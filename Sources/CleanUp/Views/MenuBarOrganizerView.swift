import SwiftUI

struct MenuBarOrganizerView: View {
    @ObservedObject private var organizer = MenuBarOrganizer.shared

    var body: some View {
        VStack(spacing: 0) {
            StatBanner(icon: "menubar.rectangle",
                       tint: organizer.enabled ? (organizer.isCollapsed ? .green : .blue) : .gray,
                       title: organizer.enabled
                           ? (organizer.isCollapsed ? "Menu bar decluttered" : "Hidden icons are showing")
                           : "Menu bar organizer is off",
                       caption: organizer.enabled
                           ? "Click the ‹ chevron in the menu bar, or the button below, to toggle"
                           : "Turn it on to hide menu bar icons you rarely need")

            List {
                Section {
                    Toggle("Enable menu bar organizer", isOn: Binding(
                        get: { organizer.enabled },
                        set: { organizer.setEnabled($0, collapseNow: false) }
                    ))
                    .toggleStyle(.switch)

                    if organizer.enabled {
                        HStack {
                            Text(organizer.isCollapsed ? "Hidden icons are tucked away."
                                                       : "All icons are currently visible.")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(organizer.isCollapsed ? "Show Icons" : "Hide Icons") {
                                organizer.toggleCollapsed()
                            }
                        }
                    }
                }

                if organizer.enabled {
                    Section("One-time setup") {
                        setupStep(number: "1", icon: "command",
                                  text: "Hold ⌘ and drag any menu bar icon to the LEFT of CleanUp's thin separator mark ❘ — those icons become hideable.")
                        setupStep(number: "2", icon: "chevron.left.circle",
                                  text: "Click the chevron ‹ next to the separator to hide them. Click again to bring them back.")
                        setupStep(number: "3", icon: "arrow.uturn.backward",
                                  text: "Change your mind anytime — ⌘-drag an icon back to the right of the separator and it always stays visible.")
                    }

                    Section {
                        Picker("Hide again automatically", selection: $organizer.autoHideSeconds) {
                            Text("Never").tag(0)
                            Text("After 5 seconds").tag(5)
                            Text("After 10 seconds").tag(10)
                            Text("After 30 seconds").tag(30)
                            Text("After 1 minute").tag(60)
                        }
                        .pickerStyle(.menu)
                        Toggle("Start with icons hidden when CleanUp launches",
                               isOn: $organizer.startCollapsed)
                            .toggleStyle(.switch)
                    } header: {
                        Text("Options")
                    } footer: {
                        Text("macOS doesn't let any app control another app's menu bar icons — the ⌘-drag arrangement is how you choose what hides. CleanUp's own separator and chevron are the only things it adds to your bar, and turning the organizer off removes them.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle("Menu Bar")
    }

    private func setupStep(number: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(.tint.opacity(0.15), in: Circle())
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}
