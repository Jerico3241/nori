// Die Bedienung im Player.
//
// Sie liegt über dem Bild und ist im Normalfall unsichtbar. Sichtbar wird sie
// bei jedem Tastendruck, beim Öffnen, bei Pause und beim Spulen — und
// verschwindet nach der eingestellten Zeit wieder von selbst.

import type { Episode, SkipSegment } from "@nori/core";
import { Icon } from "../components/Icon";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { Seekbar } from "./Seekbar";

export interface ControlsProps {
  visible: boolean;
  title: string;
  subtitle: string;
  paused: boolean;
  position: number;
  duration: number;
  buffered: number;
  scrubbing: boolean;
  seekTarget: number;
  seekStep: number;
  hosterLabel: string;
  /** Überspringbarer Abschnitt an der aktuellen Position, sonst null. */
  skipSegment: SkipSegment | null;
  previous: Episode | null;
  next: Episode | null;
  onTogglePlay(): void;
  onSeek(delta: number): void;
  onPrevious(): void;
  onNext(): void;
  onOpenDrawer(): void;
  onSkip(): void;
  onExit(): void;
}

export function PlayerControls(props: ControlsProps) {
  return (
    <div className={`player-chrome ${props.visible ? "visible" : ""}`} aria-hidden={!props.visible}>
      <div className="player-top">
        <SpotButton
          className="player-exit"
          focusKey="player-exit"
          spotlightDisabled={!props.visible}
          aria-label="Zurück"
          onClick={props.onExit}
        >
          <Icon name="back" />
          <span>Zurück</span>
        </SpotButton>
        <div className="player-title">
          <strong>{props.title}</strong>
          <small>{props.subtitle}</small>
        </div>
      </div>

      <SpotArea className="player-controls" spotlightId="player-controls">
        <Seekbar
          position={props.position}
          duration={props.duration}
          buffered={props.buffered}
          scrubbing={props.scrubbing}
          target={props.seekTarget}
        />
        <div className="transport-row">
          <SpotButton
            className="transport-button"
            focusKey="prev"
            spotlightDisabled={!props.visible || !props.previous}
            disabled={!props.previous}
            aria-label="Vorherige Folge"
            onClick={props.onPrevious}
          >
            <Icon name="previous" />
          </SpotButton>
          <SpotButton
            className="transport-button"
            focusKey="back10"
            spotlightDisabled={!props.visible}
            aria-label={`${props.seekStep} Sekunden zurück`}
            onClick={() => props.onSeek(-props.seekStep)}
          >
            <Icon name="rewind" />
            <small>{props.seekStep}</small>
          </SpotButton>
          <SpotButton
            className="transport-button play-button"
            focusKey="play"
            spotlightDisabled={!props.visible}
            aria-label={props.paused ? "Abspielen" : "Pause"}
            onClick={props.onTogglePlay}
          >
            <Icon name={props.paused ? "play" : "pause"} />
          </SpotButton>
          <SpotButton
            className="transport-button"
            focusKey="fwd10"
            spotlightDisabled={!props.visible}
            aria-label={`${props.seekStep} Sekunden vor`}
            onClick={() => props.onSeek(props.seekStep)}
          >
            <Icon name="forward" />
            <small>{props.seekStep}</small>
          </SpotButton>
          <SpotButton
            className="transport-button"
            focusKey="next"
            spotlightDisabled={!props.visible || !props.next}
            disabled={!props.next}
            aria-label="Nächste Folge"
            onClick={props.onNext}
          >
            <Icon name="next" />
          </SpotButton>
        </div>
        <div className="player-actions">
          {props.skipSegment ? (
            <SpotButton
              className="skip-button"
              focusKey="skip"
              spotlightDisabled={!props.visible}
              aria-label={
                props.skipSegment.type === "outro"
                  ? "Outro überspringen"
                  : props.skipSegment.type === "recap"
                    ? "Zusammenfassung überspringen"
                    : "Intro überspringen"
              }
              onClick={props.onSkip}
            >
              <Icon name="forward" />
              {props.skipSegment.type === "outro"
                ? "Outro überspringen"
                : props.skipSegment.type === "recap"
                  ? "Skip"
                  : "Intro überspringen"}
            </SpotButton>
          ) : null}
          <SpotButton
            focusKey="drawer"
            spotlightDisabled={!props.visible}
            onClick={props.onOpenDrawer}
          >
            <Icon name="layers" />
            <span>Sprache &amp; Hoster</span>
            <small>{props.hosterLabel}</small>
          </SpotButton>
        </div>
      </SpotArea>
    </div>
  );
}
