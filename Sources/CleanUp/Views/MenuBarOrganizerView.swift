import SwiftUI

struct MenuBarOrganizerView: View {
    @ObservedObject private var organizer = MenuBarOrganizer.shared

    private var statusTint: Color {
        organizer.enabled ? (organizer.isCollapsed ? .green : .blue) : .gray
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                setupCard
                if organizer.enabled { optionsCard }
            }
            .padding(16)
        }
        .navigationTitle("Menu Bar")
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
                Text(organizer.enabled
                     ? "Click the chevron in your menu bar, or the button here, to hide or show icons."
                     : "Turn it on to tuck away menu bar icons you rarely need.")
                    .font(.callout).foregroundStyle(.secondary)
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
