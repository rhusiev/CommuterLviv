import type { Shown } from "../lib/places";
import { t } from "../lib/i18n";
import { Icon } from "./Icon";
import { Close } from "./Cross";

/** A place picked by name, from the bottom of the map: what it is, whether it
 * is kept, and the way there */
export function PlaceCard({
  place,
  isSaved,
  onSave,
  onGo,
  onClose,
}: {
  place: Shown;
  isSaved: boolean;
  onSave: () => void;
  onGo: () => void;
  onClose: () => void;
}) {
  const under = isSaved ? t.saved : place.where;
  return (
    <div className="panel pointer-events-auto p-3">
      <div className="flex items-start gap-2">
        <div className="min-w-0 flex-1">
          <h3 className="truncate font-medium text-slate-100">{place.name}</h3>
          {under && <p className="truncate text-xs text-slate-500">{under}</p>}
        </div>
        {/* As in the search: a saved place's star only says so */}
        {isSaved ? (
          <span className="p-1.5 text-sm text-accent">★</span>
        ) : (
          <button
            onClick={onSave}
            title={t.savePlace}
            className="rounded-control bg-raised/70 p-1.5 text-sm text-slate-400 hover:text-accent"
          >
            ☆
          </button>
        )}
        <Close onClick={onClose} />
      </div>
      <button
        onClick={onGo}
        className="mt-2 flex items-center gap-1.5 rounded-control bg-accent/15 px-2.5 py-1.5 text-sm text-accent hover:bg-accent/25"
      >
        <Icon name="destination" className="size-4" />
        {t.getHere}
      </button>
    </div>
  );
}
