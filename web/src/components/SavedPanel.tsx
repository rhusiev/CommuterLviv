import { useState, type ComponentProps } from "react";
import { t } from "../lib/i18n";
import { dropped, renamed } from "../lib/places";
import { useReorder } from "../lib/reorder";
import type { Place } from "../lib/types";
import { Remove } from "./Cross";
import { Grip } from "./Grip";

/** The places kept by name, in the order the account chose; a row is dragged
 * by its grip to change it. A place is renamed by writing the whole list with
 * the old name gone and the new one in its position, because the name is what
 * identifies it server-side. */

export function SavedPanel({
  places,
  onPlaces,
  onPlace,
}: {
  places: Place[];
  onPlaces: (next: Place[]) => void;
  onPlace: (place: Place) => void;
}) {
  const kept = useReorder(places, onPlaces);
  if (places.length === 0) return <p className="text-sm text-slate-500">{t.nothingSaved}</p>;
  return (
    <ul className="space-y-1">
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
      <Remove title={t.deletePlace} onClick={onForget} />
    </li>
  );
}
