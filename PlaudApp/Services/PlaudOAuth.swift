#if os(macOS)
import AppKit
import CryptoKit
import Foundation
import Network

enum PlaudOAuthError: LocalizedError {
    case notConfigured
    case listenFailed(String)
    case timeout
    case denied(String)
    case stateMismatch
    case missingCode
    case exchangeFailed(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Connexion Plaud intégrée non configurée (client OAuth absent)."
        case .listenFailed(let reason):
            return "Impossible d'écouter sur localhost:8199 (\(reason)). Un autre login Plaud est peut-être en cours."
        case .timeout: return "Connexion Plaud abandonnée : aucune réponse du navigateur en 2 minutes."
        case .denied(let reason): return "Connexion Plaud refusée : \(reason)"
        case .stateMismatch: return "Réponse OAuth invalide (state différent) — connexion annulée."
        case .missingCode: return "Réponse OAuth sans code d'autorisation."
        case .exchangeFailed(let code): return "Échange du code Plaud refusé (HTTP \(code))."
        }
    }
}

extension Notification.Name {
    /// Émise après une connexion Plaud réussie depuis les Réglages : la liste se recharge.
    static let plaudDidLogin = Notification.Name("PlaudDidLogin")
}

/// Connexion Plaud dans l'app : OAuth 2 « authorization code » + PKCE (S256) avec
/// redirection loopback, comme le login du MCP Plaud. Les tokens obtenus sont écrits
/// dans `~/.plaud/tokens-mcp.json` via `TokenStore`, donc partagés avec le MCP et le CLI.
///
/// Le client OAuth est dédié à l'app et se lit dans l'Info.plist (`PlaudOAuthClientID`) :
/// tant qu'il est vide, la connexion intégrée est désactivée et l'UI ne la propose pas.
actor PlaudOAuth {
    static let shared = PlaudOAuth()

    /// Client OAuth public (sans secret) attribué par Plaud à Plaud Companion.
    static var clientID: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "PlaudOAuthClientID") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static var isConfigured: Bool { clientID != nil }

    private let port: UInt16 = 8199
    private let callbackPath = "/auth/callback"
    private let authorizationURL = "https://web.plaud.ai/platform/oauth"
    private let tokenURL = URL(string:
        "https://platform.plaud.ai/developer/api/oauth/third-party/access-token")!
    private var redirectURI: String { "http://localhost:\(port)\(callbackPath)" }

    private var inProgress = false

    /// Ouvre la page de connexion Plaud dans le navigateur, attend la redirection
    /// sur localhost puis échange le code contre des tokens.
    func login() async throws {
        guard let clientID = Self.clientID else { throw PlaudOAuthError.notConfigured }
        guard !inProgress else { throw PlaudOAuthError.listenFailed("connexion déjà en cours") }
        inProgress = true
        defer { inProgress = false }

        let verifier = Self.randomBase64URL(byteCount: 32)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomBase64URL(byteCount: 16)

        var comps = URLComponents(string: authorizationURL)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authURL = comps.url else { throw URLError(.badURL) }

        let server = OAuthCallbackServer(port: port, path: callbackPath)
        let items = try await server.waitForCallback(timeout: 120) {
            DispatchQueue.main.async { NSWorkspace.shared.open(authURL) }
        }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw PlaudOAuthError.denied(value("error_description") ?? error)
        }
        guard value("state") == state else { throw PlaudOAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw PlaudOAuthError.missingCode }

        try await exchange(code: code, verifier: verifier, state: state, clientID: clientID)
    }

    private func exchange(code: String, verifier: String, state: String, clientID: String) async throws {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(plaudUserAgent, forHTTPHeaderField: "User-Agent")
        // Client public : identifiant seul en Basic, secret vide.
        let basic = Data("\(clientID):".utf8).base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        req.httpBody = Self.formEncode([
            ("code", code),
            ("redirect_uri", redirectURI),
            ("code_verifier", verifier),
            ("state", state),
        ]).data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw PlaudOAuthError.exchangeFailed(http.statusCode)
        }

        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let tokenType: String?
            let expiresIn: Double?
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case tokenType = "token_type"
                case expiresIn = "expires_in"
            }
        }
        let body = try JSONDecoder().decode(TokenResponse.self, from: data)
        try await TokenStore.shared.store(TokenSet(
            accessToken: body.accessToken,
            refreshToken: body.refreshToken,
            tokenType: body.tokenType ?? "Bearer",
            expiresAt: body.expiresIn.map { Date().timeIntervalSince1970 * 1000 + $0 * 1000 }
        ))
    }

    // MARK: - Helpers

    private static func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ pairs: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return pairs.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
    }
}

/// Mini serveur HTTP sur l'interface loopback (IPv4 et IPv6 : les navigateurs
/// résolvent souvent `localhost` en `::1`) qui attend une seule redirection OAuth.
private final class OAuthCallbackServer: @unchecked Sendable {
    private let port: UInt16
    private let path: String
    private let queue = DispatchQueue(label: "PlaudOAuth.callback")
    // Accédés uniquement sur `queue`.
    private var listener: NWListener?
    private var continuation: CheckedContinuation<[URLQueryItem], Error>?
    private var finished = false

    init(port: UInt16, path: String) {
        self.port = port
        self.path = path
    }

    func waitForCallback(timeout: TimeInterval,
                         onReady: @escaping @Sendable () -> Void) async throws -> [URLQueryItem] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                queue.async { self.start(cont, timeout: timeout, onReady: onReady) }
            }
        } onCancel: {
            queue.async { self.finish(.failure(CancellationError())) }
        }
    }

    private func start(_ cont: CheckedContinuation<[URLQueryItem], Error>,
                       timeout: TimeInterval, onReady: @escaping @Sendable () -> Void) {
        if finished {
            cont.resume(throwing: CancellationError())
            return
        }
        continuation = cont

        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            finish(.failure(PlaudOAuthError.listenFailed(error.localizedDescription)))
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: onReady()
            case .failed(let error):
                self?.finish(.failure(PlaudOAuthError.listenFailed(error.localizedDescription)))
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: self.queue)
            self.receive(on: conn, buffer: Data())
        }
        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(.failure(PlaudOAuthError.timeout))
        }
    }

    private func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let header = String(data: buffer, encoding: .utf8), header.contains("\r\n\r\n") {
                self.handle(request: header, on: conn)
            } else if isComplete || error != nil || buffer.count > 65_536 {
                conn.cancel()
            } else {
                self.receive(on: conn, buffer: buffer)
            }
        }
    }

    private func handle(request: String, on conn: NWConnection) {
        let requestLine = request.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2,
              let comps = URLComponents(string: "http://localhost" + parts[1]),
              comps.path == path else {
            respond(on: conn, status: "404 Not Found",
                    title: "Plaud Companion", message: "Cette page peut être fermée.")
            return
        }
        let items = comps.queryItems ?? []
        if items.contains(where: { $0.name == "error" }) {
            respond(on: conn, status: "200 OK", title: "Connexion refusée",
                    message: "Retourne dans Plaud Companion.")
        } else {
            respond(on: conn, status: "200 OK", title: "Connexion Plaud reçue",
                    message: "Tu peux fermer cet onglet et revenir dans Plaud Companion.")
        }
        finish(.success(items))
    }

    private func respond(on conn: NWConnection, status: String, title: String, message: String) {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>Plaud Companion</title></head>\
        <body style="font-family:system-ui;padding:2rem;text-align:center;">\
        <h1>\(title)</h1><p>\(message)</p></body></html>
        """
        let body = Data(html.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n" +
            "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func finish(_ result: Result<[URLQueryItem], Error>) {
        guard !finished else { return }
        finished = true
        listener?.cancel()
        listener = nil
        continuation?.resume(with: result)
        continuation = nil
    }
}
#endif
