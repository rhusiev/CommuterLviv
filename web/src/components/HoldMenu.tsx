import { useState } from "react";
import { t } from "../lib/i18n";

/** Where the map was held: the point, and where on the page to open beside it */
export type Held = { lat: number; lon: number; x: number; y: number };

/** The menu's width in CSS pixels, so it is kept on the page near an edge */
const WIDTH_PX = 240;
/** About its height with the name field and its warning open, for the same */
const HEIGHT_PX = 240;

/** What a long press or a right click on the map offers for that point. Saving
 * asks for the name in the menu itself, and says so before it replaces a place
 * of that name elsewhere. */
export function HoldMenu({
  at,
  label,
  isTaken,
  onSave,
  onTo,
  onFrom,
  onNear,
  onClose,
}: {
  at: Held;
  /** What to call the point, in the menu's heading */
  label: string;
  isTaken: (name: string) => boolean;
  onSave: (name: string) => void;
  onTo: () => void;
  onFrom: () => void;
  onNear: () => void;
  onClose: () => void;
}) {
  const [naming, setNaming] = useState(false);
  const [name, setName] = useState("");
  const clash = isTaken(name);
  const left = Math.max(0, Math.min(at.x, window.innerWidth - WIDTH_PX));
  const top = Math.max(0, Math.min(at.y, window.innerHeight - HEIGHT_PX));
  const save = () => {
    if (name.trim()) onSave(name.trim());
  };
  const item = (label: string, act: () => void) => (
    <button
      onClick={act}
      className="block w-full rounded-control px-2.5 py-2 text-left text-sm text-slate-300 hover:bg-raised hover:text-slate-100"
    >
      {label}
    </button>
  );
  return (
    <>
      <button
        aria-hidden
        tabIndex={-1}
        onClick={onClose}
        onContextMenu={(e) => {
          e.preventDefault();
          onClose();
        }}
        className="fixed inset-0 z-40 cursor-default"
      />
      <div
        role="dialog"
        aria-label={t.thisPlace}
        style={{ left, top, width: WIDTH_PX }}
        className="panel fixed z-40 bg-panel p-1.5"
        onKeyDown={(e) => {
          if (e.key === "Escape") onClose();
        }}
      >
        <p className="px-2.5 pb-1 pt-0.5 text-xs text-slate-500">
          {label}
        </p>
        {naming ? (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              save();
            }}
            className="flex flex-col gap-1.5 p-1"
          >
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t.namePlace}
              aria-label={t.namePlace}
              autoFocus
              aria-invalid={clash}
              className="field w-full py-1.5"
            />
            {clash && <p className="px-1 text-xs text-rose-300">{t.placeTaken}</p>}
            <div className="flex justify-end gap-1">
              <button type="button" onClick={onClose} className="btn-quiet px-2">
                {t.cancel}
              </button>
              <button type="submit" disabled={!name.trim()} className="btn px-3 disabled:bg-raised/70 disabled:text-slate-500">
                {clash ? t.replace : t.save}
              </button>
            </div>
          </form>
        ) : (
          <>
            {item(t.savePlaceAs, () => setNaming(true))}
            {item(t.toHere, onTo)}
            {item(t.fromHere, onFrom)}
            {item(t.nearHere, onNear)}
          </>
        )}
      </div>
    </>
  );
}
