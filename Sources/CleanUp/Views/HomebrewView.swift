import SwiftUI

struct HomebrewView: View {
    @ObservedObject private var brew = HomebrewService.shared
    @State private var confirmUninstall: BrewPackage?
    @State private var showLog = false

    var body: some View {
        Group {
            if !brew.available {
                VStack(spacing: 12) {
                    Image(systemName: "mug").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("Homebrew is not installed on this Mac.")
                        .foregroundStyle(.secondary)
                    Link("Learn about Homebrew", destination: URL(string: "https://brew.sh")!)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(brew.scanning ? "Scanning…" : "Scan", systemImage: "arrow.clockwise") {
                    brew.scan()
                }
                .disabled(brew.scanning || brew.busyTitle != nil)
            }
        }
        .navigationTitle("Homebrew")
        .navigationSubtitle(brew.available && !brew.installed.isEmpty
            ? "\(brew.installed.count) packages" : "")
        .onAppear { brew.scan() }
        .confirmationDialog("Uninstall \(confirmUninstall?.name ?? "")?",
                            isPresented: .init(get: { confirmUninstall != nil },
                                               set: { if !$0 { confirmUninstall = nil } }),
                            titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) {
                if let package = confirmUninstall { brew.uninstall(package) }
                confirmUninstall = nil
            }
        } message: {
            Text("Removed via Homebrew (not the Trash). You can reinstall anytime with brew install.")
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if let title = brew.busyTitle {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(title)
                    Spacer()
                    Button(showLog ? "Hide Log" : "Show Log") { showLog.toggle() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
            }

            List {
                maintenanceSection
                updatesSection
                installedSection
            }

            if showLog || (brew.busyTitle != nil && !brew.log.isEmpty) {
                logView
            }
        }
    }

    private var maintenanceSection: some View {
        Section {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Downloads & old versions")
                        Text(brew.cleanupEstimate.map { "About \($0) reclaimable" }
                             ?? "Nothing to clean right now")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "sparkles")
                }
                Spacer()
                Button("Clean Up") { brew.cleanUp() }
                    .disabled(brew.cleanupEstimate == nil || brew.busyTitle != nil)
            }
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Orphaned dependencies")
                        Text(brew.orphans.isEmpty ? "None — nothing was left behind"
                             : brew.orphans.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
                Spacer()
                Button("Remove \(brew.orphans.count)") { brew.removeOrphans() }
                    .disabled(brew.orphans.isEmpty || brew.busyTitle != nil)
            }
        } header: {
            Text("Maintenance")
        } footer: {
            Text("Actions run Homebrew's own commands — removed items don't go to the Trash, but anything can be reinstalled with brew install.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var updatesSection: some View {
        Section {
            if brew.outdated.isEmpty {
                Text(brew.scanning ? "Checking…" : "Everything is up to date.")
                    .foregroundStyle(.secondary)
            }
            ForEach(brew.outdated) { package in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(package.name)
                        Text("\(package.installed) → \(package.latest)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if package.isCask {
                        Text("cask").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    Button("Update") { brew.upgrade(package) }
                        .disabled(brew.busyTitle != nil)
                }
            }
        } header: {
            HStack {
                Text("Updates (\(brew.outdated.count))")
                Spacer()
                if brew.outdated.count > 1 {
                    Button("Update All") { brew.upgradeAll() }
                        .font(.caption)
                        .disabled(brew.busyTitle != nil)
                }
            }
        }
    }

    private var installedSection: some View {
        Section("Installed (\(brew.installed.count))") {
            ForEach(brew.installed) { package in
                HStack {
                    Text(package.name)
                    if package.isCask {
                        Text("cask").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    Text(package.size.map { Format.bytes($0) } ?? "…")
                        .monospacedDigit().foregroundStyle(.secondary)
                    Button("Uninstall") { confirmUninstall = package }
                        .controlSize(.small)
                        .disabled(brew.busyTitle != nil)
                }
            }
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(brew.log)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .id("logEnd")
            }
            .frame(height: 140)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .top) { Divider() }
            .onChange(of: brew.log) {
                proxy.scrollTo("logEnd", anchor: .bottom)
            }
        }
    }
}
