import { THEMES, type Theme } from "../lib/theme";
import { t } from "../lib/i18n";

/** Everything that changes what the map draws, and nothing else: the overlays
 * as switches, the basemap as a choice. The rule for what belongs here is that
 * touching it changes the map behind the panel while the panel is still open. */

type Props = {
  lines: boolean;
  onLines: (on: boolean) => void;
  traffic: boolean;
  onTraffic: (on: boolean) => void;
  theme: Theme;
  onTheme: (theme: Theme) => void;
};

function Toggle(p: { label: string; on: boolean; onChange: (on: boolean) => void }) {
  return (
    <label className="flex cursor-pointer items-center justify-between gap-3 rounded-md px-2 py-1.5 text-sm text-slate-300 hover:bg-raised/70">
      {p.label}
      <input
        type="checkbox"
        checked={p.on}
        onChange={(e) => p.onChange(e.target.checked)}
        className="size-4 accent-accent"
      />
    </label>
  );
}

export function LayersPanel(p: Props) {
  return (
    <div className="flex flex-col gap-1">
      <Toggle label={t.everyRoute} on={p.lines} onChange={p.onLines} />
      <Toggle label={t.traffic} on={p.traffic} onChange={p.onTraffic} />
      <h2 className="mt-2 px-2 text-xs uppercase tracking-wide text-slate-500">
        {t.basemap}
      </h2>
      {THEMES.map((m) => (
        <button
          key={m.id}
          onClick={() => p.onTheme(m)}
          className={`rounded-md px-2 py-1.5 text-left text-sm ${
            m.id === p.theme.id
              ? "bg-accent/15 text-accent"
              : "text-slate-300 hover:bg-raised/70"
          }`}
        >
          {m.name}
        </button>
      ))}
    </div>
  );
}
