import { useMemo, useRef, useState } from "react";
import type { Origin, Point } from "../components/JourneyPanel";
import { clock } from "./eta";
import { t } from "./i18n";
import { hereOnce, ONE_FIX, type NoFix } from "./position";

const MS_PER_S = 1000;

/** The journey planner's two ends and how they are being set. Kept above the
 * planner's panel, which a change of tab unmounts. `shown` is whether the
 * planner is open, the only time its ends are marked on the map. */
export function usePlanner(shown: boolean, onNoFix: (why: NoFix) => void) {
  const [from, setFrom] = useState<Origin | null>(null);
  /** Times got on board, so a fix asked for before it does not move the start */
  const boarded = useRef(0);
  const [to, setTo] = useState<Point | null>(null);
  /** The planner is to search as soon as both ends are set */
  const [ask, setAsk] = useState(false);
  const [picking, setPicking] = useState<"from" | "to" | null>(null);

  /** Asked separately from the map's own locate button, so a refusal here does
   * not turn the map's dot off */
  const hereFor = (which: "from" | "to") => {
    const asked = boarded.current;
    if (!navigator.geolocation) return;
    hereOnce(ONE_FIX).then((pos) => {
      // Named with the time of the fix: the end stays where it was taken, and
      // "where I am" read as if it moved along
      const name = t.hereAt(clock(pos.timestamp / MS_PER_S));
      const at = { lat: pos.coords.latitude, lon: pos.coords.longitude, name };
      // A fix asked for before getting on board is no longer the start
      if (which === "to") setTo(at);
      else if (asked === boarded.current) setFrom(at);
    }, onNoFix);
  };

  const board = (on: Origin) => {
    boarded.current += 1;
    setFrom(on);
  };

  /** On board lasts only while planning: the vehicle goes on without the planner */
  const leave = () => setFrom((was) => (was && "veh" in was ? null : was));

  const setEnd = (which: "from" | "to", at: Point) =>
    which === "from" ? setFrom(at) : setTo(at);

  const swap = () => {
    if (from && "veh" in from) return;
    setFrom(to);
    setTo(from);
  };

  /** The end being picked, at a point tapped on the map */
  const pickAt = (lat: number, lon: number) => {
    if (picking !== null) setEnd(picking, { lat, lon });
    setPicking(null);
  };

  const marks = useMemo(() => {
    const out: { lat: number; lon: number; label: string }[] = [];
    if (!shown) return out;
    if (from && !("veh" in from)) out.push({ ...from, label: "A" });
    if (to) out.push({ ...to, label: "B" });
    return out;
  }, [shown, from, to]);

  return {
    from,
    to,
    setFrom,
    setTo,
    setEnd,
    swap,
    board,
    leave,
    hereFor,
    ask,
    setAsk,
    picking,
    setPicking,
    pickAt,
    marks,
  };
}
