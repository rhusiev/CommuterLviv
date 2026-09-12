import { lang, setLang, t } from "../lib/i18n";

/** Everything that belongs to the account rather than to the map. Signing out
 * sits below a rule, so it is never the click next to anything else. */

type Props = {
  username: string;
  onOut: () => void;
};

export function AccountMenu(p: Props) {
  return (
    <div className="flex flex-col gap-1">
      <p className="truncate px-2 py-1 text-sm font-medium text-slate-200">{p.username}</p>
      <h2 className="mt-1 px-2 text-xs uppercase tracking-wide text-slate-500">
        {t.language}
      </h2>
      {(["uk", "en"] as const).map((l) => (
        <button
          key={l}
          onClick={() => setLang(l)}
          className={`rounded-md px-2 py-1.5 text-left text-sm ${
            l === lang ? "bg-accent/15 text-accent" : "text-slate-300 hover:bg-raised/70"
          }`}
        >
          {l === "uk" ? "Українська" : "English"}
        </button>
      ))}
      <hr className="my-1 border-hair" />
      <button
        onClick={p.onOut}
        className="rounded-md px-2 py-1.5 text-left text-sm text-rose-300 hover:bg-raised/70"
      >
        {t.signOut}
      </button>
    </div>
  );
}
