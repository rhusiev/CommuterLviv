import { useEffect, useId, useRef } from "react";
import { createPortal } from "react-dom";
import { t } from "../lib/i18n";

/** Asks before an action that cannot be taken back. Focus moves to Cancel and
 *  returns where it was once answered; Escape or a click outside cancels */
export function Confirm({
  text,
  action,
  onConfirm,
  onCancel,
}: {
  text: string;
  /** The confirming button's label */
  action: string;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  const id = useId();
  const cancel = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    const was = document.activeElement;
    cancel.current?.focus();
    return () => {
      if (was instanceof HTMLElement) was.focus();
    };
  }, []);
  // To the body: a panel's backdrop blur would otherwise hold a fixed overlay inside it
  return createPortal(
    <div onClick={onCancel} className="fixed inset-0 z-50 flex cursor-default items-center justify-center bg-black/50 p-4">
      <div
        role="alertdialog"
        aria-modal
        aria-labelledby={id}
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          if (e.key === "Escape") onCancel();
        }}
        className="panel w-80 max-w-full bg-panel p-4 text-sm"
      >
        <p id={id} className="text-slate-200">
          {text}
        </p>
        <div className="mt-3 flex justify-end gap-1">
          <button ref={cancel} onClick={onCancel} className="btn-quiet">
            {t.cancel}
          </button>
          <button onClick={onConfirm} className="btn">
            {action}
          </button>
        </div>
      </div>
    </div>,
    document.body,
  );
}
