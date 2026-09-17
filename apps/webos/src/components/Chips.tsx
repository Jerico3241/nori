// Eine Reihe Schnellfilter.
//
// Knöpfe statt eines Auswahlfelds: ein Dropdown führt den Fokus in eine Liste,
// die man mit einer Fernbedienung nicht kommen sieht. Die Reihe scrollt
// waagerecht, wenn sie breiter ist als der Bildschirm — etwa bei vielen Genres.

import { SpotButton } from "../navigation/Spot";

export interface ChipOption<T extends string> {
  value: T;
  label: string;
  count?: number;
}

export function ChipRow<T extends string>({
  options, value, onChange, route, area, className, label,
}: {
  options: ChipOption<T>[];
  value: T;
  onChange(value: T): void;
  route: string;
  area: string;
  className?: string;
  label: string;
}) {
  return (
    <div
      className={`chips${className ? ` ${className}` : ""}`}
      role="group"
      aria-label={label}
      data-scroll-x=""
      data-scroll-key={`chips-${area}`}
    >
      <div className="chips-inner" data-nav-row="">
        {options.map((option) => (
          <SpotButton
            key={option.value}
            className={`chip${option.value === value ? " active" : ""}`}
            aria-pressed={option.value === value}
            focusRoute={route}
            focusArea={area}
            focusKey={`${area}-${option.value}`}
            onClick={() => onChange(option.value)}
          >
            {option.label}
            {typeof option.count === "number" ? <small>{option.count}</small> : null}
          </SpotButton>
        ))}
      </div>
    </div>
  );
}
