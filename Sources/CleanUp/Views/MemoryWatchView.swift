import SwiftUI

struct MemoryWatchView: View {
    @ObservedObject private var watch = MemoryWatch.shared

    private var overCount: Int { watch.apps.filter(\.isOver).count }
    private var watchedCount: Int { watch.apps.filter { $0.threshold != nil }.count }
    private var largest: Int64 { watch.apps.map(\.footprint).max() ?? 1 }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summary
                if watch.notificationsDenied { notificationsWarning }
                SectionCard(title: "Running Apps (\(watch.apps.count))", icon: "app.badge", tint: .orange,
                            info: "Set an alert level for any app. When it uses more memory than that, CleanUp sends a notification with Quit and Relaunch buttons. “Default” means no alert — macOS manages the app normally. Memory is checked every 5 seconds.") {
                    ForEach(watch.apps) { app in
                        row(app)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Memory Watch")
        .navigationSubtitle("\(watch.apps.count) apps running")
        .onAppear { watch.start() }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            IconTile(systemName: "memorychip", tint: overCount > 0 ? .red : .green, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Format.bytes(watch.apps.reduce(0) { $0 + $1.footprint })) in use by \(watch.apps.count) apps")
                    .font(.headline)
                Text(overCount > 0
                     ? "\(overCount) app\(overCount == 1 ? "" : "s") over their alert level"
                     : watchedCount == 0 ? "No alerts set — pick a level on any app below"
                                         : "\(watchedCount) app\(watchedCount == 1 ? "" : "s") watched · all within their alert levels")
                    .font(.caption).foregroundStyle(overCount > 0 ? .red : .secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var notificationsWarning: some View {
        HStack(spacing: 12) {
            IconTile(systemName: "bell.slash", tint: .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are off").font(.callout.bold())
                Text("Alerts can't be shown until you allow notifications for CleanUp.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.notifications")!)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func row(_ app: WatchedApp) -> some View {
        let tint: Color = app.isOver ? .red : .orange
        HoverRow(highlight: app.isOver ? .red : .primary) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 28, height: 28)
            } else {
                IconTile(systemName: "app", tint: .gray)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(app.name).lineLimit(1)
                    if app.isOver {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .help("Above its alert level")
                    }
                    Spacer()
                    if app.footprint > 0 {
                        Text(Format.bytes(app.footprint))
                            .font(.callout).monospacedDigit()
                            .foregroundStyle(app.isOver ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                            .help("macOS doesn't let CleanUp read this app's memory usage")
                    }
                }
                UsageBar(fraction: Double(app.footprint) / Double(max(largest, 1)), tint: tint)
            }
            thresholdMenu(app)
        }
    }

    private func thresholdMenu(_ app: WatchedApp) -> some View {
        Menu {
            Button("No alert (Default)") { watch.setThreshold(nil, for: app.id) }
            Divider()
            ForEach(MemoryWatch.thresholdOptions, id: \.self) { bytes in
                Button("Alert above \(Format.bytes(bytes))") { watch.setThreshold(bytes, for: app.id) }
            }
        } label: {
            Label(app.threshold.map { "Above \(Format.bytes($0))" } ?? "No alert",
                  systemImage: app.threshold == nil ? "bell.slash" : "bell.fill")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(app.threshold == nil ? AnyShapeStyle(.quaternary)
                                         : AnyShapeStyle(Color.orange.opacity(0.18)),
                    in: Capsule())
        .frame(width: 150, alignment: .trailing)
    }
}
