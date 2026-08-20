import SwiftUI
#if os(macOS)
import Sparkle
#endif

@main
struct PlaudApp: App {
    @State private var settings = AppSettings()

    #if os(macOS)
    private let updaterController: SPUStandardUpdaterController = {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Vérification en arrière-plan OK, mais jamais de téléchargement/installation
        // sans consentement : l'app ne doit pas être tuée/remplacée en pleine session.
        controller.updater.automaticallyChecksForUpdates = true
        controller.updater.automaticallyDownloadsUpdates = false
        return controller
    }()
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(settings.t("check_updates")) {
                    updaterController.checkForUpdates(nil)
                }
            }
        }
        #endif

        // Réglages via la scène native macOS (⌘,). Sur iOS, les réglages sont
        // présentés en feuille depuis `ContentView` (pas de scène `Settings`).
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(settings)
        }
        #endif
    }
}
