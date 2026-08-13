import SwiftUI

@main
struct CleanUpApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .frame(minWidth: 900, minHeight: 600)
        }

        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "wand.and.stars")
        }
    }
}

struct MenuBarContent: View {
    @StateObject private var disk = DiskStatus()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Free space: \(disk.freeShort) of \(Format.bytes(disk.total))")
        Divider()
        Button("Open CleanUp") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button("Smart Scan Now") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
            AppState.shared.requestSmartScan()
        }
        Divider()
        Button("Quit CleanUp") { NSApp.terminate(nil) }
    }
}
