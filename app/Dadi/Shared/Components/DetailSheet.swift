import SwiftUI

/// The 4 pt-scale spacing every sheet shares.
enum SheetLayout {
    /// Space between the header, the facts, the rail and the sections.
    static let gap: CGFloat = 16
    /// Space between inset cards.
    static let inner: CGFloat = 12
    /// Space from the sheet's edges to its content.
    static let inset: CGFloat = 24
}

/// The one anatomy of a detail sheet, as Thaali's `DetailCard`: a header (title over one situation line), a block of
/// label/value fact rows, a single action rail under a hairline, then inset cards. Every gap is one step of the 4 pt
/// scale (`gap` between blocks, `inner` inside the inset stack) and the content sits 24 pt from the sheet's edges, so
/// rows start at the same offsets from one sheet to the next.
struct DetailSheet<Situation: View, Facts: View, Rail: View, Sections: View>: View {
    let title: String
    var hasFacts = true
    var hasRail = true
    var hasSections = true
    @ViewBuilder let situation: () -> Situation
    @ViewBuilder let facts: () -> Facts
    @ViewBuilder let rail: () -> Rail
    @ViewBuilder let sections: () -> Sections

    var body: some View {
        VStack(alignment: .leading, spacing: SheetLayout.gap) {
            SheetHeader(title: title, situation: situation)
            if hasFacts { VStack(spacing: 0, content: facts) }
            if hasRail {
                Divider().overlay(Color.rule)
                VStack(alignment: .leading, spacing: 8, content: rail)
            }
            if hasSections { VStack(alignment: .leading, spacing: SheetLayout.inner, content: sections) }
        }
        .padding(SheetLayout.inset)
    }
}
