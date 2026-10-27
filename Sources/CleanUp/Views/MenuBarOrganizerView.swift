import SwiftUI

struct MenuBarOrganizerView: View {
    @ObservedObject private var organizer = MenuBarOrganizer.shared
    @State private var menuBarApps: [MenuBarConcealer.MenuBarApp] = []
    @State private var hasAccessibility = MenuBarConcealer.hasAccessibility

    private var statusTint: Color {
        organizer.enabled ? (organizer.isCollapsed ? .green : .blue) : .gray
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                if organizer.usesSystemHiding {
                    appsCard
                } else {
                    setupCard
                }
                if organizer.enabled { optionsCard }
            }
            .padding(16)
        }
        .navigationTitle("Menu Bar")
        .onAppear(perform: refreshApps)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshApps()
        }
    }

    private func refreshApps() {
        hasAccessibility = MenuBarConcealer.hasAccessibility
        guard organizer.usesSystemHiding, hasAccessibility else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = MenuBarConcealer.appsWithMenuBarIcons()
            DispatchQueue.main.async { menuBarApps = apps }
        }
    }

    // MARK: macOS 27+: choose apps to hide

    /// Hidden apps that aren't running right now still show, so they can be
    /// un-hidden.
    private var listedApps: [MenuBarConcealer.MenuBarApp] {
        let running = Set(menuBarApps.map(\.bundleID))
        let offline = organizer.hiddenApps.subtracting(running).sorted().map { id -> MenuBarConcealer.MenuBarApp in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            return MenuBarConcealer.MenuBarApp(
                bundleID: id,
                name: url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id,
                icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) })
        }
        return menuBarApps + offline
    }

    private var appsCard: some View {
        SectionCard(title: "Icons to hide", icon: "eye.slash", tint: .accentColor,
                    info: "On macOS 27, the menu bar arranges itself, so ⌘-dragging no longer decides what hides. Pick the apps whose icons the chevron should tuck away. The clock, Wi-Fi, battery and Control Center always stay. While icons are hidden, macOS may ignore clicks on those system items — click the chevron first. A few apps (such as InstantView) and the camera/microphone indicator are hidden along with your picks; macOS decides this, not CleanUp.") {
            if !hasAccessibility {
                HoverRow {
                    IconTile(systemName: "hand.raised", tint: .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow Accessibility to list menu bar icons")
                        Text("CleanUp uses it only to see which apps have an icon in the menu bar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Allow…") { MenuBarConcealer.requestAccessibility() }
                }
            } else if listedApps.isEmpty {
                Text("Looking for apps with menu bar icons…")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(8)
            }
            ForEach(listedApps) { app in
                HoverRow {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                    } else {
                        IconTile(systemName: "app", tint: .gray, size: 24)
                    }
                    Text(app.name)
                    Spacer()
                    Text(organizer.hiddenApps.contains(app.bundleID) ? "Hidden" : "Visible")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("", isOn: Binding(
                        get: { organizer.hiddenApps.contains(app.bundleID) },
                        set: { hide in
                            if hide { organizer.hiddenApps.insert(app.bundleID) }
                            else { organizer.hiddenApps.remove(app.bundleID) }
                        }))
                    .labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    // MARK: Status

    private var statusCard: some View {
        HStack(spacing: 14) {
            IconTile(systemName: organizer.isCollapsed ? "eye.slash" : "menubar.rectangle",
                     tint: statusTint, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(organizer.enabled
                     ? (organizer.isCollapsed ? "Menu bar decluttered" : "Hidden icons are showing")
                     : "Menu bar organizer is off")
                    .font(.title3.bold())
                if organizer.enabled && organizer.usesSystemHiding && organizer.hiddenApps.isEmpty {
                    Label("No icons are chosen to hide yet. Pick them under Icons to hide.",
                          systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.orange)
                } else {
                    Text(organizer.enabled
                         ? "Click the chevron in your menu bar, or the button here, to hide or show icons."
                         : "Turn it on to tuck away menu bar icons you rarely need.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if organizer.enabled {
                Button {
                    organizer.toggleCollapsed()
                } label: {
                    Label(organizer.isCollapsed ? "Show Icons" : "Hide Icons",
                          systemImage: organizer.isCollapsed ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderedProminent)
            }
            Toggle("", isOn: Binding(
                get: { organizer.enabled },
                set: { organizer.setEnabled($0, collapseNow: false) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .help(organizer.enabled ? "Turn the organizer off (removes its items from the menu bar)"
                                    : "Turn the organizer on")
        }
        .padding(16)
        .background(statusTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Setup

    private var setupCard: some View {
        SectionCard(title: "How it works", icon: "lightbulb", tint: .yellow,
                    info: "macOS doesn't let any app move or hide another app's menu bar icons — the ⌘-drag arrangement is how you choose what hides. CleanUp's own separator and chevron are the only things it adds to your bar, and turning the organizer off removes them.") {
            HStack(alignment: .top, spacing: 10) {
                stepTile(number: 1, icon: "command",
                         title: "Arrange once",
                         text: "Hold ⌘ and drag icons you rarely use to the left of CleanUp's thin separator ❘.")
                stepTile(number: 2, icon: "chevron.left.circle",
                         title: "Hide with a click",
                         text: "Click the chevron next to the separator. Everything left of it disappears.")
                stepTile(number: 3, icon: "arrow.uturn.backward.circle",
                         title: "Undo anytime",
                         text: "⌘-drag an icon back to the right of the separator and it always stays visible.")
            }
            .padding(4)
        }
    }

    private func stepTile(number: Int, icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor, in: Circle())
                Spacer()
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            Text(title).font(.callout.bold())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Options

    private var optionsCard: some View {
        SectionCard(title: "Options", icon: "slider.horizontal.3", tint: .accentColor) {
            HoverRow {
                IconTile(systemName: "timer", tint: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide again automatically")
                    Text("After you show hidden icons, tuck them away again on their own.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $organizer.autoHideSeconds) {
                    Text("Never").tag(0)
                    Text("After 5 seconds").tag(5)
                    Text("After 10 seconds").tag(10)
                    Text("After 30 seconds").tag(30)
                    Text("After 1 minute").tag(60)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            HoverRow {
                IconTile(systemName: "power", tint: .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start with icons hidden")
                    Text("When CleanUp launches, the hideable icons start tucked away.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $organizer.startCollapsed)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}
