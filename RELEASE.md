# Releasing Plaud Companion

This project ships a signed & **notarized** `.dmg` so users can open it without
Gatekeeper warnings. The whole pipeline lives in [`Scripts/release.sh`](Scripts/release.sh):

```
build (Release) → codesign (Developer ID + Hardened Runtime) → DMG (Finder layout)
   → notarize (Apple) → staple → ready to publish
```

## Prerequisites (one time)

1. **Apple Developer Program** membership and a **Developer ID Application** certificate installed in your login keychain. Check it's there:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
2. **A notary credential profile** stored in the keychain (asks for an [app‑specific password](https://support.apple.com/en-us/102654)):
   ```bash
   xcrun notarytool store-credentials "PlaudCompanion-Notary" \
     --apple-id "you@example.com" --team-id "KFLACS69T9"
   ```
   > The notary credentials are tied to your Apple account, not to the app — you can reuse a profile across projects by passing `NOTARY_PROFILE=<name>`.
3. **XcodeGen**: `brew install xcodegen`.

## Cut a release

```bash
./Scripts/release.sh 1.0.0
```

This produces `PlaudCompanion-1.0.0.dmg`, fully signed, notarized and stapled.

Override the identity or notary profile if needed:

```bash
SIGNING_IDENTITY="Developer ID Application: … (TEAMID)" \
NOTARY_PROFILE="MyProfile" \
./Scripts/release.sh 1.0.0
```

## Publish on GitHub

```bash
gh release create v1.0.0 ./PlaudCompanion-1.0.0.dmg \
  --title "v1.0.0" --generate-notes
```

The README's `Release` badge updates automatically from the GitHub API once a release exists.

## Versioning

- `MARKETING_VERSION` (user‑facing, e.g. `1.0.0`) is injected by the script from the `<version>` argument → `CFBundleShortVersionString`.
- `CURRENT_PROJECT_VERSION` (build number) is derived from the git commit count → `CFBundleVersion`.
- Defaults live in [`project.yml`](project.yml); the script overrides them per build.

## Notes

- `CODE_SIGNING_ALLOWED=NO` is used during `xcodebuild`, then the app is signed manually. This sidesteps the macOS Sequoia `com.apple.provenance` xattr that otherwise breaks CLI `codesign`.
- The app uses the **Hardened Runtime** (`--options runtime`) and **no sandbox** (it reads the shared Plaud token at `~/.plaud/tokens-mcp.json`).
- Apple's timestamp server is occasionally flaky; the script retries `codesign` up to 5 times.
- The DMG itself is not committed to git (`*.dmg` is ignored) — it lives only on the Releases page.
