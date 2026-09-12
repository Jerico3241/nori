// Zurück-Verhalten, an einer Stelle.
//
// Die Zurück-Taste darf nie überraschen: sie schließt zuerst, was zuletzt
// aufging (Drawer, Modal, Player-Bedienung), und geht erst dann eine Ansicht
// zurück. Umgesetzt als Stapel: wer etwas Überlagerndes öffnet, meldet hier
// einen Griff an und nimmt ihn beim Schließen zurück. Der oberste Griff
// gewinnt.

import { createContext, useCallback, useContext, useEffect, useRef, type ReactNode } from "react";
import { isBack } from "./keys";
import { log } from "../services/log";

/** Gibt `true` zurück, wenn der Griff die Taste verbraucht hat. */
export type BackHandler = () => boolean;

interface BackContextValue {
  push(handler: BackHandler): () => void;
}

const BackContext = createContext<BackContextValue | null>(null);

export function BackProvider({ children, onExhausted }: {
  children: ReactNode;
  onExhausted: () => void;
}) {
  const handlers = useRef<BackHandler[]>([]);
  const exhausted = useRef(onExhausted);
  exhausted.current = onExhausted;

  const push = useCallback((handler: BackHandler) => {
    handlers.current.push(handler);
    return () => {
      const index = handlers.current.lastIndexOf(handler);
      if (index >= 0) handlers.current.splice(index, 1);
    };
  }, []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!isBack(event)) return;
      // Im Suchfeld löscht die Rücktaste einer Tastatur ein Zeichen. Als
      // „Zurück" gelesen, verließ jeder Tippfehler die Seite.
      const target = document.activeElement;
      const typing = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement;
      if (typing && event.key === "Backspace") return;
      event.preventDefault();
      event.stopPropagation();
      for (let i = handlers.current.length - 1; i >= 0; i -= 1) {
        if (handlers.current[i]()) {
          log("nav", "Zurück von Griff verbraucht");
          return;
        }
      }
      exhausted.current();
    };
    // `capture`, damit ein fokussierter Knopf die Taste nicht vorher abfängt.
    window.addEventListener("keydown", onKeyDown, true);
    return () => window.removeEventListener("keydown", onKeyDown, true);
  }, []);

  return <BackContext.Provider value={{ push }}>{children}</BackContext.Provider>;
}

/**
 * Einen Zurück-Griff anmelden, solange `active` gilt.
 *
 * `handler` gibt `true` zurück, wenn es die Taste verbraucht hat.
 */
export function useBackHandler(handler: BackHandler, active = true): void {
  const ctx = useContext(BackContext);
  const ref = useRef(handler);
  ref.current = handler;

  useEffect(() => {
    if (!ctx || !active) return;
    return ctx.push(() => ref.current());
  }, [ctx, active]);
}
