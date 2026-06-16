import SwiftUI

/// The major, user-customizable sections of the menu panel. Raw values are the
/// stable identifiers persisted in the saved order and the collapsed set, so
/// renaming a case would orphan a user's stored layout — keep them stable.
enum PanelSectionID: String, CaseIterable, Identifiable {
    case keepAwake, mixer, system, network, power

    var id: String { rawValue }

    /// Localized display name, reused from the existing section titles.
    func title(_ s: Strings) -> String {
        switch self {
        case .keepAwake: return s.keepAwakeTitle
        case .mixer: return s.mixerSection
        case .system: return s.systemSection
        case .network: return s.networkSection
        case .power: return s.powerSection
        }
    }
}

/// Persisted panel layout: the order the sections appear in and which ones are
/// collapsed. The order is a comma-joined list of ids; any section missing from
/// a saved order (e.g. one added in a later version) is appended in its canonical
/// position, so a section can never silently disappear. Collapsed sections are a
/// comma-joined set of ids.
enum PanelLayout {
    private static var defaults: UserDefaults { .standard }

    /// The sections in display order: the user's saved order first, then any not
    /// yet listed, in their canonical order.
    static var order: [PanelSectionID] {
        let saved = (defaults.string(forKey: DefaultsKey.panelSectionOrder) ?? "")
            .split(separator: ",")
            .compactMap { PanelSectionID(rawValue: String($0)) }
        var seen = Set<PanelSectionID>()
        var result: [PanelSectionID] = []
        for id in saved where seen.insert(id).inserted { result.append(id) }
        for id in PanelSectionID.allCases where seen.insert(id).inserted { result.append(id) }
        return result
    }

    static func setOrder(_ ids: [PanelSectionID]) {
        defaults.set(ids.map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.panelSectionOrder)
    }

    static func isCollapsed(_ id: PanelSectionID) -> Bool {
        collapsedSet().contains(id.rawValue)
    }

    static func setCollapsed(_ collapsed: Bool, for id: PanelSectionID) {
        var set = collapsedSet()
        if collapsed { set.insert(id.rawValue) } else { set.remove(id.rawValue) }
        defaults.set(set.sorted().joined(separator: ","), forKey: DefaultsKey.panelCollapsedSections)
    }

    static func resetCollapsedSectionsOnce(for version: String) {
        guard defaults.string(forKey: DefaultsKey.panelCollapsedResetVersion) != version else { return }
        defaults.removeObject(forKey: DefaultsKey.panelCollapsedSections)
        defaults.set(version, forKey: DefaultsKey.panelCollapsedResetVersion)
    }

    private static func collapsedSet() -> Set<String> {
        Set((defaults.string(forKey: DefaultsKey.panelCollapsedSections) ?? "")
            .split(separator: ",").map(String.init))
    }
}

/// A major panel section with a collapsible header. The header row (the section
/// title plus a chevron) toggles a persisted collapsed state; collapsing hides
/// the body but keeps the header so it can be reopened. Every major component in
/// the panel uses this so they all collapse and reorder consistently.
struct PanelSection<Content: View>: View {
    private let id: PanelSectionID
    private let title: String
    private let content: Content
    @State private var collapsed: Bool

    init(_ id: PanelSectionID, title: String, @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        self.content = content()
        _collapsed = State(initialValue: PanelLayout.isCollapsed(id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    sectionTitle(title)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                content
            }
        }
    }

    private func toggle() {
        withAnimation(.easeOut(duration: 0.18)) { collapsed.toggle() }
        PanelLayout.setCollapsed(collapsed, for: id)
    }
}
