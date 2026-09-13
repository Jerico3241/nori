import SwiftUI

/// Noris Kalender.
///
/// Aufbau: ein feststehender Kopfbereich — Titel, Filterknopf, Heute/Woche/
/// Monat und darunter der Tagesnavigator — und ein scrollender Inhalt.
/// Der Kopfbereich bleibt stehen, weil seine Bedienelemente zum Kalender
/// gehören: wer vom unteren Ende einer Monatsliste auf „Heute" will, soll
/// nicht erst zurückscrollen müssen.
///
/// ## Woher die Einträge kommen
///
/// Die Verfügbarkeit entscheiden **nur** Noris Provider: AniWorld und
/// Serienstream sagen, welche Folge wann bei ihnen steht. TMDB trägt
/// Folgentitel und Standbilder nach (siehe `CalendarReleaseRow`) und bestimmt
/// nie, ob ein Eintrag erscheint — TMDB kennt Ausstrahlungstermine, nicht
/// Noris Bestand. Ohne TMDB-Schlüssel sieht der Kalender schlichter aus und
/// funktioniert unverändert.
///
/// ## Was diese Ansicht nicht tut
///
/// Sie führt nichts zusammen und sortiert nichts. Dubletten, Tagesschlüssel in
/// der Zeitzone des Geräts und die Reihenfolge kommen aus `CalendarMerge`,
/// Filter und Bündelung aus `CalendarSelection`, das Laden aus
/// `CalendarService`. Die vorherige Kalenderansicht hatte all das zwischen
/// ihren Zeilen.
struct CalendarView: View {
    @Environment(LibraryStore.self) private var library
    /// Die zugelassenen Slugs, wenn der Bereich an einem Genre hängt.
    ///
    /// Ein `AiringEntry` trägt Slug und Quelle, aber keine Genres — ohne diesen
    /// Umweg zeigte „K-Drama" den vollständigen Serienstream-Kalender.
    let slugs: Set<String>?
    /// Zählt hoch, wenn sich `slugs` inhaltlich ändert.
    let slugsRevision: Int

    @State private var service = CalendarService()
    @State private var mode: CalendarMode = .today
    @State private var filter = CalendarFilter()
    /// Der Tag, den die Liste zeigt. In „Heute" immer heute.
    @State private var selected = Date()
    /// Heute, festgehalten beim Erscheinen — damit eine über Mitternacht
    /// geöffnete App nicht weiter den Vortag hervorhebt.
    @State private var today = Date()
    @State private var showFilter = false

    private var calendar: Calendar { Calendar.current }

    private static let maxContentWidth: CGFloat = 980

    var body: some View {
        NoriGradientScreen {
            VStack(spacing: 14) {
                CalendarHeaderView(
                    filtersActive: !filter.isDefault || library.scope != .all,
                    onFilter: { showFilter = true }
                )
                CalendarModeSwitcher(mode: $mode)
                navigator
                content
            }
            .padding(.top, 6)
            // Auf dem iPad quer liefen die Zeilen über 1376 Punkte: Titel
            // links, Pfeil ganz rechts, dazwischen eine leere Bahn. Eine Spalte
            // in Lesebreite, mittig — auf dem iPhone und im iPad-Hochformat
            // greift die Grenze nicht.
            .frame(maxWidth: Self.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        // Der Kopfbereich bringt Titel und Filter selbst mit; eine zweite
        // Leiste darüber wäre doppelt.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showFilter) {
            CalendarFilterSheet(
                scope: Bindable(library).scope,
                filter: $filter,
                matching: periodReleases.count
            )
        }
        .task(id: reloadKey) {
            today = Date()
            if mode == .today { selected = today }
            await service.load(scope: library.scope, slugs: slugs, slugsRevision: slugsRevision)
        }
        .onChange(of: mode) { _, next in
            // „Heute" ist ein Tag, kein Zeitraum: der Modus setzt die Auswahl
            // zurück, sonst zeigte er nach einem Ausflug in den Monat weiter
            // den dort angetippten Tag unter der Überschrift „Heute".
            if next == .today { selected = today }
        }
    }

    // MARK: - Tagesnavigator

    /// Wochenleiste in „Heute" und „Woche", Monatsraster in „Monat".
    @ViewBuilder
    private var navigator: some View {
        switch mode {
        case .today:
            CalendarWeekStrip(
                days: CalendarSelection.week(containing: today, calendar: calendar),
                selected: selected,
                today: today,
                counts: counts,
                calendar: calendar,
                onSelect: jump
            )
        case .week:
            VStack(spacing: 10) {
                CalendarPeriodBar(
                    label: weekLabel,
                    onBack: { shiftWeek(-1) },
                    onForward: { shiftWeek(1) }
                )
                CalendarWeekStrip(
                    days: weekDays,
                    selected: selected,
                    today: today,
                    counts: counts,
                    calendar: calendar,
                    onSelect: { selected = $0 }
                )
            }
        case .month:
            CalendarPeriodBar(
                label: selected.formatted(.dateTime.month(.wide).year()),
                onBack: { shiftMonth(-1) },
                onForward: { shiftMonth(1) }
            )
        }
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var content: some View {
        if service.loading, service.releases.isEmpty {
            CalendarSkeleton()
        } else if let error = service.error, service.releases.isEmpty {
            ContentUnavailableView(
                "Kalender nicht geladen",
                systemImage: "calendar.badge.exclamationmark",
                description: Text(error)
            )
        } else {
            list
        }
    }

    private var list: some View {
        GeometryReader { proxy in
            let thumb = proxy.size.width <= 380 ? CalendarMetrics.thumbNarrow : CalendarMetrics.thumb
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        switch mode {
                        case .today: todaySections(thumb: thumb)
                        case .week: weekSections(thumb: thumb)
                        case .month: monthSections(thumb: thumb)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, NoriPanel.bottom)
                }
                .scrollIndicators(.hidden)
                .noriSoftScrollEdges(.bottom)
                .refreshable { await service.load(scope: library.scope, slugs: slugs, slugsRevision: slugsRevision, force: true) }
                // Ein Tipper in der Wochenleiste springt zum Abschnitt des
                // Tages, statt die Liste auszutauschen: in „Woche" stehen alle
                // sieben Tage untereinander, und „springen" ist genau das, was
                // die Leiste verspricht.
                .onChange(of: selected) { _, next in
                    guard mode == .week else { return }
                    let key = CalendarRelease.dayKey(for: next, calendar: calendar)
                    withAnimation(NoriMotion.content) { scroll.scrollTo(key, anchor: .top) }
                }
            }
        }
    }

    /// Heute, darunter ein Ausblick auf morgen und den Rest der Woche.
    @ViewBuilder
    private func todaySections(thumb: CGFloat) -> some View {
        let rows = CalendarSelection.releases(visible, on: today, calendar: calendar)

        CalendarSummaryCard(
            headline: "Heute, " + today.formatted(.dateTime.day().month(.wide)),
            detail: summaryDetail(count: rows.count),
            count: rows.count
        )

        if rows.isEmpty {
            CalendarEmptyState(
                title: "Heute keine neuen Episoden",
                detail: emptyDetail
            )
        } else {
            section("Heute", rows: rows, thumb: thumb)
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            let next = CalendarSelection.releases(visible, on: tomorrow, calendar: calendar)
            if !next.isEmpty {
                CalendarSectionHead(title: "Morgen", count: next.count)
                CalendarDateCard(
                    title: tomorrow.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                    detail: titleList(next),
                    action: { jump(to: tomorrow) }
                )
            }
        }

        let rest = restOfWeek
        if !rest.isEmpty {
            CalendarSectionHead(title: "Diese Woche", count: rest.count)
            CalendarDateCard(
                title: restOfWeekLabel,
                detail: titleList(rest),
                action: { mode = .week }
            )
        }
    }

    /// Montag bis Sonntag, Tage ohne Veröffentlichungen werden übersprungen.
    @ViewBuilder
    private func weekSections(thumb: CGFloat) -> some View {
        // Nicht `rows` nennen: so heisst der Zeilenbauer unten, und ein
        // gleichnamiger Wert verdeckt ihn in diesem Abschnitt.
        let week = periodReleases
        let days = CalendarSelection.days(week, calendar: calendar)

        CalendarSummaryCard(
            headline: weekLabel,
            detail: summaryDetail(count: week.count),
            count: week.count
        )

        if days.isEmpty {
            CalendarEmptyState(
                title: "Diese Woche keine neuen Episoden",
                detail: emptyDetail
            )
        } else {
            ForEach(days) { day in
                // Der Tagesschlüssel ist das Sprungziel der Wochenleiste.
                CalendarSectionHead(
                    title: day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)),
                    count: day.releases.count
                )
                .id(day.key)
                rows(day.releases, thumb: thumb)
            }
        }
    }

    /// Das Raster, darunter der gewählte Tag.
    @ViewBuilder
    private func monthSections(thumb: CGFloat) -> some View {
        CalendarMonthGrid(
            cells: CalendarSelection.monthGrid(containing: selected, calendar: calendar),
            selected: selected,
            today: today,
            counts: counts,
            calendar: calendar,
            onSelect: { selected = $0 }
        )

        let rows = CalendarSelection.releases(visible, on: selected, calendar: calendar)
        let isToday = calendar.isDate(selected, inSameDayAs: today)

        CalendarSummaryCard(
            headline: (isToday ? "Heute, " : "") + selected.formatted(.dateTime.day().month(.wide)),
            detail: summaryDetail(count: rows.count),
            count: rows.count
        )

        if rows.isEmpty {
            CalendarEmptyState(
                title: "An diesem Tag keine neuen Episoden",
                detail: monthEmptyDetail
            )
        } else {
            section(
                selected.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                rows: rows,
                thumb: thumb
            )
        }
    }

    // MARK: - Zeilen

    @ViewBuilder
    private func section(_ title: String, rows list: [CalendarRelease], thumb: CGFloat) -> some View {
        CalendarSectionHead(title: title, count: list.count)
        rows(list, thumb: thumb)
    }

    @ViewBuilder
    private func rows(_ list: [CalendarRelease], thumb: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(list) { release in
                CalendarReleaseLink(release: release) {
                    CalendarReleaseRow(
                        release: release,
                        marked: library.isFavorite(release.slug),
                        width: thumb
                    )
                }
                if release.id != list.last?.id {
                    Divider().overlay(NoriTheme.border)
                }
            }
        }
        .padding(.horizontal, CalendarMetrics.screen)
    }

    // MARK: - Auswahl

    /// Alle Veröffentlichungen, die durch den Filter kommen.
    private var visible: [CalendarRelease] {
        CalendarSelection.filtered(
            service.releases,
            filter: filter,
            favorites: Set(library.favorites),
            started: startedSlugs
        )
    }

    /// Die Veröffentlichungen des Zeitraums, den der Modus zeigt — Grundlage
    /// für jede Zahl in der Zusammenfassung.
    private var periodReleases: [CalendarRelease] {
        switch mode {
        case .today:
            return CalendarSelection.releases(visible, on: today, calendar: calendar)
        case .week:
            let keys = Set(weekDays.map { CalendarRelease.dayKey(for: $0, calendar: calendar) })
            return visible.filter { keys.contains($0.dayKey) }
        case .month:
            return CalendarSelection.releases(visible, on: selected, calendar: calendar)
        }
    }

    private var counts: [String: Int] { CalendarSelection.counts(visible) }

    /// Serien, von denen schon eine Folge angefangen wurde.
    ///
    /// Der Fortschritt ist die einzige belastbare Auskunft darüber, was jemand
    /// verfolgt. Ob eine Serie bei der Quelle noch **produziert** wird, sagt
    /// weder AniWorld noch Serienstream — deshalb gibt es dafür keinen Filter.
    private var startedSlugs: Set<String> {
        var slugs: Set<String> = []
        for item in library.progress.values where item.positionSec > 0 || item.completed == true {
            slugs.insert(item.slug)
        }
        return slugs
    }

    private var weekDays: [Date] {
        CalendarSelection.week(containing: selected, calendar: calendar)
    }

    /// Der Rest der Woche nach morgen — für den Ausblick in „Heute".
    private var restOfWeek: [CalendarRelease] {
        guard let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today) else { return [] }
        let week = CalendarSelection.week(containing: today, calendar: calendar)
        let keys = Set(
            week
                .filter { $0 >= calendar.startOfDay(for: dayAfterTomorrow) }
                .map { CalendarRelease.dayKey(for: $0, calendar: calendar) }
        )
        return visible.filter { keys.contains($0.dayKey) }
    }

    // MARK: - Beschriftungen

    private var weekLabel: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "Diese Woche" }
        let from = first.formatted(.dateTime.day().month(.abbreviated))
        let to = last.formatted(.dateTime.day().month(.abbreviated))
        return "\(from) – \(to)"
    }

    private var restOfWeekLabel: String {
        let days = CalendarSelection.days(restOfWeek, calendar: calendar)
        guard let first = days.first, let last = days.last else { return "Diese Woche" }
        if first.key == last.key {
            return first.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
        return first.date.formatted(.dateTime.day()) + ".–" + last.date.formatted(.dateTime.day().month(.wide))
    }

    /// Der Erklärtext der Zusammenfassung — er muss zum eingestellten Filter
    /// passen, sonst verspricht er den ganzen Katalog, während nur die
    /// Merkliste gezeigt wird.
    private func summaryDetail(count: Int) -> String {
        let what = count == 1 ? "eine neue Episode" : "\(count) neue Episoden"
        switch filter.source {
        case .catalog:
            return count == 0
                ? "Aus dem Katalog von AniWorld und Serienstream."
                : "\(what.prefix(1).capitalized)\(what.dropFirst()) aus dem Katalog von AniWorld und Serienstream."
        case .watchlist:
            return count == 0
                ? "Aus deiner Merkliste."
                : "\(what.prefix(1).capitalized)\(what.dropFirst()) aus deiner Merkliste."
        case .started:
            return count == 0
                ? "Aus den Titeln, die du angefangen hast."
                : "\(what.prefix(1).capitalized)\(what.dropFirst()) aus den Titeln, die du angefangen hast."
        }
    }

    /// Sagt im Leerzustand, ob der Filter daran beteiligt ist — sonst sucht
    /// jemand den Fehler beim Kalender, während „Nur Merkliste" eingestellt ist.
    private var emptyDetail: String {
        if filter.isDefault, library.scope == .all {
            return "Die Quellen kündigen für diesen Zeitraum nichts an."
        }
        return "Mit den aktuellen Filtern bleibt nichts übrig. Über den Filterknopf oben lässt sich das ändern."
    }

    private var monthEmptyDetail: String {
        if filter.isDefault, library.scope == .all {
            return "Die Quellen kündigen nur wenige Tage im Voraus an. Die Punkte im Raster zeigen, wo etwas liegt."
        }
        return "Mit den aktuellen Filtern bleibt an diesem Tag nichts übrig."
    }

    /// Die Serien einer Tagesliste als Aufzählung — höchstens drei, danach
    /// „und N weitere". Eine Karte ist kein Platz für zwanzig Namen.
    private func titleList(_ releases: [CalendarRelease]) -> String {
        var names: [String] = []
        for release in releases where !names.contains(release.title) {
            names.append(release.title)
        }
        guard !names.isEmpty else { return "" }
        if names.count <= 3 {
            return "Neue Folgen von " + names.formatted(.list(type: .and, width: .standard)) + "."
        }
        let shown = Array(names.prefix(3))
        let rest = names.count - shown.count
        return "Neue Folgen von " + shown.formatted(.list(type: .and, width: .standard))
            + " und \(rest) weiteren Titeln."
    }

    // MARK: - Navigation im Zeitraum

    /// Wechselt mit dem Bereich — und mit dem Katalog, sofern der Bereich
    /// überhaupt nach Genre einschränkt.
    private var reloadKey: String {
        guard library.scope.genre != nil else { return library.scope.rawValue }
        return "\(library.scope.rawValue)|\(slugsRevision)"
    }

    /// Aus „Heute" auf einen anderen Tag: der Modus wechselt mit, sonst stünde
    /// der 14. unter der Überschrift „Heute".
    private func jump(to day: Date) {
        selected = day
        if !calendar.isDate(day, inSameDayAs: today) {
            mode = .week
        }
    }

    private func shiftWeek(_ delta: Int) {
        guard let next = calendar.date(byAdding: .weekOfYear, value: delta, to: selected) else { return }
        selected = next
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: selected) else { return }
        selected = next
    }
}

// MARK: - Tipper auf eine Veröffentlichung

/// Öffnet die neue Detailseite der Serie.
///
/// Nicht die Folge direkt: eine Folge, die es noch nicht gibt, lässt sich nicht
/// abspielen, und eine, die es gibt, kann auf der Detailseite mit einem
/// weiteren Tipper starten — dort steht auch, welche Hoster und Sprachen sie
/// tatsächlich hat. Die Detailseite ist damit für beide Fälle die richtige
/// Antwort, ohne dass der Kalender eine zweite Abspielstrecke mitbringt.
///
/// Die Quelle wird mitgegeben: seit der Kalender beide Seiten zusammenführt,
/// ist die Vorgabequelle der Bibliothek regelmäßig die falsche.
private struct CalendarReleaseLink<Label: View>: View {
    let release: CalendarRelease
    @ViewBuilder let label: () -> Label

    var body: some View {
        NoriSeriesLink(
            slug: release.slug,
            titleHint: release.title,
            provider: release.primaryProvider,
            label: label
        )
    }
}

// MARK: - Ausblickskarte

/// „Freitag, 12. September — Neue Folgen von …", antippbar.
private struct CalendarDateCard: View {
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NoriTheme.muted)
            }
            .padding(14)
            .noriPanel(radius: NoriPanel.cardRadius)
            .contentShape(RoundedRectangle(cornerRadius: NoriPanel.cardRadius, style: .continuous))
        }
        .buttonStyle(NoriPressStyle(scale: 0.98))
        .padding(.horizontal, CalendarMetrics.screen)
    }
}

// MARK: - Zeitraumleiste

/// ‹ Zeitraum › — eine Woche oder ein Monat vor und zurück.
///
/// Ohne sie wäre „Monat" eine Ansicht, die nur den laufenden Monat kennt. Die
/// Quellen kündigen zwar nur wenige Tage im Voraus an, aber der gelaufene Teil
/// reicht zurück, und ein Kalender, in dem man nicht blättern kann, ist keiner.
struct CalendarPeriodBar: View {
    let label: String
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            button("chevron.left", label: "Zurück", action: onBack)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
            button("chevron.right", label: "Weiter", action: onForward)
        }
        .padding(.horizontal, CalendarMetrics.screen)
        .noriAnimation(NoriMotion.ui, value: label)
    }

    private func button(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .frame(width: NoriControl.hit, height: NoriControl.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoriPressStyle())
        .accessibilityLabel(label)
    }
}


// MARK: - Ladezustand

/// Der Kalender, bevor die Einträge da sind.
///
/// Zusammenfassung und Zeilen im Umriss, in denselben Abständen wie die Liste.
/// Vorher stand hier ein `ProgressView` mitten im Inhalt; beim Eintreffen der
/// Daten schoben sich Karte und Zeilen von der Mitte an den oberen Rand.
private struct CalendarSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            RoundedRectangle(cornerRadius: NoriPanel.cardRadius, style: .continuous)
                .fill(NoriTheme.elevated)
                .frame(height: 92)
                .padding(.horizontal, CalendarMetrics.screen)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0 ..< 5, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(NoriTheme.elevated)
                            .frame(width: CalendarMetrics.thumb, height: CalendarMetrics.thumb * 9 / 16)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Titel einer Serie")
                                .font(.subheadline.weight(.semibold))
                            Text("S1 · F1 · Deutsch")
                                .font(.caption)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, CalendarMetrics.screen)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .redacted(reason: .placeholder)
        .foregroundStyle(NoriTheme.elevated)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kalender wird geladen")
    }
}
