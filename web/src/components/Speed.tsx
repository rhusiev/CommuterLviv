import { t } from "../lib/i18n";
import { WALK_KMH } from "../lib/walking";
import { Icon } from "./Icon";

/** A walking speed, a step at a time */
export function Speed({ kmh, onKmh }: { kmh: number; onKmh: (kmh: number) => void }) {
  const { min, max, step } = WALK_KMH;
  return (
    <span className="flex items-center gap-1">
      <button onClick={() => onKmh(kmh - step)} disabled={kmh <= min} title={t.slower} className="btn-quiet px-2 disabled:opacity-40">
        <Icon name="minus" className="size-4" />
      </button>
      <span className="w-16 text-center text-sm tabular-nums">{t.kmh(kmh)}</span>
      <button onClick={() => onKmh(kmh + step)} disabled={kmh >= max} title={t.faster} className="btn-quiet px-2 disabled:opacity-40">
        <Icon name="plus" className="size-4" />
      </button>
    </span>
  );
}
