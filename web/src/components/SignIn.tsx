import { useEffect, useState, type FormEvent } from "react";
import { api, ApiError } from "../lib/api";
import { t } from "../lib/i18n";

/** Sign in, register, or take up an invite. Which of the three the server
 * allows is its `COMMUTERLVIV_REGISTRATION`, read from `/api/health`; an invite
 * code arrives in the link an admin sent, and this screen is the only thing
 * that ever reads it. */
export function SignIn({ code, onIn }: { code: string | null; onIn: () => void }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [remember, setRemember] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [signingUp, setSigningUp] = useState(false);
  // Until the server answers, offer the way in that every deployment accepts
  const [mode, setMode] = useState("code");

  useEffect(() => {
    api.registration().then(setMode, () => {});
  }, []);

  const joining = code !== null || signingUp;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (joining) await api.register(code ?? "", username, password, remember);
      else await api.login(username, password, remember);
      history.replaceState(null, "", "/");
      onIn();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t.wrong);
      setBusy(false);
    }
  };

  return (
    <div className="flex min-h-dvh items-center justify-center bg-slate-950 p-6">
      <form onSubmit={submit} className="w-full max-w-sm space-y-4">
        <div>
          <h1 className="text-xl font-semibold text-slate-100">{t.appName}</h1>
          <p className="mt-1 text-sm text-slate-400">
            {!joining ? t.signInHint : code !== null ? t.inviteHint : t.registerHint}
          </p>
        </div>

        <label className="block">
          <span className="text-xs uppercase tracking-wide text-slate-500">{t.username}</span>
          <input
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            // The autocomplete token is what a password manager reads first, but
            // the older heuristics look at the name, and both are free
            name="username"
            autoComplete="username"
            autoFocus
            required
            className="mt-1 w-full rounded-lg border border-slate-800 bg-slate-900 px-3 py-2 text-slate-100 outline-none focus:border-sky-600"
          />
        </label>

        <label className="block">
          <span className="text-xs uppercase tracking-wide text-slate-500">{t.password}</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            name="password"
            autoComplete={joining ? "new-password" : "current-password"}
            required
            className="mt-1 w-full rounded-lg border border-slate-800 bg-slate-900 px-3 py-2 text-slate-100 outline-none focus:border-sky-600"
          />
          {joining && <span className="mt-1 block text-xs text-slate-500">{t.passwordHint}</span>}
        </label>

        <label className="flex items-center gap-2 text-sm text-slate-300">
          <input
            type="checkbox"
            checked={remember}
            onChange={(e) => setRemember(e.target.checked)}
            className="size-4 accent-sky-600"
          />
          {t.stayIn}
        </label>

        {error && <p className="text-sm text-rose-400">{error}</p>}

        <button
          type="submit"
          disabled={busy}
          className="w-full rounded-lg bg-sky-600 py-2 font-medium text-white hover:bg-sky-500 disabled:opacity-50"
        >
          {joining ? t.createAccount : t.signIn}
        </button>

        {(joining || mode === "open") && (
          <button
            type="button"
            onClick={() => {
              if (!joining) {
                setSigningUp(true);
                return;
              }
              setSigningUp(false);
              // An invite is in the address bar, so dropping it takes a reload
              if (code !== null) {
                history.replaceState(null, "", "/");
                location.reload();
              }
            }}
            className="w-full text-sm text-slate-500 hover:text-slate-300"
          >
            {joining ? t.haveAccount : t.wantAccount}
          </button>
        )}
      </form>
    </div>
  );
}
