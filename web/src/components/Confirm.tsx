import { useEffect, useId, useRef, useState, type ReactNode, type RefObject } from "react";
import { createPortal } from "react-dom";
import { t } from "../lib/i18n";

/** The page-wide overlay a question is asked in. Focus moves to `first` and
 *  returns where it was once answered; Escape or a click outside cancels */
function Modal({
  role,
  labelledBy,
  first,
  onCancel,
  children,
}: {
  role: "dialog" | "alertdialog";
  labelledBy: string;
  first: RefObject<HTMLElement | null>;
  onCancel: () => void;
  children: ReactNode;
}) {
  useEffect(() => {
    const was = document.activeElement;
    first.current?.focus();
    return () => {
      if (was instanceof HTMLElement) was.focus();
    };
  }, [first]);
  // To the body: a panel's backdrop blur would otherwise hold a fixed overlay inside it
  return createPortal(
    <div onClick={onCancel} className="fixed inset-0 z-50 flex cursor-default items-center justify-center bg-black/50 p-4">
      <div
        role={role}
        aria-modal
        aria-labelledby={labelledBy}
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          if (e.key === "Escape") onCancel();
        }}
        className="panel w-80 max-w-full bg-panel p-4 text-sm"
      >
        {children}
      </div>
    </div>,
    document.body,
  );
}

/** Asks before an action that cannot be taken back, with focus on Cancel */
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
  return (
    <Modal role="alertdialog" labelledBy={id} first={cancel} onCancel={onCancel}>
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
    </Modal>
  );
}

/** Asks for a line of text, the page's own `prompt()`. It answers trimmed,
 *  and only once something is typed unless `optional` */
export function Prompt({
  text,
  action,
  optional = false,
  onAnswer,
  onCancel,
}: {
  text: string;
  /** The answering button's label */
  action: string;
  optional?: boolean;
  onAnswer: (text: string) => void;
  onCancel: () => void;
}) {
  const id = useId();
  const field = useRef<HTMLInputElement>(null);
  const [value, setValue] = useState("");
  const answer = value.trim();
  const canAnswer = optional || answer !== "";
  return (
    <Modal role="dialog" labelledBy={id} first={field} onCancel={onCancel}>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (canAnswer) onAnswer(answer);
        }}
      >
        <p id={id} className="text-slate-200">
          {text}
        </p>
        <input
          ref={field}
          aria-labelledby={id}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          className="field mt-2 w-full py-1.5"
        />
        <div className="mt-3 flex justify-end gap-1">
          <button type="button" onClick={onCancel} className="btn-quiet">
            {t.cancel}
          </button>
          <button type="submit" disabled={!canAnswer} className="btn disabled:bg-raised/70 disabled:text-slate-500">
            {action}
          </button>
        </div>
      </form>
    </Modal>
  );
}
