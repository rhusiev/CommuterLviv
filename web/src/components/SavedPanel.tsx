import { useState, type ComponentProps } from "react";
import { t } from "../lib/i18n";
import { dropped, renamed } from "../lib/places";
import { useReorder } from "../lib/reorder";
import type { Catalog, Place } from "../lib/types";

/** Everything the account has kept: places by name, stops by id. Both lists are
 * in the order the account chose, and a row is dragged by its grip to change it.
 * A place is renamed by writing the whole list with the old name gone and the new
 * one in its position, because the name is what identifies it server-side. A
 * pinned stop has no name of its own - it is the catalog's - so it is only
 * shown, unpinned, or opened. */

export function SavedPanel({
  catalog,
  places,
  onPlaces,
  pins,
  onPins,
  onPlace,
  onStop,
}: {
  catalog: Catalog;
  places: Place[];
  onPlaces: (next: Place[]) => void;
  pins: number[];
  onPins: (next: number[]) => void;
  onPlace: (place: Place) => void;
  onStop: (stop: number) => void;
}) {
  const kept = useReorder(places, onPlaces);
  const pinned = useReorder(pins, onPins);
  const empty = places.length === 0 && pins.length === 0;
  return (
    <div className="flex h-full flex-col gap-3 overflow-y-auto">
      {empty && <p className="text-sm text-slate-500">{t.nothingSaved}</p>}

      {places.length > 0 && (
        <section>
          <h2 className="text-xs uppercase tracking-wide text-slate-500">{t.places}</h2>
          <ul className="mt-2 space-y-1">
            {kept.shown.map((p, i) => (
              <PlaceRow
                key={p.name}
                place={p}
                drag={kept.row(i)}
                onShow={() => onPlace(p)}
                onRename={(name) => onPlaces(renamed(places, p, name))}
                onForget={() => onPlaces(dropped(places, p.name))}
              />
            ))}
          </ul>
        </section>
      )}

      {pins.length > 0 && (
        <section>
          <h2 className="text-xs uppercase tracking-wide text-slate-500">{t.pinnedStops}</h2>
          <ul className="mt-2 space-y-1">
            {pinned.shown.map((i, at) => (
              <li
                key={catalog.stops[i]?.id ?? i}
                {...pinned.row(at)}
                className="flex items-center gap-1"
              >
                <Grip />
                <button
                  onClick={() => onStop(i)}
                  title={t.showOnMap}
                  className="min-w-0 flex-1 truncate rounded-md px-2 py-1.5 text-left text-sm text-slate-300 hover:bg-raised/70"
                >
                  {catalog.stops[i]?.name ?? ""}
                </button>
                <button
                  onClick={() => onPins(pins.filter((p) => p !== i))}
                  className="rounded-control px-2 py-1.5 text-xs text-slate-500 transition-colors hover:bg-raised/70 hover:text-rose-300"
                >
                  ✕
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}

function Grip() {
  return (
    <span
      title={t.dragToOrder}
      className="cursor-grab select-none px-1 text-xs leading-none text-slate-600"
    >
      ⠿
    </span>
  );
}

function PlaceRow({
  place,
  drag,
  onShow,
  onRename,
  onForget,
}: {
  place: Place;
  drag: ComponentProps<"li">;
  onShow: () => void;
  onRename: (name: string) => void;
  onForget: () => void;
}) {
  const [name, setName] = useState<string | null>(null);

  if (name !== null)
    return (
      <li>
        <form
          className="flex gap-1"
          onSubmit={(e) => {
            e.preventDefault();
            if (name.trim()) onRename(name.trim());
            setName(null);
          }}
        >
          <input
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => e.key === "Escape" && setName(null)}
            className="field min-w-0 flex-1 py-1.5"
          />
          <button className="btn-quiet px-3 py-0" title={t.keepName}>
            {t.save}
          </button>
        </form>
      </li>
    );

  return (
    <li {...drag} className="flex items-center gap-1">
      <Grip />
      <button
        onClick={onShow}
        title={t.showOnMap}
        className="min-w-0 flex-1 truncate rounded-md px-2 py-1.5 text-left text-sm text-slate-300 hover:bg-raised/70"
      >
        {place.name}
      </button>
      <button
        onClick={() => setName(place.name)}
        className="rounded-control px-2 py-1.5 text-xs text-slate-500 transition-colors hover:bg-raised/70 hover:text-slate-200"
      >
        {t.rename}
      </button>
      <button
        onClick={onForget}
        className="rounded-control px-2 py-1.5 text-xs text-slate-500 transition-colors hover:bg-raised/70 hover:text-rose-300"
      >
        ✕
      </button>
    </li>
  );
}
