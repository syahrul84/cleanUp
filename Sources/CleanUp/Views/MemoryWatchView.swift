import SwiftUI

struct MemoryWatchView: View {
    @ObservedObject private var watch = MemoryWatch.shared

    private var overCount: Int { watch.apps.filter(\.isOver).count }

    var body: some View {
        VStack(spacing: 0) {
        if !watch.apps.isEmpty {
            StatBanner(icon: "memorychip",
                       tint: overCount > 0 ? .orange : .green,
                       title: "\(Format.bytes(watch.apps.reduce(0) { $0 + $1.footprint })) in use by \(watch.apps.count) apps",
                       caption: overCount > 0
                           ? "\(overCount) app\(overCount == 1 ? "" : "s") over their alert level"
                           : "All apps within their alert levels")
        }
        List {
            if watch.notificationsDenied {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Notifications are off", systemImage: "bell.slash")
                            .font(.callout.bold())
                        Text("Alerts can't be shown. Allow notifications for CleanUp in System Settings.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open Notification Settings") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.notifications")!)
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                ForEach(watch.apps) { app in
                    row(app)
                }
            } header: {
                Text("Running applications")
            }
        }
        }
        .navigationTitle("Memory Watch")
        .navigationSubtitle("\(watch.apps.count) apps running")
        .onAppear { watch.start() }
    }

    @ViewBuilder
    private func row(_ app: WatchedApp) -> some View {
        HStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: "app").frame(width: 24)
            }
            Text(app.name).lineLimit(1)
            if app.isOver {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Above its alert level")
            }
            Spacer()
            Text(Format.bytes(app.footprint))
                .monospacedDigit()
                .foregroundStyle(app.isOver ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            thresholdPicker(app)
        }
        .padding(.vertical, 2)
    }

    private func thresholdPicker(_ app: WatchedApp) -> some View {
        Picker("", selection: Binding<Int64?>(
            get: { app.threshold },
            set: { watch.setThreshold($0, for: app.id) }
        )) {
            Text("Default").tag(nil as Int64?)
            Divider()
            ForEach(MemoryWatch.thresholdOptions, id: \.self) { bytes in
                Text("Alert at \(Format.bytes(bytes))").tag(bytes as Int64?)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 150)
    }
}
