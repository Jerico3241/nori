// Was die Swift-Seite exportiert.
//
// Bewusst nur zwei Funktionen mit reinem C-ABI. Alles Weitere steckt im JSON,
// das durch sie hindurchgeht — siehe NoriBridge.swift.
#ifndef NORI_BRIDGE_H
#define NORI_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Nimmt eine JSON-Anfrage, gibt eine JSON-Antwort zurück. Der Puffer gehört
/// danach dem Aufrufer.
const char *nori_bridge_call(const char *request);

/// Gibt zurück, was `nori_bridge_call` geliefert hat.
void nori_bridge_free(char *response);

#endif

#ifdef __cplusplus
}
#endif
