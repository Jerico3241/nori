import SwiftUI

// Wo Noris Einstellungen liegen — und warum an zwei Orten.
//
// Es gibt **zwei** Arten von Einstellung, und sie gehören nicht an denselben
// Platz:
//
// 1. **Wiedergabe** — Sprache, Hoster, Resume, Autoplay, Geschwindigkeit,
//    Qualität. Sie stehen in `LibraryStore` und damit in `library.json`, also
//    in derselben Datei wie Merkliste, Verlauf und Fortschritt. Der Grund ist
//    der Abgleich: wer seine Bibliothek auf ein zweites Gerät spiegelt, will
//    dort dieselbe Sprache und dieselbe Qualität. Sie stehen deshalb auch im
//    `config/contract.json` und in `shared/nori-core/src/library.ts`.
//
// 2. **Darstellung** — Glas, dynamische Farben, reduzierte Bewegung. Sie
//    stehen in `@AppStorage`, also in den Nutzervorgaben dieses Geräts, und
//    werden **nicht** abgeglichen. Das ist Absicht: ein iPhone mit wenig
//    Akku und ein iPad am Netz dürfen unterschiedlich aussehen, und
//    „Bewegung reduzieren" ist eine Eigenschaft des Geräts, nicht der
//    Bibliothek.
//
// Ein drittes, eigenes Einstellungssystem gibt es nicht. Was hier steht, sind
// nur die Schlüssel und die Aufzählungen, die die Oberfläche braucht.

// MARK: - Darstellung

/// Die Schlüssel der Darstellungseinstellungen.
///
/// An einer Stelle, weil `@AppStorage` sie an mehreren Orten braucht — eine
/// Zeichenkette an drei Orten ist ein Tippfehler im Wartezustand. `NoriGlassSetting`
/// steht aus demselben Grund schon länger neben dem Glas selbst.
enum NoriLook {
    /// Ob Cover- und Artworkfarben die Oberfläche einfärben dürfen.
    static let dynamicColorsKey = "nori.look.dynamicColors"
    /// Noris eigener Schalter für weniger Bewegung. Apples
    /// Systemeinstellung hat Vorrang und wird nie überstimmt — siehe
    /// `RootView`, wo beide verodert werden.
    static let reduceMotionKey = "nori.look.reduceMotion"
}

// MARK: - Wiedergabe

/// Die Sprachen, die Noris Quellen tatsächlich führen.
///
/// Die Kennungen sind dieselben, die `HosterResolver.pickLang` vergleicht und
/// die in `WatchProgress` mitlaufen — hier wird nichts umbenannt, nur
/// ausgeschrieben.
///
/// Ein Eintrag „Automatisch" fehlt bewusst. Er wäre nicht haltbar: der Spieler
/// schreibt die zuletzt **dort** gewählte Sprache in dieselbe Einstellung
/// zurück, damit die nächste Folge in derselben Sprache startet. „Automatisch"
/// wäre damit nach der ersten Wiedergabe von selbst verschwunden — eine
/// Einstellung, die sich unbemerkt ändert, ist schlechter als eine, die es
/// nicht gibt.
enum NoriLanguageOption: String, CaseIterable, Identifiable {
    case german = "DE"
    case subtitled = "GerSub"
    case english = "EN"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .german: return "Deutsch"
        case .subtitled: return "GerSub"
        case .english: return "Englisch"
        }
    }

    var note: String {
        switch self {
        case .german: return "Deutsche Synchronisation, wenn die Folge sie hat."
        case .subtitled: return "Originalton mit deutschen Untertiteln."
        case .english: return "Englische Fassung, wenn die Quelle sie führt."
        }
    }

    /// Unbekannte gespeicherte Werte landen auf Deutsch, statt die Auswahl
    /// leer zu lassen.
    static func from(_ raw: String) -> NoriLanguageOption {
        NoriLanguageOption(rawValue: raw) ?? .german
    }
}

/// Die Qualitätsstufen, die Nori wirklich durchsetzen kann.
///
/// Durchgesetzt wird über `AVPlayerItem.preferredPeakBitRate`, und zwar nur
/// dort, wo der Hoster eine HLS-Master-Playlist mit mehreren Spuren liefert.
/// Bei einer einzelnen MP4-Datei — dem häufigeren Fall — gibt es nichts zu
/// wählen; der Spieler sagt das dann auch und behauptet nicht, eine Stufe
/// erzwungen zu haben.
///
/// Die Stufen sind Bildhöhen und keine Bitraten: jede Master-Playlist nennt
/// `RESOLUTION`, und „720p" ist eine Angabe, „2,8 Mbit/s" eine Zumutung.
enum NoriQualityOption: String, CaseIterable, Identifiable {
    case auto = "auto"
    case fullHD = "1080"
    case hd = "720"
    case sd = "480"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automatisch"
        case .fullHD: return "1080p"
        case .hd: return "720p"
        case .sd: return "480p"
        }
    }

    var note: String {
        switch self {
        case .auto: return "Der Spieler wählt nach verfügbarer Bandbreite."
        case .fullHD: return "Höchstens 1080p, wenn der Hoster Stufen anbietet."
        case .hd: return "Höchstens 720p — spart Daten bei kaum sichtbarem Verlust."
        case .sd: return "Höchstens 480p — für langsame Verbindungen."
        }
    }

    /// Die Obergrenze als Bildhöhe, oder `nil` für „der Spieler entscheidet".
    var maxHeight: Int? {
        switch self {
        case .auto: return nil
        case .fullHD: return 1080
        case .hd: return 720
        case .sd: return 480
        }
    }

    static func from(_ raw: String) -> NoriQualityOption {
        NoriQualityOption(rawValue: raw) ?? .auto
    }

    /// Die Stufe, die zu dieser Vorgabe passt: die höchste angebotene, die
    /// nicht über der Grenze liegt.
    ///
    /// Gibt `nil` zurück, wenn es nichts zu wählen gibt — keine Vorgabe, keine
    /// Stufen, oder alle Stufen liegen über der Grenze. Im letzten Fall wäre
    /// die niedrigste zu erzwingen eine schlechtere Antwort als der Automatik
    /// zu überlassen: eine Playlist, die nur 1440p und 2160p führt, hat für
    /// „höchstens 1080p" schlicht kein Angebot.
    func pick(from variants: [HLSVariant]) -> HLSVariant? {
        guard let maxHeight else { return nil }
        return variants
            .filter { ($0.height ?? 0) > 0 && ($0.height ?? 0) <= maxHeight }
            .max { left, right in (left.height ?? 0) < (right.height ?? 0) }
    }
}
