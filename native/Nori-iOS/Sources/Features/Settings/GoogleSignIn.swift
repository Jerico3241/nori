import AuthenticationServices
import Foundation
import SwiftUI

/// Die Google-Anmeldung auf iOS und iPadOS.
///
/// `ASWebAuthenticationSession` ist der von Apple und von Google vorgesehene
/// Weg: die Anmeldung läuft in Safari, nicht in einer eingebetteten WebView.
/// Der Unterschied ist keiner der Optik — eine App, die das Anmeldeformular
/// selbst zeichnet, sieht dabei jedes Passwort, und Google lehnt solche
/// Anmeldungen ab.
///
/// Zurück kommt Google über das umgedrehte Client-Kürzel. Der früher übliche
/// Weg, den Code von Hand zu kopieren (`urn:ietf:wg:oauth:2.0:oob`), ist seit
/// 2022 abgeschaltet und kommt hier nicht vor.
@MainActor
final class WebAuthenticationSignInPresenter: NSObject, GoogleSignInPresenter, @unchecked Sendable {
    private let scheme: String
    private var session: ASWebAuthenticationSession?

    init(reversedClientId: String) {
        self.scheme = reversedClientId
        super.init()
    }

    nonisolated func beginRedirect() async throws -> String {
        // Ein Pfad muss dran: eine reine Schema-Adresse ist keine gültige
        // Rückleitung.
        "\(scheme):/oauth2redirect"
    }

    nonisolated func awaitRedirect(authorizationURL: URL) async throws -> URL {
        try await MainActor.run { self }.start(authorizationURL)
    }

    nonisolated func cancel() {
        Task { @MainActor in
            session?.cancel()
            session = nil
        }
    }

    private func start(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleOAuthError.cancelled)
                } else {
                    continuation.resume(throwing: GoogleOAuthError.transport(
                        error?.localizedDescription ?? "Die Anmeldung wurde beendet."))
                }
            }
            session.presentationContextProvider = self
            // Ohne das trägt die Anmeldung die Cookies aus Safari — wer dort
            // angemeldet ist, käme ohne Rückfrage durch. Für eine Verbindung,
            // die dauerhaft Zugriff bekommt, soll die Frage tatsächlich
            // gestellt werden.
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() {
                continuation.resume(throwing: GoogleOAuthError.transport("Die Anmeldung ließ sich nicht öffnen."))
            }
        }
    }
}

extension WebAuthenticationSignInPresenter: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.first { $0.activationState == .foregroundActive }?.keyWindow
                ?? scenes.first?.keyWindow
            return window ?? ASPresentationAnchor()
        }
    }
}
