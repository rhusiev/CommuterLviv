import { useState, type FormEvent } from "react";
import { api, ApiError } from "../lib/api";
import { t } from "../lib/i18n";

/** Changing the password, folded away until asked for. The service signs every
 * other device out, and keeps only this one's session, not its remember-me. */
export function PasswordForm() {
  const [open, setOpen] = useState(false);
  const [old, setOld] = useState("");
  const [next, setNext] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [done, setDone] = useState(false);

  // Folds away forgetting what was typed, so it is not there when unfolded
  const close = () => {
    setOpen(false);
    setOld("");
    setNext("");
    setError("");
  };

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      await api.password(old, next);
      close();
      setDone(true);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t.wrong);
    }
    setBusy(false);
  };

  if (!open)
    return (
      <>
        <button
          onClick={() => {
            setOpen(true);
            setDone(false);
          }}
          className="rounded-md px-2 py-1.5 text-left text-sm text-slate-300 hover:bg-raised/70"
        >
          {t.changePassword}
        </button>
        {done && <p className="px-2 text-xs text-emerald-300">{t.passwordChanged}</p>}
      </>
    );
  return (
    <form onSubmit={submit} className="flex flex-col gap-2 px-2 py-1">
      <label className="block">
        <span className="text-xs uppercase tracking-wide text-slate-500">{t.currentPassword}</span>
        <input
          type="password"
          value={old}
          onChange={(e) => setOld(e.target.value)}
          autoComplete="current-password"
          autoFocus
          required
          className="field mt-1"
        />
      </label>
      <label className="block">
        <span className="text-xs uppercase tracking-wide text-slate-500">{t.newPassword}</span>
        <input
          type="password"
          value={next}
          onChange={(e) => setNext(e.target.value)}
          autoComplete="new-password"
          required
          className="field mt-1"
        />
        <span className="mt-1 block text-xs text-slate-500">{t.passwordHint}</span>
      </label>
      {error && <p className="text-xs text-rose-400">{error}</p>}
      <div className="flex gap-2">
        <button type="submit" disabled={busy} className="btn flex-1 py-1.5 text-sm disabled:opacity-50">
          {t.changePassword}
        </button>
        <button type="button" onClick={close} disabled={busy} className="btn-quiet px-2 text-sm disabled:opacity-50">
          {t.cancel}
        </button>
      </div>
    </form>
  );
}
