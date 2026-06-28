import SwiftUI

@main
struct PlaudApp: App {
    @State private var settings = AppSettings()

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
