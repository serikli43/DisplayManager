import SwiftUI

@main
struct DisplayManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // 1. Wir erstellen den Manager hier (als Quelle der Wahrheit)
    @StateObject private var monitorManager = MonitorManager()

    var body: some Scene {
        MenuBarExtra("Monitor Control", systemImage: "sun.max.circle.fill") {
            MenuView()
                .environmentObject(monitorManager) // Manager an Menü weitergeben
        }
        .menuBarExtraStyle(.window)

        Settings{
            SettingsView()
                .environmentObject(monitorManager) // Manager ans Fenster weitergebend
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {}
}
