// Dialog und Auswahlmenü.
//
// Was jedes Overlay auf einem Fernseher können muss:
//
// - **Den Fokus einsperren.** Sonst wandert er mit „links" auf die Seite
//   darunter, die man nicht bedient sieht.
// - **Beim Öffnen auf das Richtige.** Im Menü ist das der gewählte Eintrag,
//   nicht der erste: wer bei Staffel 24 steht, fängt nicht bei 1 an.
// - **Mit Zurück schließen**, ohne die Ansicht zu verlassen.
// - **Beim Schließen den Fokus zurückgeben** — an das Element, von dem aus es
//   geöffnet wurde. Das leistet `SpotArea`.

import type { ReactNode } from "react";

import { useBackHandler } from "../navigation/back";
import { SpotArea, SpotButton, useAutoFocus } from "../navigation/Spot";
import { Icon } from "./Icon";

export function Dialog({
  open, onClose, eyebrow, title, className, initial = ".spottable", id, children,
}: {
  open: boolean;
  onClose(): void;
  eyebrow?: string;
  title: string;
  className?: string;
  /** Welches Element beim Öffnen den Fokus bekommt. */
  initial?: string;
  id: string;
  children: ReactNode;
}) {
  const ref = useAutoFocus(open, initial);
  useBackHandler(() => {
    if (!open) return false;
    onClose();
    return true;
  }, open);

  if (!open) return null;
  return (
    <>
      <div className="dialog-shade" aria-hidden="true" />
      <SpotArea
        className={`dialog${className ? ` ${className}` : ""}`}
        restrict="self-only"
        spotlightId={id}
        role="dialog"
        aria-label={title}
      >
        <div ref={ref} className="dialog-body">
          <header className="dialog-head">
            {eyebrow ? <div className="eyebrow">{eyebrow}</div> : null}
            <h2>{title}</h2>
          </header>
          <div className="dialog-scroll" data-scroll-y="">{children}</div>
        </div>
      </SpotArea>
    </>
  );
}

export interface MenuOption<T extends string> {
  value: T;
  label: string;
  detail?: string;
}

export function Menu<T extends string>({
  open, onClose, eyebrow, title, options, value, onPick, id,
}: {
  open: boolean;
  onClose(): void;
  eyebrow?: string;
  title: string;
  options: MenuOption<T>[];
  value: T | null;
  onPick(value: T): void;
  id: string;
}) {
  return (
    <Dialog
      open={open}
      onClose={onClose}
      eyebrow={eyebrow}
      title={title}
      id={id}
      className="menu"
      initial={value !== null ? ".menu-item.selected" : ".menu-item"}
    >
      <div className="menu-list">
        {options.map((option) => {
          const selected = option.value === value;
          return (
            <SpotButton
              key={option.value}
              className={`menu-item${selected ? " selected" : ""}`}
              aria-pressed={selected}
              focusKey={`${id}-${option.value}`}
              onClick={() => {
                onPick(option.value);
                onClose();
              }}
            >
              <span className="menu-label">{option.label}</span>
              {option.detail ? <small>{option.detail}</small> : null}
              <span className="menu-check">{selected ? <Icon name="check" /> : null}</span>
            </SpotButton>
          );
        })}
      </div>
    </Dialog>
  );
}
