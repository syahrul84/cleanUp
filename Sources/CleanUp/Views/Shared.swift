import SwiftUI

/// Compact dashboard card: colored title, big value, caption, optional action.
struct StatCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let caption: String
    var actionLabel: String?
    var actionDisabled = false
    var height: CGFloat = 112
    var action: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 2)
            if let actionLabel {
                Button(actionLabel) { action() }
                    .controlSize(.small)
                    .disabled(actionDisabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Full-width summary banner shown above a results list.
struct StatBanner: View {
    let icon: String
    let tint: Color
    let title: String
    let caption: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

/// Row with a checkbox, name, secondary label and size.
struct RemovalRow: View {
    @Binding var item: RemovalItem
    var showPath = false

    var body: some View {
        HStack {
            Toggle("", isOn: $item.selected).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).lineLimit(1)
                Text(showPath ? item.url.path : item.label)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Format.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }
}

/// "Move N items (X) to Trash" button with a confirmation dialog, a busy
/// indicator while trashing (large folders can take a while), and a result
/// alert. Trashing runs off the main thread so the UI never freezes.
struct TrashActionButton: View {
    let count: Int
    let size: Int64
    /// Evaluated on the main thread at confirm time; the returned URLs are
    /// then trashed on a background task.
    let urls: () -> [URL]
    var onDone: () -> Void = {}

    @State private var confirming = false
    @State private var working = false
    @State private var resultMessage: String?

    var body: some View {
        Button {
            confirming = true
        } label: {
            if working {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Moving to Trash…")
                }
            } else {
                Label("Move \(count) item\(count == 1 ? "" : "s") (\(Format.bytes(size))) to Trash",
                      systemImage: "trash")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(count == 0 || working)
        .confirmationDialog("Move \(count) item\(count == 1 ? "" : "s") to Trash?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                let targets = urls()
                working = true
                Task.detached(priority: .userInitiated) {
                    let result = FileUtils.trash(targets)
                    await MainActor.run {
                        working = false
                        var message = "Moved \(result.trashed) item\(result.trashed == 1 ? "" : "s") to Trash."
                        if !result.errors.isEmpty {
                            message += "\n\n\(result.errors.count) failed (likely needs Full Disk Access):\n"
                                + result.errors.prefix(5).joined(separator: "\n")
                        }
                        resultMessage = message
                        onDone()
                    }
                }
            }
        } message: {
            Text("Nothing is permanently deleted — you can restore items from the Trash.")
        }
        .alert("Cleanup finished", isPresented: .init(
            get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }
}

/// Standard empty/loading placeholder.
struct ScanPlaceholder: View {
    let scanning: Bool
    let emptyIcon: String
    let emptyText: String
    var progressText: String = "Scanning…"

    var body: some View {
        VStack(spacing: 12) {
            if scanning {
                ProgressView()
                Text(progressText).foregroundStyle(.secondary)
            } else {
                Image(systemName: emptyIcon).font(.system(size: 40)).foregroundStyle(.tertiary)
                Text(emptyText).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FolderPicker {
    static func choose(prompt: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.urls : []
    }
}

/// Segmented tab bar that shows an icon with each title (the system
/// segmented Picker on macOS drops Label images).
struct IconTabBar<T: Hashable>: View {
    let items: [(value: T, title: String, icon: String)]
    @Binding var selection: T
    var small = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let selected = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    Label(item.title, systemImage: item.icon)
                        .font(small ? .caption : .callout)
                        .padding(.horizontal, small ? 8 : 10)
                        .padding(.vertical, small ? 3 : 5)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(selected ? Color.accentColor : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Empty-state start screen in the Smart Scan style: big icon, title,
/// explanation and a prominent start button (shows progress while scanning).
struct ScanHero: View {
    let icon: String
    let title: String
    let description: String
    let buttonTitle: String
    var buttonIcon = "magnifyingglass"
    let scanning: Bool
    var progressText = "Scanning…"
    /// 0…1 when the scan reports measurable progress; nil shows a spinner.
    var progress: Double?
    /// Shown under the button after a scan that found nothing.
    var resultNote: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 46))
                .foregroundStyle(.tint)
            Text(title).font(.largeTitle.bold())
            Text(description)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            if scanning {
                if let progress {
                    VStack(spacing: 6) {
                        UsageBar(fraction: progress, height: 6)
                        HStack {
                            Text(progressText)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text("\(Int(progress * 100))%").monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(width: 380)
                    .padding(.top, 6)
                } else {
                    ProgressView().padding(.top, 4)
                    Text(progressText).foregroundStyle(.secondary)
                }
            } else {
                Button(action: action) {
                    Label(buttonTitle, systemImage: buttonIcon)
                        .font(.title3)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
                if let resultNote {
                    Text(resultNote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bottom bar under scan results: re-scan on the left, clean on the right.
struct ResultsActionBar<Trailing: View>: View {
    let rescanTitle: String
    var rescanIcon = "arrow.clockwise"
    let scanning: Bool
    let rescan: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            Button(rescanTitle, systemImage: rescanIcon, action: rescan)
                .disabled(scanning)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Card sections (the standard content layout)

/// Rounded panel with an icon header, optional ⓘ explanation and optional
/// trailing header control. Content rows go inside, usually `HoverRow`s.
struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = .accentColor
    var info: String?
    var accessory: AnyView?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.headline)
                if let info { InfoButton(text: info) }
                Spacer()
                accessory
            }
            .padding(.horizontal, 6)
            VStack(spacing: 0) { content() }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Row that tints on hover so wide rows read as one line.
struct HoverRow<Content: View>: View {
    var highlight: Color = .primary
    @ViewBuilder let content: () -> Content
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovered ? highlight.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

/// Small rounded tile holding an SF Symbol — the row "icon" for things
/// that aren't apps.
struct IconTile: View {
    let systemName: String
    var tint: Color = .accentColor
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.26))
    }
}

/// ⓘ that reveals an explanation in a popover (instead of footer text).
struct InfoButton: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .frame(width: 320, alignment: .leading)
                .padding()
        }
    }
}

/// Thin horizontal usage bar.
struct UsageBar: View {
    let fraction: Double
    var tint: Color = .accentColor
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if fraction > 0 {
                    Capsule().fill(tint)
                        .frame(width: max(3, geo.size.width * min(fraction, 1)))
                }
            }
        }
        .frame(height: height)
    }
}

/// Icon-only button that turns solid on hover (quit, remove…).
struct HoverIconButton: View {
    let systemName: String
    var tint: Color = .red
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovered ? .white : tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(hovered ? 0.85 : 0.12), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

/// Icon for any process: its own app icon, or — for helpers and agents —
/// the icon of the .app bundle it lives inside. Cached per pid.
enum ProcessIcons {
    private static var cache: [pid_t: NSImage?] = [:]

    static func icon(for pid: pid_t) -> NSImage? {
        if let hit = cache[pid] { return hit }
        var result: NSImage?
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            result = icon
        } else {
            var buffer = [CChar](repeating: 0, count: 4096)
            if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
                result = appIcon(containing: String(cString: buffer))
            }
        }
        cache[pid] = result
        return result
    }

    /// Icon of the outermost .app in a path, e.g. Chrome for its helpers.
    static func appIcon(containing path: String) -> NSImage? {
        guard let range = path.range(of: ".app/") ?? path.range(of: ".app", options: .backwards),
              path[range.upperBound...].isEmpty || path[range].hasSuffix("/") else { return nil }
        let bundle = String(path[..<range.lowerBound]) + ".app"
        guard FileManager.default.fileExists(atPath: bundle) else { return nil }
        return NSWorkspace.shared.icon(forFile: bundle)
    }

    /// Display name of the outermost .app in a path.
    static func appName(containing path: String) -> String? {
        guard let range = path.range(of: ".app/") ?? path.range(of: ".app", options: .backwards) else { return nil }
        let bundle = String(path[..<range.lowerBound]) + ".app"
        guard FileManager.default.fileExists(atPath: bundle) else { return nil }
        return FileManager.default.displayName(atPath: bundle).replacingOccurrences(of: ".app", with: "")
    }
}

// MARK: - Scan results

/// Headline card at the top of a results page.
struct SummaryCard: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: icon, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Selectable file/folder row: checkbox, Finder icon, name, detail, size.
/// Clicking anywhere on the row toggles the checkbox.
struct FileRow: View {
    @Binding var item: RemovalItem
    var detail: String?
    var trailingNote: String?

    var body: some View {
        HoverRow(highlight: .accentColor) {
            Toggle("", isOn: $item.selected).labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().interpolation(.high)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(detail ?? item.label)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.bytes(item.size)).font(.callout).monospacedDigit()
                if let trailingNote {
                    Text(trailingNote).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onTapGesture { item.selected.toggle() }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }
}

/// Tri-state "select all" checkbox for a group of rows.
struct SelectAllBox: View {
    @Binding var items: [RemovalItem]

    var body: some View {
        let count = items.filter(\.selected).count
        Button {
            let target = count < items.count
            for i in items.indices { items[i].selected = target }
        } label: {
            Image(systemName: count == 0 ? "square"
                  : count == items.count ? "checkmark.square.fill" : "minus.square.fill")
                .font(.system(size: 15))
                .foregroundStyle(count == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
        }
        .buttonStyle(.plain)
        .help(count < items.count ? "Select all" : "Deselect all")
    }
}
