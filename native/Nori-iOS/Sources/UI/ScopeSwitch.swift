import SwiftUI

/// Umschalter für den Bereich der Bibliothek.
///
/// Hieß einmal `KindSwitch` und schaltete zwischen zwei Quellen um. Seit es
/// `LibraryScope` gibt, wählt er einen **Ausschnitt**: „Alle", „Anime",
/// „Serien" oder „K-Drama". Die Quelle entscheidet weiter, wohin ein
/// einzelner Titel führt — nur nicht mehr, was in den Listen steht.
///
/// ## Warum ein Menü und kein segmentierter Regler
///
/// Auf dem Mac sitzt derselbe Umschalter als segmentierter `Picker` in der
/// Seitenleiste, wo Platz ist. In einer iPhone-Navigationsleiste sind vier
/// Segmente zu viel: „K-Drama" allein braucht mehr Breite als die beiden
/// alten Segmente zusammen, und mit Dynamic Type wird daraus Gedränge oder
/// abgeschnittener Text. Ein Menü zeigt stattdessen den aktuellen Bereich und
/// bleibt gleich breit, egal wie viele Bereiche dazukommen.
///
/// ## Warum das hier steht und nicht mehr bei der Startseite
///
/// Der Umschalter lag in `HomeView.swift`, zusammen mit einer Pillenreihe
/// (`ScopeChips`), die ihn auf der Startseite noch einmal zeigte. Die
/// Startseite hat beides nicht mehr: sie führt Anime und Serien bewusst
/// gemeinsam, also gibt es dort nichts umzuschalten. Gebraucht wird der
/// Umschalter weiter in Katalog, Kalender und Merkliste — deshalb steht er
/// jetzt bei den gemeinsamen Bausteinen und nicht bei einem Bildschirm, der
/// ihn selbst nicht mehr verwendet.
struct ScopeSwitch: View {
    @Binding var scope: LibraryScope

    var body: some View {
        Menu {
            Picker("Bereich", selection: $scope) {
                ForEach(LibraryScope.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(scope.label, systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.titleAndIcon)
        }
        .accessibilityLabel("Bereich: \(scope.label)")
    }
}
