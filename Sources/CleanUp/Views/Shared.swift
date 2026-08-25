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
