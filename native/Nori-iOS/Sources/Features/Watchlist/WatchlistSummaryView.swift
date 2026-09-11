import SwiftUI

/// Die Zusammenfassung über der Liste: ein Satz und drei Zahlen.
///
/// Die Zahlen beschreiben die **ganze** Merkliste, nicht den gerade
/// sichtbaren Ausschnitt. Sonst zeigte die Karte unter dem Filter
/// „Angefangen" dreimal dieselbe Zahl und wäre damit überflüssig; so
/// beantwortet sie die Frage, die der Filter gerade nicht beantwortet.
struct WatchlistSummaryView: View {
    let stats: WatchlistStats

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Deine Merkliste")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(NoriTheme.fg)
            Text("Gespeicherte Titel, Fortschritt und zuletzt hinzugefügte Inhalte an einem Ort.")
                .font(.system(size: 12))
                .foregroundStyle(NoriTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)

            HStack(spacing: 8) {
                stat(stats.saved, "Gespeichert")
                stat(stats.started, "Angefangen")
                stat(stats.seen, "Gesehen")
            }
            .padding(.top, 15)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(
                    colors: [NoriTheme.elevated, NoriTheme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // Der Schimmer oben rechts wie in der Vorlage. Ein
                // Farbverlauf statt eines Bildes: er kostet nichts und
                // skaliert mit der Karte.
                RadialGradient(
                    colors: [NoriTheme.accent.opacity(0.20), .clear],
                    center: UnitPoint(x: 0.82, y: 0.25),
                    startRadius: 0,
                    endRadius: 160
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: WatchlistMetrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WatchlistMetrics.cardRadius, style: .continuous)
                .strokeBorder(NoriTheme.border)
        }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(NoriTheme.fg)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(NoriTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(NoriTheme.bg.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.06))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// Die Zeile über den Ergebnissen: links, worauf gefiltert wird und wie
/// viel übrig bleibt; rechts Sortierung und Ansichtswechsel.
struct WatchlistToolbarView: View {
    let headline: String
    let count: Int
    @Binding var sort: WatchlistSort
    @Binding var mode: WatchlistViewMode

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(NoriTheme.fg)
                    .lineLimit(1)
                Text("\(count) \(count == 1 ? "Ergebnis" : "Ergebnisse")")
                    .font(.system(size: 11))
                    .foregroundStyle(NoriTheme.muted)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            // Ein Menü statt eines durchgeschalteten Knopfes: die Vorlage
            // schaltet mit jedem Tipp weiter, was bei vier Sortierungen
            // heißt, dass man dreimal daneben tippt, um die vierte zu
            // erreichen. Die Beschriftung bleibt dieselbe.
            Menu {
                Picker("Sortierung", selection: $sort) {
                    ForEach(WatchlistSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                pill {
                    HStack(spacing: 5) {
                        Text(sort.buttonLabel)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
            }
            .accessibilityLabel("Sortierung: \(sort.label)")

            Button {
                withAnimation(NoriMotion.ui) {
                    mode = mode == .grid ? .list : .grid
                }
            } label: {
                pill(square: true) {
                    Image(systemName: mode == .grid ? WatchlistViewMode.grid.symbol : WatchlistViewMode.list.symbol)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .buttonStyle(NoriPressStyle(scale: 0.93))
            .accessibilityLabel(mode == .grid ? "Ansicht: Kacheln" : "Ansicht: Liste")
            .accessibilityHint("Wechselt zwischen Kacheln und Liste")
        }
        .noriHaptic(.selection, trigger: mode)
    }

    private func pill<Content: View>(square: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(NoriTheme.fg)
            .frame(width: square ? 36 : nil, height: 36)
            .padding(.horizontal, square ? 0 : 11)
            .background(NoriTheme.elevated.opacity(0.68), in: Capsule())
            .overlay { Capsule().strokeBorder(NoriTheme.border) }
    }
}

/// Was steht, wenn nichts steht.
///
/// Zwei Fälle, und sie dürfen nicht denselben Text bekommen: eine leere
/// Merkliste ist ein Anfang und verweist in den Katalog; eine Merkliste, aus
/// der die Filter alles herausgenommen haben, ist ein Missverständnis und
/// verweist auf die Filter.
struct WatchlistEmptyState: View {
    enum Reason {
        /// Es ist gar nichts gemerkt.
        case nothingSaved
        /// Es ist etwas gemerkt, aber Suche oder Filter lassen nichts übrig.
        case noMatches
    }

    let reason: Reason
    /// Wechselt in den Katalog. Nur im ersten Fall belegt.
    var openCatalog: (() -> Void)?
    /// Nimmt Suche und Filter zurück. Nur im zweiten Fall belegt.
    var clearFilters: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: reason == .nothingSaved ? "bookmark" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(NoriTheme.muted)
                .padding(.bottom, 4)
            Text(reason == .nothingSaved ? "Noch nichts gespeichert" : "Keine Titel gefunden")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(NoriTheme.fg)
            Text(reason == .nothingSaved
                 ? "Entdecke Titel im Katalog und füge sie deiner Merkliste hinzu."
                 : "Passe deine Suche oder Filter an.")
                .font(.footnote)
                .foregroundStyle(NoriTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if reason == .nothingSaved, let openCatalog {
                Button("Katalog öffnen", action: openCatalog)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NoriTheme.bg)
                    .padding(.horizontal, 22)
                    .frame(height: NoriControl.hit)
                    .background(NoriTheme.fg, in: Capsule())
                    .buttonStyle(NoriPressStyle(scale: 0.95))
                    .padding(.top, 8)
            }
            if reason == .noMatches, let clearFilters {
                Button("Filter zurücksetzen", action: clearFilters)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NoriTheme.fg)
                    .padding(.horizontal, 22)
                    .frame(height: NoriControl.hit)
                    .background(NoriTheme.elevated, in: Capsule())
                    .overlay { Capsule().strokeBorder(NoriTheme.border) }
                    .buttonStyle(NoriPressStyle(scale: 0.95))
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 48)
    }
}
