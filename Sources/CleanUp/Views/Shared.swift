import SwiftUI

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

/// "Move N items (X) to Trash" button with a confirmation dialog and result alert.
struct TrashActionButton: View {
    let count: Int
    let size: Int64
    let action: () -> (trashed: Int, errors: [String])
    var onDone: () -> Void = {}

    @State private var confirming = false
    @State private var resultMessage: String?

    var body: some View {
        Button {
            confirming = true
        } label: {
            Label("Move \(count) item\(count == 1 ? "" : "s") (\(Format.bytes(size))) to Trash",
                  systemImage: "trash")
        }
        .buttonStyle(.borderedProminent)
        .disabled(count == 0)
        .confirmationDialog("Move \(count) item\(count == 1 ? "" : "s") to Trash?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                let result = action()
                var message = "Moved \(result.trashed) item\(result.trashed == 1 ? "" : "s") to Trash."
                if !result.errors.isEmpty {
                    message += "\n\n\(result.errors.count) failed (likely needs Full Disk Access):\n"
                        + result.errors.prefix(5).joined(separator: "\n")
                }
                resultMessage = message
                onDone()
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
