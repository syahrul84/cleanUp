import SwiftUI

struct MemoryWatchView: View {
    @ObservedObject private var watch = MemoryWatch.shared

    var body: some View {
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
            } footer: {
                Text("macOS can't hard-cap an app's memory — no tool can. Memory Watch alerts you when an app crosses your level, so you can quit or relaunch it before it swamps your Mac. Checks every 5 seconds; alerts repeat at most every 5 minutes per app.")
                    .font(.caption).foregroundStyle(.tertiary)
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
