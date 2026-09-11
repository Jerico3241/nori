import SwiftUI

/// Der Kopfbereich der Merkliste: Eyebrow, Titel, Anzahl, Suche,
/// Filterknopf, Schnellfilter.
///
/// Er bleibt beim Scrollen oben stehen — wie in der Vorlage, und aus
/// demselben Grund: Suche und Schnellfilter sind die beiden Bedienelemente,
/// die man mitten in einer langen Liste braucht, und eine Merkliste kann
/// lang werden.
///
/// ## Was hier ausdrücklich **nicht** steht
///
/// Kein Umschalter „Anime | Serien". Er saß bis zuletzt in der
/// Navigationsleiste und war die auffälligste Entscheidung des Bildschirms,
/// obwohl er die unwichtigste traf: nach Medientyp sucht man selten, nach
/// dem eigenen Stand ständig. Wer ihn doch braucht, findet ihn im
/// Filter-Sheet unter „Inhalt".
struct WatchlistHeaderView: View {
    @Binding var query: String
    @Binding var quick: WatchlistQuickFilter
    /// Wie viele Titel gerade angezeigt werden — nicht, wie viele gespeichert
    /// sind. Die Zahl gehört zu dem, was darunter steht.
    let shownCount: Int
    let filtersActive: Bool
    let openFilters: () -> Void

    @FocusState private var searching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
            searchRow.padding(.top, 18)
            chips.padding(.top, 11)
        }
        .padding(.horizontal, WatchlistMetrics.screen)
        .padding(.bottom, 12)
        .background(alignment: .top) {
            // Ein Verlauf statt einer Kante: der Inhalt soll darunter
            // verschwinden, nicht an einer Linie abgeschnitten werden.
            LinearGradient(
                stops: [
                    .init(color: NoriTheme.bg.opacity(0.98), location: 0),
                    .init(color: NoriTheme.bg.opacity(0.88), location: 0.78),
                    .init(color: NoriTheme.bg.opacity(0.1), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Deine Bibliothek")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(NoriTheme.muted)
                Text("Merkliste")
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-1.3)
                    .foregroundStyle(NoriTheme.fg)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Text("\(shownCount) \(shownCount == 1 ? "Titel" : "Titel")")
                .font(.system(size: 12))
                .foregroundStyle(NoriTheme.muted)
                .accessibilityLabel("\(shownCount) Titel angezeigt")
        }
    }

    private var searchRow: some View {
        HStack(spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(NoriTheme.muted)
                TextField("Merkliste durchsuchen …", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(NoriTheme.fg)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($searching)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(NoriTheme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Suche leeren")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(NoriTheme.elevated.opacity(0.78), in: Capsule())
            .overlay { Capsule().strokeBorder(NoriTheme.border) }
            // Der ganze Streifen nimmt den Tipp an, nicht nur das Feld.
            .contentShape(Capsule())
            .onTapGesture { searching = true }

            Button(action: openFilters) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(NoriTheme.fg)
                    .frame(width: 50, height: 50)
                    .background(NoriTheme.elevated.opacity(0.80), in: Circle())
                    .overlay { Circle().strokeBorder(NoriTheme.border) }
                    .overlay(alignment: .topTrailing) {
                        // Der Punkt sagt, dass Titel fehlen, weil jemand das
                        // so eingestellt hat — ohne ihn sieht eine kurze
                        // Liste aus wie eine leere Merkliste.
                        if filtersActive {
                            Circle()
                                .fill(NoriTheme.accent)
                                .frame(width: 8, height: 8)
                                .offset(x: -5, y: 5)
                        }
                    }
            }
            .buttonStyle(NoriPressStyle(scale: 0.93))
            .accessibilityLabel(filtersActive ? "Filter, aktiv" : "Filter")
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(WatchlistQuickFilter.allCases) { filter in
                    Button {
                        withAnimation(NoriMotion.ui) { quick = filter }
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(quick == filter ? NoriTheme.bg : NoriTheme.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                quick == filter ? AnyShapeStyle(NoriTheme.fg) : AnyShapeStyle(NoriTheme.elevated.opacity(0.72)),
                                in: Capsule()
                            )
                            .overlay {
                                if quick != filter { Capsule().strokeBorder(NoriTheme.border) }
                            }
                    }
                    .buttonStyle(NoriPressStyle(scale: 0.94))
                    .accessibilityAddTraits(quick == filter ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .noriHaptic(.selection, trigger: quick)
    }
}
