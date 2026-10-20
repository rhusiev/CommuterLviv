import { t } from "../lib/i18n";

/** A ✕ that closes the card or panel it sits in */
export function Close({ onClick }: { onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      title={t.close}
      aria-label={t.close}
      className="px-1 text-slate-500 hover:text-slate-200"
    >
      ✕
    </button>
  );
}

/** A ✕ that removes the row it sits in. A glyph alone says nothing to a
 * screen reader, so `title` is required and names what goes */
export function Remove({ onClick, title }: { onClick: () => void; title: string }) {
  return (
    <button
      title={title}
      aria-label={title}
      onClick={onClick}
      className="rounded-control px-2 py-1.5 text-xs text-slate-500 transition-colors hover:bg-raised/70 hover:text-rose-300"
    >
      ✕
    </button>
  );
}
