// Googles Fluss für Fernseher und Geräte mit eingeschränkter Eingabe.
//
// Auf einem Fernseher gibt es keinen Browser zum Anmelden und keine Tastatur
// für ein Passwort. Das Gerät holt einen kurzen Code, der Nutzer gibt ihn am
// Telefon ein, und das Gerät fragt in Ruhe nach.
//
// Die Antwortcodes dieses Flusses sind eigen — `authorization_pending` ist der
// Normalfall und kein Fehler, `slow_down` eine Bitte und kein Abbruch —, und
// genau das wird hier geprüft.

import assert from "node:assert/strict";
import test from "node:test";
import {
  clientIdValidationError, clientSecretValidationError, deviceQrPayload,
  GoogleAuthError, GoogleDeviceAuthorization, MemoryTokenStore, tokensAreValid,
} from "../src/google/auth.js";

class ScriptedFetch {
  calls: { url: string; body: URLSearchParams }[] = [];
  constructor(private script: { status: number; body: unknown }[]) {}
  readonly fetchImpl: typeof fetch = (async (url: string | URL | Request, init: RequestInit = {}) => {
    this.calls.push({ url: String(url), body: new URLSearchParams(String(init.body ?? "")) });
    const next = this.script.shift() ?? { status: 200, body: {} };
    return new Response(JSON.stringify(next.body), { status: next.status });
  }) as unknown as typeof fetch;
}

const config = { clientId: "1234.apps.googleusercontent.com", clientSecret: "tv-secret" };

function authFor(script: ScriptedFetch, store = new MemoryTokenStore(), now = () => 1_000_000) {
  return new GoogleDeviceAuthorization({
    configuration: config, tokenStore: store, fetchImpl: script.fetchImpl, now,
  });
}

test("Der Gerätecode kommt mit Adresse, Code und Wartezeit zurück", async () => {
  const script = new ScriptedFetch([{
    status: 200,
    body: {
      device_code: "dc", user_code: "ABCD-EFGH",
      verification_url: "https://www.google.com/device", expires_in: 1800, interval: 5,
    },
  }]);

  const authorization = await authFor(script).requestDeviceCode();

  assert.equal(authorization.userCode, "ABCD-EFGH");
  assert.equal(authorization.verificationUrl, "https://www.google.com/device");
  assert.equal(authorization.intervalMs, 5_000);
  assert.equal(authorization.expiresAt, 1_000_000 + 1_800_000);
  // Nur der kleinste Bereich, der reicht.
  assert.equal(script.calls[0].body.get("scope"), "https://www.googleapis.com/auth/drive.appdata");
  // Beim Abholen des Codes verlangt Google kein Secret.
  assert.equal(script.calls[0].body.get("client_secret"), null);
});

test("Ohne Zugangsdaten wird gar nicht erst gefragt", async () => {
  const script = new ScriptedFetch([]);
  const auth = new GoogleDeviceAuthorization({
    configuration: { clientId: "", clientSecret: "" },
    tokenStore: new MemoryTokenStore(), fetchImpl: script.fetchImpl,
  });

  assert.equal(auth.isConfigured, false);
  await assert.rejects(() => auth.requestDeviceCode(), (error: GoogleAuthError) => {
    assert.equal(error.kind, "notConfigured");
    return true;
  });
  assert.equal(script.calls.length, 0);
});

/** `authorization_pending` ist der Normalfall, solange der Nutzer noch tippt. */
test("Wartende Zustimmung wird weiter abgefragt", async () => {
  const script = new ScriptedFetch([
    { status: 428, body: { error: "authorization_pending" } },
    { status: 428, body: { error: "authorization_pending" } },
    { status: 200, body: { access_token: "at", refresh_token: "rt", expires_in: 3600 } },
  ]);
  const store = new MemoryTokenStore();
  const waits: number[] = [];

  const tokens = await authFor(script, store).pollForTokens(
    { deviceCode: "dc", userCode: "X", verificationUrl: "u", expiresAt: 9_000_000, intervalMs: 5_000 },
    { sleep: async (ms) => { waits.push(ms); } },
  );

  assert.equal(tokens.accessToken, "at");
  assert.equal(store.read()?.refreshToken, "rt");
  assert.deepEqual(waits, [5_000, 5_000, 5_000]);
  assert.equal(script.calls[0].body.get("grant_type"), "urn:ietf:params:oauth:grant-type:device_code");
  // Anders als beim Fluss für native Apps verlangt Google hier ein Secret.
  assert.equal(script.calls[0].body.get("client_secret"), "tv-secret");
});

/** `slow_down` ist eine Bitte und kein Abbruch — fünf Sekunden mehr. */
test("slow_down verlängert die Wartezeit", async () => {
  const script = new ScriptedFetch([
    { status: 403, body: { error: "slow_down" } },
    { status: 403, body: { error: "slow_down" } },
    { status: 200, body: { access_token: "at", refresh_token: "rt", expires_in: 3600 } },
  ]);
  const waits: number[] = [];

  await authFor(script).pollForTokens(
    { deviceCode: "dc", userCode: "X", verificationUrl: "u", expiresAt: 9_000_000, intervalMs: 5_000 },
    { sleep: async (ms) => { waits.push(ms); } },
  );

  assert.deepEqual(waits, [5_000, 10_000, 15_000]);
});

test("Eine Ablehnung beendet die Abfrage", async () => {
  const script = new ScriptedFetch([{ status: 403, body: { error: "access_denied" } }]);

  await assert.rejects(
    () => authFor(script).pollForTokens(
      { deviceCode: "dc", userCode: "X", verificationUrl: "u", expiresAt: 9_000_000, intervalMs: 1 },
      { sleep: async () => {} },
    ),
    (error: GoogleAuthError) => { assert.equal(error.kind, "denied"); return true; },
  );
});

test("Ein abgelaufener Code beendet die Abfrage", async () => {
  const script = new ScriptedFetch([{ status: 400, body: { error: "expired_token" } }]);

  await assert.rejects(
    () => authFor(script).pollForTokens(
      { deviceCode: "dc", userCode: "X", verificationUrl: "u", expiresAt: 9_000_000, intervalMs: 1 },
      { sleep: async () => {} },
    ),
    (error: GoogleAuthError) => { assert.equal(error.kind, "expired"); return true; },
  );
});

/** Die Abfrage läuft nicht ewig: irgendwann ist der Code abgelaufen. */
test("Nach Ablauf des Codes wird nicht weiter gefragt", async () => {
  const script = new ScriptedFetch([]);
  let clock = 1_000_000;
  const auth = new GoogleDeviceAuthorization({
    configuration: config, tokenStore: new MemoryTokenStore(),
    fetchImpl: script.fetchImpl, now: () => clock,
  });

  await assert.rejects(
    () => auth.pollForTokens(
      { deviceCode: "dc", userCode: "X", verificationUrl: "u", expiresAt: 1_000_500, intervalMs: 5_000 },
      { sleep: async () => { clock += 5_000; } },
    ),
    (error: GoogleAuthError) => { assert.equal(error.kind, "expired"); return true; },
  );
});

test("Abbrechen beendet die Abfrage sofort", async () => {
  const script = new ScriptedFetch([]);
  const controller = new AbortController();
  controller.abort();

  await assert.rejects(
    () => authFor(script).pollForTokens(
      { deviceCode: "dc", userCode: "X", verificationUrl: "u", expiresAt: 9_000_000, intervalMs: 1 },
      { signal: controller.signal, sleep: async () => {} },
    ),
    (error: GoogleAuthError) => { assert.equal(error.kind, "denied"); return true; },
  );
  assert.equal(script.calls.length, 0);
});

/**
 * Ohne Auffrischungstoken hielte die Verbindung eine Stunde und wäre danach
 * ohne Zutun weg. Das ist kein Erfolg und wird auch nicht als einer abgelegt.
 */
test("Ohne Auffrischungstoken gilt die Verbindung nicht als hergestellt", async () => {
  const script = new ScriptedFetch([{ status: 200, body: { access_token: "at", expires_in: 3600 } }]);
  const store = new MemoryTokenStore();

  await assert.rejects(
    () => authFor(script, store).pollForTokens(
      { deviceCode: "dc", userCode: "X", verificationUrl: "u", expiresAt: 9_000_000, intervalMs: 1 },
      { sleep: async () => {} },
    ),
    (error: GoogleAuthError) => { assert.equal(error.kind, "noRefreshToken"); return true; },
  );
  assert.equal(store.read(), null);
});

// --- Token ------------------------------------------------------------------

test("Ein gültiges Token wird ohne Not nicht erneuert", async () => {
  const script = new ScriptedFetch([]);
  const store = new MemoryTokenStore({ accessToken: "at", refreshToken: "rt", expiresAt: 9_000_000 });

  assert.equal(await authFor(script, store).validAccessToken(), "at");
  assert.equal(script.calls.length, 0);
});

test("Beim Erneuern bleibt der Auffrischungstoken erhalten", async () => {
  const script = new ScriptedFetch([{ status: 200, body: { access_token: "neu", expires_in: 3600 } }]);
  const store = new MemoryTokenStore({ accessToken: "alt", refreshToken: "rt", expiresAt: 0 });

  const token = await authFor(script, store).validAccessToken();

  assert.equal(token, "neu");
  assert.equal(store.read()?.refreshToken, "rt", "Der Auffrischungstoken ist verloren gegangen");
});

/**
 * Zwei gleichzeitige Erneuerungen desselben Tokens beantwortet Google mit
 * `invalid_grant` — und danach ist die Verbindung weg.
 */
test("Gleichzeitige Erneuerungen teilen sich eine Anfrage", async () => {
  const script = new ScriptedFetch([{ status: 200, body: { access_token: "neu", expires_in: 3600 } }]);
  const store = new MemoryTokenStore({ accessToken: "alt", refreshToken: "rt", expiresAt: 0 });
  const auth = authFor(script, store);

  const results = await Promise.all([auth.validAccessToken(), auth.validAccessToken(), auth.validAccessToken()]);

  assert.deepEqual(results, ["neu", "neu", "neu"]);
  assert.equal(script.calls.length, 1, "Drei Anfragen haben den Token dreimal erneuert");
});

test("Ein ungültiger Auffrischungstoken wird weggeräumt", async () => {
  const script = new ScriptedFetch([{ status: 400, body: { error: "invalid_grant" } }]);
  const store = new MemoryTokenStore({ accessToken: "alt", refreshToken: "rt", expiresAt: 0 });

  await assert.rejects(() => authFor(script, store).validAccessToken(), (error: GoogleAuthError) => {
    assert.equal(error.kind, "notAuthorized");
    return true;
  });
  assert.equal(store.read(), null, "Der wertlose Token liegt noch im Speicher");
});

/** Eine Google-Störung ist nicht dasselbe wie „abgemeldet". */
test("Ein Serverfehler löscht die Anmeldung nicht", async () => {
  const script = new ScriptedFetch([{ status: 500, body: { error: "backendError" } }]);
  const store = new MemoryTokenStore({ accessToken: "alt", refreshToken: "rt", expiresAt: 0 });

  await assert.rejects(() => authFor(script, store).validAccessToken());

  assert.notEqual(store.read(), null, "Eine Google-Störung hat die Anmeldung gelöscht");
});

test("Trennen löscht nur die Tokens", () => {
  const store = new MemoryTokenStore({ accessToken: "at", refreshToken: "rt", expiresAt: 9_000_000 });
  authFor(new ScriptedFetch([]), store).disconnectDevice();
  assert.equal(store.read(), null);
});

test("Der Kontofingerabdruck verrät den Token nicht", () => {
  const store = new MemoryTokenStore({ accessToken: "at", refreshToken: "geheim", expiresAt: 0 });
  const fingerprint = authFor(new ScriptedFetch([]), store).accountFingerprint;

  assert.ok(fingerprint);
  assert.ok(!fingerprint!.includes("geheim"));
  assert.equal(authFor(new ScriptedFetch([]), new MemoryTokenStore()).accountFingerprint, null);
});

test("Ein Token, das gleich abläuft, gilt als abgelaufen", () => {
  const tokens = { accessToken: "at", refreshToken: "rt", expiresAt: 100_000 };
  assert.equal(tokensAreValid(tokens, 0), true);
  assert.equal(tokensAreValid(tokens, 99_000), false, "Zehn Sekunden Restlaufzeit gelten noch als gültig");
  assert.equal(tokensAreValid(null, 0), false);
});

// --- Zugangsdaten prüfen ----------------------------------------------------
//
// Dieselben Fälle wie `GoogleClientIDTests.swift`. Mit einer falschen
// Client-ID antwortet Google mit `invalid_client`, und auf dem Fernseher sieht
// das aus wie „der Abgleich ist kaputt" statt wie ein Tippfehler.

test("Eine wohlgeformte Client-ID wird angenommen", () => {
  assert.equal(clientIdValidationError("123456-abc.apps.googleusercontent.com"), null);
  // Umschliessender Leerraum kommt beim Einfügen ständig mit.
  assert.equal(clientIdValidationError("  123456-abc.apps.googleusercontent.com \n"), null);
});

test("Was keine Client-ID ist, wird abgewiesen", () => {
  assert.ok(clientIdValidationError(""));
  assert.ok(clientIdValidationError("   "));
  assert.ok(clientIdValidationError("falsche-eingabe"));
  assert.ok(clientIdValidationError("1234.apps.google.com"));
  // Der reine Suffix ohne Kennung davor ist keine Client-ID.
  assert.ok(clientIdValidationError(".apps.googleusercontent.com"));
});

test("Das Client-Secret darf nicht leer sein und keinen Leerraum enthalten", () => {
  assert.equal(clientSecretValidationError("GOCSPX-abcdef"), null);
  assert.equal(clientSecretValidationError("  GOCSPX-abcdef  "), null);
  assert.ok(clientSecretValidationError(""));
  assert.ok(clientSecretValidationError("GOCSPX abcdef"));
});

// --- RFC 8628: was Google mitschickt ----------------------------------------
//
// `verification_uri` heisst das Feld in RFC 8628, `verification_url` in Googles
// älterer Beschreibung. Google schickt beide; Nori liest beide und erfindet
// keines.

test("Die Adresse nach RFC 8628 wird gelesen", async () => {
  const script = new ScriptedFetch([{
    status: 200,
    body: {
      device_code: "dc", user_code: "ABCD-EFGH",
      verification_uri: "https://www.google.com/device",
      verification_uri_complete: "https://www.google.com/device?user_code=ABCD-EFGH",
      expires_in: 1800, interval: 5,
    },
  }]);

  const device = await authFor(script).requestDeviceCode();

  assert.equal(device.verificationUrl, "https://www.google.com/device");
  assert.equal(device.verificationUrlComplete, "https://www.google.com/device?user_code=ABCD-EFGH");
  // Und die vollständige gewinnt im QR-Code: der Nutzer tippt dann nichts mehr.
  assert.equal(deviceQrPayload(device), "https://www.google.com/device?user_code=ABCD-EFGH");
});

test("Ohne vollständige Adresse bleibt sie leer, statt gebaut zu werden", async () => {
  const script = new ScriptedFetch([{
    status: 200,
    body: {
      device_code: "dc", user_code: "ABCD-EFGH",
      verification_url: "https://www.google.com/device",
      expires_in: 1800, interval: 5,
    },
  }]);

  const device = await authFor(script).requestDeviceCode();

  assert.equal(device.verificationUrl, "https://www.google.com/device");
  assert.equal(device.verificationUrlComplete, undefined);
  // Nichts angehängt. Welchen Parameter Google an `google.com/device` erwartet,
  // sichert es nirgends zu — ein falscher führt auf eine Fehlerseite.
  assert.equal(deviceQrPayload(device), "https://www.google.com/device");
});

/**
 * Eine Antwort ohne Adresse ist kaputt und wird als solche behandelt.
 *
 * Vorher stand hier ein Rückfall auf `https://www.google.com/device`. Der war
 * geraten: eine Antwort ohne Adresse heisst nicht, dass diese Adresse gilt.
 */
test("Eine Antwort ohne Anmeldeadresse wird nicht geraten", async () => {
  const script = new ScriptedFetch([{
    status: 200, body: { device_code: "dc", user_code: "ABCD-EFGH", expires_in: 1800 },
  }]);

  await assert.rejects(() => authFor(script).requestDeviceCode(), (error: GoogleAuthError) => {
    assert.equal(error.kind, "server");
    return true;
  });
});

test("Unsinnige Zahlen fallen auf Googles Voreinstellungen zurück", async () => {
  const script = new ScriptedFetch([{
    status: 200,
    body: {
      device_code: "dc", user_code: "ABCD-EFGH",
      verification_uri: "https://www.google.com/device",
      expires_in: "bald", interval: null,
    },
  }]);

  const device = await authFor(script).requestDeviceCode();

  // `NaN` als Ablaufzeit hiesse: der Code läuft nie ab und die Schleife
  // niemals aus.
  assert.equal(device.expiresAt, 1_000_000 + 1_800_000);
  assert.equal(device.intervalMs, 5_000);
});

test("Ein falscher Clienttyp fällt schon beim Gerätecode auf", async () => {
  const script = new ScriptedFetch([{ status: 401, body: { error: "invalid_client" } }]);

  await assert.rejects(() => authFor(script).requestDeviceCode(), (error: GoogleAuthError) => {
    assert.equal(error.kind, "invalidClient");
    return true;
  });
});

test("Ein verweigerter Bereich wird als solcher benannt", async () => {
  const script = new ScriptedFetch([{ status: 400, body: { error: "invalid_scope" } }]);

  await assert.rejects(
    () => authFor(script).pollForTokens(
      { deviceCode: "dc", userCode: "X", verificationUrl: "u", expiresAt: 9_000_000, intervalMs: 1 },
      { sleep: async () => {} },
    ),
    (error: GoogleAuthError) => { assert.equal(error.kind, "invalidScope"); return true; },
  );
});

test("Die Regel der Organisation wird als solche benannt", async () => {
  const script = new ScriptedFetch([{ status: 403, body: { error: "admin_policy_enforced" } }]);

  await assert.rejects(
    () => authFor(script).pollForTokens(
      { deviceCode: "dc", userCode: "X", verificationUrl: "u", expiresAt: 9_000_000, intervalMs: 1 },
      { sleep: async () => {} },
    ),
    (error: GoogleAuthError) => { assert.equal(error.kind, "adminPolicy"); return true; },
  );
});

/** Nennt Google beim `slow_down` selbst eine Wartezeit, gilt die. */
test("slow_down mit eigener Wartezeit gewinnt", async () => {
  const script = new ScriptedFetch([
    { status: 403, body: { error: "slow_down", interval: 30 } },
    { status: 200, body: { access_token: "at", refresh_token: "rt", expires_in: 3600 } },
  ]);
  const waits: number[] = [];

  await authFor(script).pollForTokens(
    { deviceCode: "dc", userCode: "X", verificationUrl: "u", expiresAt: 9_000_000, intervalMs: 5_000 },
    { sleep: async (ms) => { waits.push(ms); } },
  );

  assert.deepEqual(waits, [5_000, 30_000]);
});

// --- Doppeltes Fragen -------------------------------------------------------

test("Zwei Schleifen auf denselben Code gibt es nicht", async () => {
  const script = new ScriptedFetch([
    { status: 428, body: { error: "authorization_pending" } },
    { status: 200, body: { access_token: "at", refresh_token: "rt", expires_in: 3600 } },
  ]);
  const auth = authFor(script);
  const device = {
    deviceCode: "dc", userCode: "X", verificationUrl: "u",
    expiresAt: 9_000_000, intervalMs: 5_000,
  };
  // Ein Warten, das erst auf Zuruf weitergeht: so lässt sich die zweite
  // Schleife starten, während die erste noch steht.
  let release = () => {};
  const gate = new Promise<void>((resolve) => { release = resolve; });

  const first = auth.pollForTokens(device, { sleep: () => gate });
  await assert.rejects(
    () => auth.pollForTokens(device, { sleep: async () => {} }),
    (error: GoogleAuthError) => { assert.equal(error.kind, "pending"); return true; },
  );

  release();
  await first;
  // Nach dem Ende der ersten läuft eine zweite wieder an.
  assert.equal(script.calls.length, 2);
});

/**
 * Ein Abbruch wirkt sofort und nicht erst beim nächsten Aufwachen.
 *
 * Sonst dauert „Abbrechen" bis zu einem ganzen Wartetakt, und wer danach
 * gleich wieder „Verbinden" drückt, bekommt nichts — die alte Schleife steht
 * noch und hält ihren Platz.
 */
test("Ein Abbruch beendet auch ein laufendes Warten", async () => {
  const script = new ScriptedFetch([
    { status: 200, body: { access_token: "at", refresh_token: "rt", expires_in: 3600 } },
  ]);
  const auth = authFor(script);
  const controller = new AbortController();
  const device = {
    deviceCode: "dc", userCode: "X", verificationUrl: "u",
    expiresAt: 9_000_000, intervalMs: 5_000,
  };

  // Ein Warten, das von sich aus nie endet.
  const pending = auth.pollForTokens(device, {
    signal: controller.signal,
    sleep: () => new Promise<void>(() => {}),
  });
  controller.abort();

  await assert.rejects(() => pending, (error: GoogleAuthError) => {
    assert.equal(error.kind, "denied");
    return true;
  });
  assert.equal(script.calls.length, 0);
  // Und der Platz ist frei: die nächste Schleife läuft durch.
  const tokens = await auth.pollForTokens(device, { sleep: async () => {} });
  assert.equal(tokens.accessToken, "at");
});

test("Widerrufen räumt die Tokens weg, auch wenn Google nicht antwortet", async () => {
  const script = new ScriptedFetch([]);
  const store = new MemoryTokenStore({ accessToken: "at", refreshToken: "rt", expiresAt: 9_000_000 });
  const auth = new GoogleDeviceAuthorization({
    configuration: config,
    tokenStore: store,
    fetchImpl: (() => Promise.reject(new Error("kein Netz"))) as unknown as typeof fetch,
  });

  await auth.revokeAccess();

  // Der Widerruf ist dem Nutzer wichtig, nicht das Ergebnis dieser Anfrage.
  assert.equal(store.read(), null);
  assert.equal(auth.isConnected, false);
  void script;
});
