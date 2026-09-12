import AppKit
import Foundation
import Network

/// Die Google-Anmeldung auf macOS.
///
/// Ein Loopback-Server auf `127.0.0.1` mit einem vom System vergebenen Port.
/// Google nennt das für Desktop-Anwendungen ausdrücklich den empfohlenen Weg;
/// eigene URL-Schemata gelten dort inzwischen als unsicher, weil eine andere
/// Anwendung dasselbe Schema beanspruchen und damit die Antwort abfangen kann.
///
/// Der früher übliche Weg, den Code von Hand aus dem Browser zu kopieren
/// (`urn:ietf:wg:oauth:2.0:oob`), ist seit 2022 abgeschaltet.
///
/// Der Port ist bewusst nicht fest: ein belegter Port ließe die Anmeldung
/// scheitern, und ein fester Port wäre für andere Programme auf dem Rechner
/// vorhersehbar.
final class LoopbackSignInPresenter: GoogleSignInPresenter, @unchecked Sendable {

    /// Eine Fortsetzung, die genau einmal fortgesetzt wird.
    ///
    /// Netzwerk-Rückrufe kommen mehrfach — ein zweiter Aufruf von `resume`
    /// beendet das Programm sofort. Ein Browser, der nebenbei `/favicon.ico`
    /// holt, reicht dafür schon.
    private final class OneShot<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value, Error>?

        init(_ continuation: CheckedContinuation<Value, Error>) {
            self.continuation = continuation
        }

        private func take() -> CheckedContinuation<Value, Error>? {
            lock.lock(); defer { lock.unlock() }
            let value = continuation
            continuation = nil
            return value
        }

        func resume(returning value: Value) { take()?.resume(returning: value) }
        func resume(throwing error: Error) { take()?.resume(throwing: error) }
    }

    private let queue = DispatchQueue(label: "de.nori.oauth.loopback")
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var redirect: OneShot<URL>?

    func beginRedirect() async throws -> String {
        cancel()
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Nur die Rückschleife. Der Server soll für das Netz nicht sichtbar
        // sein, auch nicht für die Dauer einer Anmeldung.
        parameters.requiredInterfaceType = .loopback

        let listener = try NWListener(using: parameters, on: .any)
        lock.lock(); self.listener = listener; lock.unlock()

        let address = try await withCheckedThrowingContinuation { (raw: CheckedContinuation<String, Error>) in
            let once = OneShot(raw)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let assigned = listener.port?.rawValue else {
                        once.resume(throwing: GoogleOAuthError.transport("Kein Port für die Anmeldung."))
                        return
                    }
                    self?.lock.lock()
                    self?.port = assigned
                    self?.lock.unlock()
                    once.resume(returning: "http://127.0.0.1:\(assigned)")
                case .failed(let error):
                    once.resume(throwing: GoogleOAuthError.transport(error.localizedDescription))
                case .cancelled:
                    once.resume(throwing: GoogleOAuthError.cancelled)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
        return address
    }

    func awaitRedirect(authorizationURL: URL) async throws -> URL {
        let url = try await withCheckedThrowingContinuation { (raw: CheckedContinuation<URL, Error>) in
            lock.lock()
            redirect = OneShot(raw)
            lock.unlock()
            // Im echten Browser, nicht in einer eingebetteten WebView: eine
            // App, die das Anmeldeformular selbst zeichnet, sieht dabei jedes
            // Passwort — und Google lehnt solche Anmeldungen ab.
            DispatchQueue.main.async { NSWorkspace.shared.open(authorizationURL) }
        }
        cancel()
        return url
    }

    func cancel() {
        lock.lock()
        let listener = self.listener
        self.listener = nil
        lock.unlock()
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
    }

    // MARK: - Die eine Anfrage, auf die es ankommt

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            guard let path = Self.requestPath(text) else {
                connection.cancel()
                return
            }
            // Browser holen nebenbei `/favicon.ico`. Diese Anfragen sind nicht
            // die Antwort und dürfen die Anmeldung nicht beenden.
            guard path.contains("code=") || path.contains("error=") else {
                self.reply(on: connection, body: Self.ignoredPage, close: true)
                return
            }

            self.lock.lock()
            let port = self.port
            let redirect = self.redirect
            self.lock.unlock()

            // Die Seite sagt, was passiert ist. Vorher stand dort auch bei
            // einer Ablehnung „Nori ist verbunden".
            let failed = path.contains("error=")
            self.reply(on: connection, body: failed ? Self.failedPage : Self.donePage, close: true)
            // Zurück zu Nori, statt den Nutzer im Browser stehen zu lassen.
            DispatchQueue.main.async { NSApplication.shared.activate() }
            guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
                redirect?.resume(throwing: GoogleOAuthError.transport("Antwort nicht lesbar."))
                return
            }
            redirect?.resume(returning: url)
        }
    }

    /// Aus „GET /?code=… HTTP/1.1" wird „/?code=…".
    static func requestPath(_ request: String) -> String? {
        guard let line = request.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }

    private func reply(on connection: NWConnection, body: String, close: Bool) {
        let payload = Data(body.utf8)
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(payload.count)\r
        Connection: close\r
        \r

        """
        connection.send(content: Data(header.utf8) + payload, completion: .contentProcessed { _ in
            if close { connection.cancel() }
        })
    }

    private static let donePage = """
    <!doctype html><html lang="de"><head><meta charset="utf-8">
    <title>Nori</title>
    <style>body{font:16px -apple-system,system-ui,sans-serif;margin:4rem auto;max-width:32rem;
    text-align:center;color:#222}</style></head>
    <body><h1>Anmeldung abgeschlossen</h1>
    <p>Nori richtet den Abgleich jetzt ein. Du kannst dieses Fenster schließen.</p></body></html>
    """

    private static let failedPage = """
    <!doctype html><html lang="de"><head><meta charset="utf-8">
    <title>Nori</title>
    <style>body{font:16px -apple-system,system-ui,sans-serif;margin:4rem auto;max-width:32rem;
    text-align:center;color:#222}</style></head>
    <body><h1>Anmeldung nicht abgeschlossen</h1>
    <p>Google hat keine Berechtigung erteilt. Du kannst dieses Fenster schließen und es in Nori erneut versuchen.</p></body></html>
    """

    private static let ignoredPage = """
    <!doctype html><html lang="de"><head><meta charset="utf-8"><title>Nori</title></head><body></body></html>
    """
}
