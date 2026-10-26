import type { ReactNode } from "react";
import { Icon, type IconName } from "./Icon";

/** A round button that opens a panel beneath it; a click anywhere else closes
 * it. `lit` marks the button while something it governs is on. */
export function Menu({
  icon,
  label,
  open,
  lit = open,
  onToggle,
  children,
}: {
  icon: IconName;
  label: string;
  open: boolean;
  lit?: boolean;
  onToggle: (open: boolean) => void;
  children: ReactNode;
}) {
  return (
    <>
      <button
        onClick={() => onToggle(!open)}
        title={label}
        aria-label={label}
        className={`fab ${lit ? "text-accent" : "text-slate-300 hover:text-slate-100"}`}
      >
        <Icon name={icon} />
      </button>
      {open && (
        <>
          <button
            aria-hidden
            tabIndex={-1}
            onClick={() => onToggle(false)}
            className="fixed inset-0 cursor-default"
          />
          {/* Opaque: it opens over the map controls, which showed through */}
          <div className="panel absolute right-0 top-12 w-52 bg-panel p-2">{children}</div>
        </>
      )}
    </>
  );
}
