// Der Umschalter zwischen Anime, Serien und K-Drama.
//
// Derselbe Bereichsbegriff wie in den Apple-Apps: ein Bereich ist ein Paar aus
// Quelle und Genre, nicht bloß eine Quelle. K-Drama liegt bei Serienstream
// unter einem Genre, es wird deshalb nichts zusätzlich abgerufen.

import { LIBRARY_SCOPES, SCOPES } from "@nori/core";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { useLibrary } from "../state/library";

export function ScopeTabs({ route }: { route: string }) {
  const { state, setScope } = useLibrary();
  return (
    <SpotArea className="scope-tabs" spotlightId={`scope-${route}`}>
      {LIBRARY_SCOPES.map((scope) => (
        <SpotButton
          key={scope}
          className={state.scope === scope ? "selected" : ""}
          aria-pressed={state.scope === scope}
          focusRoute={route}
          focusArea="scope"
          focusKey={`scope-${scope}`}
          onClick={() => setScope(scope)}
        >
          {SCOPES[scope].label}
        </SpotButton>
      ))}
    </SpotArea>
  );
}
