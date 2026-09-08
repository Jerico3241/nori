// Die Naht zwischen einem Nori-Client und den Quellen.
//
// Ein Client ruft nie direkt einen Parser oder den Resolver auf, sondern immer
// dieses Gitter. Damit gibt es genau zwei Wege, und beide liefern dieselben
// Modelle:
//
//   DirectGateway  — der Client macht die Abrufe selbst (wie iOS und macOS).
//   HttpGateway    — der Client fragt einen Nori-Server (services/nori-api),
//                    der seinerseits DirectGateway benutzt.
//
// Der webOS-Client wählt zwischen beiden; hosterspezifische Logik gibt es in
// keinem Fall zweimal, sie liegt immer hier im Kern.

import { NoriClient } from "./client.js";
import type { HttpClient } from "./http.js";
import {
  type CalendarPayload, type CatalogProvider, type CatalogResult, type HosterOption,
  type PlaySource, type SeriesDetail, type WatchInfo,
} from "./models.js";
import { resolveBest, resolveHoster } from "./hoster/resolver.js";

export interface ResolveRequest {
  provider: CatalogProvider;
  episodePath: string;
  hosters: HosterOption[];
  preferredHoster?: string;
  preferredLang?: string;
  /** Ein bestimmter Hoster statt der Rangliste — für den Wechsel im Player. */
  pick?: HosterOption;
  skip?: string[];
}

export interface NoriGateway {
  catalog(provider: CatalogProvider, force?: boolean): Promise<CatalogResult>;
  series(provider: CatalogProvider, slug: string, season?: string | null): Promise<SeriesDetail>;
  watch(provider: CatalogProvider, path: string): Promise<WatchInfo>;
  calendar(provider: CatalogProvider, force?: boolean): Promise<CalendarPayload>;
  resolve(request: ResolveRequest): Promise<PlaySource>;
  /**
   * Die Adresse, die der Player tatsächlich lädt.
   *
   * Beim direkten Weg ist das der Stream selbst; über einen Nori-Server ist es
   * dessen Weiterreichung, weil der Hoster einen `Referer` verlangt, den ein
   * Browser nicht setzen darf.
   */
  playbackURL(source: PlaySource): string;
  /** Bildadresse, gegebenenfalls über den Server geleitet. */
  imageURL(url: string, provider: CatalogProvider): string;
}

export class DirectGateway implements NoriGateway {
  readonly client: NoriClient;
  private readonly http: HttpClient;

  constructor(http: HttpClient) {
    this.http = http;
    this.client = new NoriClient(http);
  }

  catalog(provider: CatalogProvider, force = false) {
    return this.client.getCatalog(provider, force);
  }

  series(provider: CatalogProvider, slug: string, season?: string | null) {
    return this.client.getSeries(provider, slug, season);
  }

  watch(provider: CatalogProvider, path: string) {
    return this.client.getWatch(provider, path);
  }

  calendar(provider: CatalogProvider, force = false) {
    return this.client.getCalendar(provider, force);
  }

  resolve(request: ResolveRequest): Promise<PlaySource> {
    const ctx = {
      http: this.http,
      provider: request.provider,
      episodePath: request.episodePath,
    };
    if (request.pick) return resolveHoster(request.pick, ctx);
    return resolveBest(request.hosters, {
      ...ctx,
      preferredHoster: request.preferredHoster,
      preferredLang: request.preferredLang,
      skip: request.skip,
    });
  }

  playbackURL(source: PlaySource): string {
    return source.url;
  }

  imageURL(url: string): string {
    return url;
  }
}
