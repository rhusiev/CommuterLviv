import { t } from "../lib/i18n";

/** The handle a reorderable row is dragged by */
export function Grip() {
  return (
    <span
      title={t.dragToOrder}
      className="cursor-grab select-none px-1 text-xs leading-none text-slate-600"
    >
      ⠿
    </span>
  );
}
