// Eine Reihenfolge je Ansicht, die nachträglich eintreffende Daten nicht umwirft.
//
// Im Katalog des Fernsehers treffen TMDB-Angaben asynchron ein — Beliebtheit,
// Trendplatz, Bewertung, Erstausstrahlung. Genau diese Werte bestimmen aber die
// Sortierung. Wurde bei jedem Treffer neu sortiert, wanderten Karten unter der
// Fernbedienung weg: der fokussierte Titel wechselte die Stelle oder wurde durch
// einen anderen ersetzt.
//
// Die Regel: **Anreicherung ändert Daten, nie die Reihenfolge.** Eine Ansicht
// (Bereich, Filter, Sortierung, Suche) bekommt beim Aufbau eine geordnete Liste
// stabiler Kennungen (`provider|slug`). Solange die Ansicht dieselbe bleibt,
// bleibt die Liste stehen:
//
// - Kennungen, die es in der Quelle noch gibt, behalten ihre Stelle — auch wenn
//   ein TMDB-abhängiger Filter oder die Dublettenregel sie inzwischen anders
//   einordnen würde.
// - Was neu hinzukommt, etwa eine später geladene Quelle, kommt hinten dazu; es
//   verschiebt nichts, was schon dasteht.
// - Kennungen, die die Quelle nicht mehr führt, fallen weg.
//
// Neu sortiert wird erst mit einer neuen Ansicht: anderer Filter, andere
// Sortierung, andere Suche — oder beim erneuten Öffnen, das der Aufrufer mit
// `previous = null` ausdrückt.

export interface CatalogOrder {
  /** Was die Ansicht ausmacht. Ändert es sich, wird neu sortiert. */
  view: string;
  /** Stabile Kennungen in der Reihenfolge, in der sie gezeigt werden. */
  ids: string[];
}

function unique(ids: readonly string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const id of ids) {
    if (seen.has(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

/**
 * Die Reihenfolge einer Ansicht fortschreiben.
 *
 * @param previous  die bisherige Reihenfolge, `null` beim ersten Aufbau
 * @param view      Schlüssel der Ansicht
 * @param fresh     die frisch sortierten Kennungen mit dem aktuellen Wissen
 * @param available alle Kennungen, die die Quelle gerade führt — ungefiltert
 * @param groupOf   dieselbe Serie aus zwei Quellen ergibt dieselbe Gruppe; eine
 *                  neue Vertreterin ersetzt keine Karte, die schon dasteht
 *
 * Gibt `previous` selbst zurück, wenn sich nichts ändert.
 */
export function stableCatalogOrder(
  previous: CatalogOrder | null,
  view: string,
  fresh: readonly string[],
  available: ReadonlySet<string>,
  groupOf: (id: string) => string = (id) => id,
): CatalogOrder {
  if (!previous || previous.view !== view || previous.ids.length === 0) {
    return { view, ids: unique(fresh) };
  }

  const kept = previous.ids.filter((id) => available.has(id));
  const keptIds = new Set(kept);
  const keptGroups = new Set(kept.map(groupOf));
  const appended: string[] = [];
  for (const id of fresh) {
    if (keptIds.has(id)) continue;
    const group = groupOf(id);
    if (keptGroups.has(group)) continue;
    keptIds.add(id);
    keptGroups.add(group);
    appended.push(id);
  }

  if (appended.length === 0 && kept.length === previous.ids.length) return previous;
  return { view, ids: [...kept, ...appended] };
}
