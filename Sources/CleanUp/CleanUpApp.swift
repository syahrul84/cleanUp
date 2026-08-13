import SwiftUI

/// Detects a launch triggered by the login item and hides the main window,
/// so booting the Mac brings up only the menu bar widget.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if launchedAtLogin {
            DispatchQueue.main.async {
                NSApp.windows.filter { $0.canBecomeMain }.forEach { $0.close() }
            }
        }
    }
}

@main
struct CleanUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Monochrome template icon echoing the logo's shape — a circular swoosh
    /// with an arrow through it. As a template image, the menu bar tints it
    /// black or white automatically to match the system appearance.
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()

            // Swoosh: open ring with the gap at the top-right, where the arrow exits.
            let swoosh = NSBezierPath()
            swoosh.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 6.5,
                             startAngle: 130, endAngle: 350, clockwise: false)
            swoosh.lineWidth = 2.2
            swoosh.lineCapStyle = .round
            swoosh.stroke()

            // Arrow shaft, bottom-left to top-right.
            let shaft = NSBezierPath()
            shaft.move(to: NSPoint(x: 5.5, y: 5.5))
            shaft.line(to: NSPoint(x: 11.5, y: 11.5))
            shaft.lineWidth = 2.2
            shaft.lineCapStyle = .round
            shaft.stroke()

            // Arrowhead pointing to the top-right.
            let head = NSBezierPath()
            head.move(to: NSPoint(x: 14.5, y: 14.5))
            head.line(to: NSPoint(x: 14.5, y: 9.0))
            head.line(to: NSPoint(x: 9.0, y: 14.5))
            head.close()
            head.fill()

            return true
        }
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .frame(minWidth: 900, minHeight: 600)
        }

        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarContent: View {
    @StateObject private var disk = DiskStatus()
    @StateObject private var stats = SystemStats()
    @StateObject private var loginItem = LoginItem()
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

            Toggle("Launch at login", isOn: Binding(
                get: { loginItem.enabled },
                set: { loginItem.set($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            if let error = loginItem.lastError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }

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
