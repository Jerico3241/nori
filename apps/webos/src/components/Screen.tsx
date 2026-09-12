// Der Rahmen jeder Ansicht: Scrollbereich, Seitenkopf, Inhalt.
//
// Genau ein senkrechter Scrollbereich je Ansicht (`data-scroll-y`). Die
// Navigation richtet sich danach: sie weiß damit, welcher Bereich sich bewegen
// muss, damit ein fokussiertes Element vollständig sichtbar wird, und der
// Scrollstand lässt sich beim Verlassen merken und beim Zurückkehren
// wiederherstellen.
//
// Der Seitenkopf scrollt mit — er ist weder `sticky` noch `fixed`. Es gibt
// damit keinen Bereich, unter dem ein fokussiertes Element verschwinden
// könnte.

import { useLayoutEffect, useRef, type ReactNode } from "react";
import { saveScroll } from "../navigation/focusMemory";

export function Screen({ route, eyebrow, title, actions, className, children }: {
  route: string;
  eyebrow?: ReactNode;
  title?: ReactNode;
  actions?: ReactNode;
  className?: string;
  children?: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const node = ref.current;
    return () => saveScroll(route, node);
  }, [route]);

  const hasHead = Boolean(eyebrow || title || actions);
  return (
    <div className={`screen${className ? ` ${className}` : ""}`} ref={ref} data-scroll-y="" data-route={route}>
      {hasHead ? (
        <header className="topline">
          <div className="topline-copy">
            {eyebrow ? <div className="eyebrow">{eyebrow}</div> : null}
            {title ? <h1>{title}</h1> : null}
          </div>
          {actions ? <div className="top-actions">{actions}</div> : null}
        </header>
      ) : null}
      {children}
    </div>
  );
}
