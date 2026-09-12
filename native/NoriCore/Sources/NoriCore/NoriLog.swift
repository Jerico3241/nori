import Foundation

/// Protokollzeilen für die Fehlersuche.
///
/// Standardmäßig **aus**. Eingeschaltet wird über die Umgebungsvariable
/// `NORI_LOG` (in Xcode: Schema → Run → Arguments → Environment Variables)
/// oder zur Laufzeit über `NoriLog.enabled`.
///
/// ## Was hier nicht hineingehört
///
/// Niemals der TMDB-Schlüssel und niemals eine vollständige Anfrageadresse —
/// die trägt ihn als Abfrageparameter. Die Aufrufstellen geben deshalb
/// Begriffe und Kennungen aus, keine URLs. Diese Regel steht hier, weil sie
/// sonst nirgends steht.
enum NoriLog {
    nonisolated(unsafe) static var enabled: Bool =
        ProcessInfo.processInfo.environment["NORI_LOG"].map { $0 != "0" && !$0.isEmpty } ?? false

    static func tmdb(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print("[TMDB] " + message())
    }
}
