import SwiftUI

// Der Kopfbereich des Kalenders und die Bauteile darin: Titelzeile,
// Modusumschalter, Wochenleiste, Zusammenfassung, Monatsraster.
//
// Die Maße stammen aus `nori-calendar-v1.html`. Wo Vorlage und Noris
// bestehendes System auseinanderlaufen, gewinnt das System: der Seitenrand
// bleibt `NoriSpacing.screen`, damit Kalender, Startseite und Detailseite links
// auf derselben Linie beginnen.

// MARK: - Maße

enum CalendarMetrics {
    static let screen: CGFloat = NoriSpacing.screen
    /// Höhe eines Segments im Modusumschalter.
    static let segment: CGFloat = 38
    /// Durchmesser des Knopfes, der den Filterbogen öffnet.
    static let circle: CGFloat = 44
    /// Breite des Standbilds einer Veröffentlichung. 16:9 ergibt rund 63 Punkte
    /// Höhe — dieselbe Form, in der die Folgenliste der Detailseite ihre
    /// Standbilder zeigt.
    static let thumb: CGFloat = 112
    static let thumbNarrow: CGFloat = 100
    /// Eine Zelle der Wochenleiste.
    static let dayCell: CGFloat = 17
    /// Der Kreis um die Tageszahl.
    static let dayDot: CGFloat = 30
}

// MARK: - Titelzeile

/// „Veröffentlichungen / Kalender" mit dem Filterknopf daneben.
struct CalendarHeaderView: View {
    /// Wie viele Filter von der Vorgabe abweichen — als Punkt am Knopf.
    let filtersActive: Bool
    let onFilter: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Veröffentlichungen")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(NoriTheme.muted)
                Text("Kalender")
                    .font(.system(size: 38, weight: .bold))
                    // Der große Titel darf bei großer Schrift mitwachsen, aber
                    // nicht so weit, dass er den Filterknopf verdrängt.
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            filterButton
        }
        .padding(.horizontal, CalendarMetrics.screen)
    }

    private var filterButton: some View {
        Button(action: onFilter) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: CalendarMetrics.circle, height: CalendarMetrics.circle)
                .noriGlass(Circle(), off: NoriTheme.elevated.opacity(0.8))
                .overlay(alignment: .topTrailing) {
                    if filtersActive {
                        Circle()
                            .fill(NoriTheme.accent)
                            .frame(width: 9, height: 9)
                            .overlay { Circle().strokeBorder(NoriTheme.bg, lineWidth: 2) }
                            .offset(x: 1, y: -1)
                    }
                }
        }
        .buttonStyle(NoriPressStyle())
        .accessibilityLabel(filtersActive ? "Filter, aktiv" : "Filter")
    }
}

// MARK: - Modus

/// Heute | Woche | Monat.
///
/// Von Hand gezeichnet und nicht `Picker(.segmented)`: die Vorlage setzt eine
/// hell gefüllte Kapsel auf dunklem Grund, und ein segmentierter Picker lässt
/// sich nicht so einfärben. Die Rollen stehen trotzdem richtig — jedes Segment
/// ist ein Knopf mit `isSelected`, VoiceOver liest „ausgewählt".
struct CalendarModeSwitcher: View {
    @Binding var mode: CalendarMode
    @NoriReduceMotion private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(CalendarMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    Text(option.label)
                        .font(.footnote.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: CalendarMetrics.segment)
                        .foregroundStyle(option == mode ? NoriTheme.bg : NoriTheme.muted)
                        .background {
                            if option == mode {
                                Capsule().fill(NoriTheme.accent)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == mode ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .noriPanel(radius: (CalendarMetrics.segment + 8) / 2)
        .noriAnimation(NoriMotion.ui, value: mode)
        .noriHaptic(.selection, trigger: mode)
        .padding(.horizontal, CalendarMetrics.screen)
    }
}

// MARK: - Wochenleiste

/// Montag bis Sonntag mit der Zahl des Tages.
///
/// Der gewählte Tag bekommt den hellen Kreis, *heute* zusätzlich einen Punkt
/// darunter — sonst wären „heute" und „angetippt" nicht zu unterscheiden,
/// sobald jemand einen anderen Tag wählt. Tage mit Veröffentlichungen tragen
/// eine feine Linie, damit sich eine leere Woche von einer gefüllten
/// unterscheidet, ohne jeden Tag anzutippen.
struct CalendarWeekStrip: View {
    let days: [Date]
    let selected: Date
    let today: Date
    /// Zahl der Veröffentlichungen je Tagesschlüssel.
    let counts: [String: Int]
    let calendar: Calendar
    let onSelect: (Date) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(days, id: \.timeIntervalSince1970) { day in
                cell(day)
            }
        }
        .padding(.horizontal, CalendarMetrics.screen)
    }

    private func cell(_ day: Date) -> some View {
        let key = CalendarRelease.dayKey(for: day, calendar: calendar)
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let count = counts[key] ?? 0

        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 5) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 9, weight: .heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(NoriTheme.muted)
                Text(day.formatted(.dateTime.day()))
                    .font(.footnote.weight(isToday ? .bold : .semibold))
                    .foregroundStyle(isSelected ? NoriTheme.bg : NoriTheme.fg)
                    .frame(width: CalendarMetrics.dayDot, height: CalendarMetrics.dayDot)
                    .background {
                        if isSelected { Circle().fill(NoriTheme.accent) }
                    }
                Capsule()
                    .fill(count > 0 ? NoriTheme.accent.opacity(isSelected ? 0.9 : 0.55) : .clear)
                    .frame(width: count > 0 ? 12 : 0, height: 2)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
            .background {
                RoundedRectangle(cornerRadius: CalendarMetrics.dayCell, style: .continuous)
                    .fill(isSelected ? NoriTheme.accent.opacity(0.10) : NoriTheme.elevated.opacity(0.58))
                    .overlay {
                        RoundedRectangle(cornerRadius: CalendarMetrics.dayCell, style: .continuous)
                            .strokeBorder(isSelected ? NoriTheme.accent.opacity(0.30) : NoriTheme.border)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: CalendarMetrics.dayCell, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(day, count: count, isToday: isToday))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func label(_ day: Date, count: Int, isToday: Bool) -> String {
        var text = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if isToday { text += ", heute" }
        text += count == 0
            ? ", keine Veröffentlichungen"
            : ", \(count) \(count == 1 ? "Veröffentlichung" : "Veröffentlichungen")"
        return text
    }
}

// MARK: - Zusammenfassung

/// Die Karte über der Liste: welcher Tag, wie viele Folgen.
///
/// Die Zahl wird gezählt, nicht geschrieben — sie gilt für den Tag bzw. den
/// Zeitraum **nach** Anwendung der Filter, sonst stünde über einer auf die
/// Merkliste eingeschränkten Liste die Zahl des ganzen Katalogs.
struct CalendarSummaryCard: View {
    let headline: String
    let detail: String
    let count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(headline)
                    .font(.headline.weight(.bold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(NoriTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            badge
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: NoriPanel.heroRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [NoriTheme.elevated, NoriTheme.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    // Dasselbe Licht wie auf der Vorlage, oben rechts in der
                    // Karte. Es sitzt **in** der Karte und nicht dahinter,
                    // damit es mit ihr abgeschnitten wird.
                    RadialGradient(
                        gradient: Gradient(colors: [NoriTheme.accent.opacity(0.22), .clear]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 90
                    )
                    .frame(width: 180, height: 180)
                    .offset(x: 40, y: -60)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: NoriPanel.heroRadius, style: .continuous)
                        .strokeBorder(NoriTheme.border)
                }
                .clipShape(RoundedRectangle(cornerRadius: NoriPanel.heroRadius, style: .continuous))
        }
        .padding(.horizontal, CalendarMetrics.screen)
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        VStack(spacing: 1) {
            Text("\(count)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(count == 1 ? "Folge" : "Folgen")
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(NoriTheme.muted)
        }
        .frame(width: 60, height: 60)
        .background(NoriTheme.bg.opacity(0.52), in: RoundedRectangle(cornerRadius: NoriPanel.cornerForBadge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NoriPanel.cornerForBadge, style: .continuous)
                .strokeBorder(NoriTheme.border)
        }
    }
}

extension NoriPanel {
    /// Das Zahlenfeld in der Zusammenfassung. Eigene Zahl, weil es kleiner ist
    /// als eine Karte und mit deren Radius fast rund aussähe.
    static let cornerForBadge: CGFloat = 18
}

// MARK: - Abschnittsüberschrift

/// „Heute — 5 Veröffentlichungen".
struct CalendarSectionHead: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
            Spacer(minLength: 8)
            Text(count == 1 ? "1 Veröffentlichung" : "\(count) Veröffentlichungen")
                .font(.caption)
                .foregroundStyle(NoriTheme.muted)
        }
        .padding(.horizontal, CalendarMetrics.screen)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Monatsraster

/// Ein Monat als Raster mit Punkten an den Tagen, die etwas bringen.
///
/// Ausdrücklich **kein** vergrößerter Wochenstreifen: der Monat soll auf einen
/// Blick zeigen, wo im Monat etwas liegt. Darunter steht weiterhin die Liste
/// des gewählten Tages — ein Raster allein beantwortet „was kommt" nicht.
struct CalendarMonthGrid: View {
    /// Die Zellen des Monats; `nil` sind die Leerfelder vor dem Ersten.
    let cells: [Date?]
    let selected: Date
    let today: Date
    let counts: [String: Int]
    let calendar: Calendar
    let onSelect: (Date) -> Void

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 9, weight: .heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(NoriTheme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Self.columns, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .padding(14)
        .noriPanel()
        .padding(.horizontal, CalendarMetrics.screen)
    }

    private func cell(_ day: Date) -> some View {
        let key = CalendarRelease.dayKey(for: day, calendar: calendar)
        let count = counts[key] ?? 0
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDate(day, inSameDayAs: today)

        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.footnote.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? NoriTheme.bg : NoriTheme.fg)
                // Bis zu drei Punkte, danach bleibt es bei drei: die Zahl steht
                // in der Zusammenfassung, hier zählt „viel oder wenig".
                HStack(spacing: 2) {
                    ForEach(0 ..< min(count, 3), id: \.self) { _ in
                        Circle()
                            .fill(isSelected ? NoriTheme.bg.opacity(0.65) : NoriTheme.accent.opacity(0.75))
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if isSelected {
                    Circle().fill(NoriTheme.accent).frame(width: 38, height: 38)
                } else if isToday {
                    Circle().strokeBorder(NoriTheme.accent.opacity(0.45)).frame(width: 38, height: 38)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(day, count: count, isToday: isToday))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func label(_ day: Date, count: Int, isToday: Bool) -> String {
        var text = day.formatted(.dateTime.day().month(.wide))
        if isToday { text += ", heute" }
        text += count == 0
            ? ", keine Veröffentlichungen"
            : ", \(count) \(count == 1 ? "Veröffentlichung" : "Veröffentlichungen")"
        return text
    }

    /// Mo–So, unabhängig von der Systemvorgabe — dieselbe Reihenfolge, in der
    /// `CalendarSelection.monthGrid` die Zellen auffüllt.
    ///
    /// Aus den Wochentagsnamen des Kalenders gedreht, nicht aus einem
    /// Bezugsdatum gerechnet. Ein „bekannter Montag" als Zeitstempel war schon
    /// einmal keiner: die Kopfzeile stand auf „D F S S M D M", also um drei
    /// Tage verschoben, während die Zellen darunter richtig lagen. Eine Zahl,
    /// deren Richtigkeit man nicht ansieht, gehört nicht in den Quelltext.
    ///
    /// `veryShortWeekdaySymbols` beginnt bei Sonntag; `firstWeekday` ist hier
    /// immer 2 (Montag), gedreht wird also um genau eine Stelle.
    private var weekdayLabels: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return [] }
        return (0 ..< 7).map { symbols[($0 + 1) % 7] }
    }
}

// MARK: - Leerer Tag

/// Ein ruhiger Zustand statt einer schwarzen Fläche.
struct CalendarEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(NoriTheme.muted)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(NoriTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
        .noriPanel(radius: NoriPanel.cardRadius)
        .padding(.horizontal, CalendarMetrics.screen)
        .accessibilityElement(children: .combine)
    }
}
