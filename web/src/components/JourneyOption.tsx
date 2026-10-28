import { Fragment, useState, type ReactNode } from "react";
import { stopName } from "../lib/catalog";
import { clock, mins } from "../lib/eta";
import { followable, plannedKmh } from "../lib/follow";
import { WAIT_MIN_S, waitBefore } from "../lib/legs";
import { t } from "../lib/i18n";
import type { Prefer } from "../lib/prefer";
import type { Catalog, Confidence, Journey, Leg } from "../lib/types";
import { Backups, type WayPick } from "./Backups";
import { HurryPill } from "./HurryPill";
import { Icon, type IconName } from "./Icon";
import { RouteBadge } from "./RouteBadge";

/** What a ride not on a tracked vehicle rests on, how loudly to say so, and why
 *  it matters */
const RESTS: Record<
  Exclude<Confidence, "live">,
  { word: string; tone: string; dot: string; why: string }
> = {
  schedule: { word: t.schedulePart, tone: "text-slate-500", dot: "bg-slate-500", why: t.scheduleWhy },
  terminus: { word: t.terminusPart, tone: "text-slate-500", dot: "bg-slate-500", why: t.terminusWhy },
  quiet: { word: t.quietPart, tone: "text-amber-400", dot: "bg-amber-400", why: t.quietWhy },
};

/** What a ride rests on, or null for a walk or a ride on a tracked vehicle */
function rests(leg: Leg) {
  if (leg.kind !== "ride") return null;
  // An older service says only whether a vehicle was seen
  const confidence = leg.confidence ?? (leg.live ? "live" : "schedule");
  return confidence === "live" ? null : RESTS[confidence];
}

/** A button's focus ring, the same on every target of the card */
const FOCUS = "outline-none focus-visible:ring-2 focus-visible:ring-accent/70";

/** One way the planner found. Unpicked, the card is one button that picks it
 *  and says in words what is worth knowing. Picked, that button folds it again,
 *  and below it the legs open: a stop is a row with a chevron, a line a ringed
 *  badge with a map, and every note is said in full */
export function JourneyOption({
  journey,
  shown,
  onShow,
  onFollow,
  onWay,
  prefer,
  place,
  catalog,
  onStop,
  onLine,
}: {
  journey: Journey;
  /** Drawn on the map and opened */
  shown: boolean;
  onShow: () => void;
  onFollow: () => void;
  onWay: (pick: WayPick) => Promise<void>;
  prefer: Prefer;
  place: (option: number) => number;
  catalog: Catalog;
  onStop: (i: number) => void;
  onLine: (i: number) => void;
}) {
  const [backups, setBackups] = useState(false);
  return (
    <div className={`inset-panel overflow-hidden ${shown ? "ring-2 ring-accent" : ""}`}>
      <button
        onClick={onShow}
        aria-expanded={shown}
        className={`block w-full p-2 text-left hover:bg-white/5 ${FOCUS}`}
      >
        <Summary journey={journey} catalog={catalog} shown={shown} />
      </button>
      {shown && (
        <Opened
          journey={journey}
          catalog={catalog}
          onStop={onStop}
          onLine={onLine}
          onBackups={() => setBackups(true)}
          onFollow={onFollow}
        />
      )}
      {backups && (
        <Backups
          journey={journey}
          prefer={prefer}
          place={place}
          catalog={catalog}
          onWay={onWay}
          onClose={() => setBackups(false)}
        />
      )}
    </div>
  );
}

function Summary({ journey, catalog, shown }: { journey: Journey; catalog: Catalog; shown: boolean }) {
  const changes = Math.max(0, journey.rides - 1);
  return (
    <>
      <span className="flex items-baseline gap-2">
        <span className="shrink-0 font-medium whitespace-nowrap text-slate-100">
          {t.minutes(mins(journey.arr - journey.dep))}
        </span>
        <span className="shrink-0 text-xs whitespace-nowrap text-slate-400">
          {clock(journey.dep)} - {clock(journey.arr)}
        </span>
        <span className="ml-auto truncate text-xs text-slate-500">
          {journey.rides === 0 ? t.wholeWalk : changes === 0 ? t.noChange : t.changeCount(changes)}
        </span>
        <Icon name={shown ? "up" : "down"} className="size-4 shrink-0 self-center text-slate-400" />
      </span>
      <Strip journey={journey} catalog={catalog} />
      {!shown && <Flags journey={journey} />}
    </>
  );
}

/** The legs in a line: a walk by its minutes, a ride by the minutes waited for
 *  it, its line's badge and the minutes ridden, with a dot where a ride rests
 *  on more than a tracked vehicle */
function Strip({ journey, catalog }: { journey: Journey; catalog: Catalog }) {
  return (
    <span className="mt-1.5 flex flex-wrap items-center gap-1 text-xs text-slate-400">
      {journey.legs.map((leg, i) => {
        const note = rests(leg);
        return (
          <span key={i} className="flex items-center gap-1">
            {i > 0 && <Icon name="right" className="size-3 text-slate-600" />}
            {leg.kind === "walk" ? (
              <span title={t.walkLeg(mins(leg.arr - leg.dep))} className="flex items-center">
                <Icon name="walk" className="size-3.5" />
                {mins(leg.arr - leg.dep)}
              </span>
            ) : (
              <StripRide leg={leg} wait={waitBefore(journey, i)} catalog={catalog} />
            )}
            {note && <span className={`size-1.5 rounded-full ${note.dot}`} />}
          </span>
        );
      })}
    </span>
  );
}

/** A ride in the strip: the minutes waited for it, by a clock, then its
 *  line's badge and the minutes ridden */
function StripRide({ leg, wait, catalog }: { leg: Leg; wait: number; catalog: Catalog }) {
  const route = leg.route === undefined ? undefined : catalog.routes[leg.route];
  const ride = mins(leg.arr - leg.dep);
  return (
    <>
      {wait >= WAIT_MIN_S && (
        <span title={t.waitLeg(mins(wait))} className="flex items-center">
          <Icon name="clock" className="size-3.5" />
          {mins(wait)}
        </span>
      )}
      {route && <RouteBadge route={route} className="px-1.5 text-xs" />}
      <span title={t.rideLeg(ride)}>{ride}</span>
    </>
  );
}

/** What an unpicked card says beyond its legs, only as words: the hurry, the
 *  loudest note, and the backups */
function Flags({ journey }: { journey: Journey }) {
  const hurry = journey.hurry ? hurried(journey) : null;
  const notes = journey.legs.map(rests);
  const loudest = notes.find((n) => n === RESTS.quiet) ?? notes.find(Boolean);
  const backups = journey.rides > 0 && journey.backup > 0;
  if (!hurry && !loudest && !backups) return null;
  return (
    <span className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
      {hurry && <HurryPill hint={hurry.hint}>{hurry.text}</HurryPill>}
      {loudest && <span className={loudest.tone}>{loudest.word}</span>}
      {backups && <span className="text-emerald-300">{t.backupCount(journey.backup)}</span>}
    </span>
  );
}

/** An option caught only by hurrying: what its pill says, with the pace that
 *  catches it, and why */
function hurried(journey: Journey) {
  const kmh = plannedKmh(journey);
  return kmh === null
    ? { text: t.hurry, hint: t.hurryHint }
    : { text: t.hurryAt(t.kmh(kmh)), hint: `${t.hurryHint}. ${t.paceHint}` };
}

/** The picked card's legs, each control drawn as one, and what it leads to */
function Opened({
  journey,
  catalog,
  onStop,
  onLine,
  onBackups,
  onFollow,
}: {
  journey: Journey;
  catalog: Catalog;
  onStop: (i: number) => void;
  onLine: (i: number) => void;
  onBackups: () => void;
  onFollow: () => void;
}) {
  const hurry = journey.hurry ? hurried(journey) : null;
  return (
    <div className="space-y-0.5 border-t border-hair px-1 pt-1 pb-1">
      {hurry && (
        <div className="space-y-1 px-1 py-1">
          <HurryPill hint={hurry.hint}>{hurry.text}</HurryPill>
          <Said>{hurry.hint}</Said>
        </div>
      )}
      {journey.legs.map((leg, i) =>
        leg.kind === "walk" ? (
          <Walk key={i} journey={journey} i={i} catalog={catalog} onStop={onStop} />
        ) : (
          <Fragment key={i}>
            <Wait seconds={waitBefore(journey, i)} />
            <Ride leg={leg} catalog={catalog} onStop={onStop} onLine={onLine} />
          </Fragment>
        ),
      )}
      <div className="flex items-center gap-2 px-1 pt-1">
        {journey.rides > 0 && journey.backup > 0 && (
          <button
            onClick={onBackups}
            title={t.backupHint}
            className={`flex min-h-11 items-center gap-1 rounded-full px-3 text-sm text-emerald-300 hover:bg-white/5 ${FOCUS}`}
          >
            {t.backupCount(journey.backup)}
            <Icon name="right" className="size-4" />
          </button>
        )}
        {followable(journey) && (
          <button onClick={onFollow} title={t.followHint} className="btn min-h-11 flex-1">
            {t.follow}
          </button>
        )}
      </div>
    </div>
  );
}

function Walk({
  journey,
  i,
  catalog,
  onStop,
}: {
  journey: Journey;
  i: number;
  catalog: Catalog;
  onStop: (i: number) => void;
}) {
  const leg = journey.legs[i]!;
  const minutes = <MinutesLead icon="walk" minutes={mins(leg.arr - leg.dep)} said={t.walkLeg} />;
  if (leg.b < 0)
    return (
      <div className="flex min-h-8 items-center gap-2 px-2 text-sm text-slate-400">
        {minutes}
        {t.toDoor}
      </div>
    );
  // Consecutive walks are folded before they are sent, so a walk with a ride
  // either side is the change itself
  const change = i > 0 && i < journey.legs.length - 1;
  const name = stopName(catalog, leg.b);
  return (
    <StopRow icon={minutes} onClick={() => onStop(leg.b)}>
      <span className="text-slate-300">{change ? t.changeAt(name) : name}</span>
    </StopRow>
  );
}

/** The minutes stood at the stop before a ride, once there are any */
function Wait({ seconds }: { seconds: number }) {
  if (seconds < WAIT_MIN_S) return null;
  return (
    <div className="flex min-h-8 items-center gap-2 px-2 text-sm text-slate-400">
      <MinutesLead icon="clock" minutes={mins(seconds)} said={t.waitLeg} />
      {t.wait}
    </div>
  );
}

/** A row's lead: minutes after an icon, said in full by its title */
function MinutesLead({ icon, minutes, said }: { icon: IconName; minutes: number; said: (m: number) => string }) {
  return (
    <span title={said(minutes)} className="flex w-12 shrink-0 items-center gap-0.5 text-xs text-slate-500">
      <Icon name={icon} className="size-3.5" />
      {t.minutes(minutes)}
    </span>
  );
}

function Ride({
  leg,
  catalog,
  onStop,
  onLine,
}: {
  leg: Leg;
  catalog: Catalog;
  onStop: (i: number) => void;
  onLine: (i: number) => void;
}) {
  const route = leg.route === undefined ? undefined : catalog.routes[leg.route];
  const note = rests(leg);
  return (
    <div className="rounded-lg bg-white/[0.03] py-0.5">
      <div className="flex items-center gap-2 px-2">
        <span className="w-12 shrink-0 text-xs text-slate-300 tabular-nums">{clock(leg.dep)}</span>
        {route && (
          <button
            onClick={() => onLine(leg.route!)}
            title={t.showLine}
            className={`group -my-1 shrink-0 rounded-full py-2 ${FOCUS}`}
          >
            <span className="inline-flex h-7 items-center gap-1 rounded-full bg-raised py-0.5 pr-2 pl-0.5 ring-1 ring-white/15 group-hover:bg-white/10">
              <RouteBadge route={route} className="rounded-full px-1.5 py-0.5 text-xs" />
              <Icon name="map" className="size-3.5 text-slate-300" />
            </span>
          </button>
        )}
        <span className="text-xs text-slate-400">{t.rideLeg(mins(leg.arr - leg.dep))}</span>
        {note && <span className={`ml-auto text-xs ${note.tone}`}>{note.word}</span>}
      </div>
      {note && <div className="px-2 pb-1 pl-16"><Said>{note.why}</Said></div>}
      <StopRow
        icon={<Icon name="destination" className="size-4 w-12 shrink-0 text-slate-500" />}
        onClick={() => onStop(leg.b)}
      >
        <span className="text-slate-200">{stopName(catalog, leg.b)}</span>
      </StopRow>
    </div>
  );
}

/** A row that opens a stop's card, by its chevron */
function StopRow({ icon, onClick, children }: { icon: ReactNode; onClick: () => void; children: ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={`flex min-h-11 w-full items-center gap-2 rounded-lg px-2 text-left text-sm hover:bg-white/5 active:bg-white/10 ${FOCUS}`}
    >
      {icon}
      <span className="min-w-0 flex-1 truncate">{children}</span>
      <Icon name="right" className="size-4 shrink-0 text-slate-500" />
    </button>
  );
}

function Said({ children }: { children: ReactNode }) {
  return <p className="text-xs leading-snug text-slate-400">{children}</p>;
}
