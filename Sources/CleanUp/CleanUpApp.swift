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
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarContent: View {
    @StateObject private var disk = DiskStatus()
    @StateObject private var stats = SystemStats()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CleanUp").font(.headline)

            statRow(icon: "cpu", title: "CPU",
                    value: String(format: "%.0f%%", stats.cpuPercent),
                    fraction: stats.cpuPercent / 100)

            statRow(icon: "memorychip", title: "Memory",
                    value: "\(Format.bytes(stats.memUsed)) of \(Format.bytes(stats.memTotal))",
                    fraction: Double(stats.memUsed) / Double(max(stats.memTotal, 1)))

            statRow(icon: "internaldrive", title: "Disk free",
                    value: "\(disk.freeShort) of \(Format.bytes(disk.total))",
                    fraction: 1 - Double(disk.free) / Double(max(disk.total, 1)))

            Divider()

            HStack {
                Button("Open CleanUp") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                Button("Smart Scan") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                    AppState.shared.requestSmartScan()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit CleanUp")
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            disk.refresh()
            stats.start()
        }
        .onDisappear { stats.stop() }
    }

    @ViewBuilder
    private func statRow(icon: String, title: String, value: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label(title, systemImage: icon).font(.callout)
                Spacer()
                Text(value).font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .progressViewStyle(.linear)
                .tint(fraction > 0.85 ? .red : fraction > 0.65 ? .orange : .accentColor)
        }
    }
}
