import { t } from "../lib/i18n";
import { Icon, type IconName } from "./Icon";

/** How much a banner matters: a failure, news, or a warning about what is shown */
export type Tone = "error" | "info" | "warn";

const TEXT: Record<Tone, string> = {
  error: "text-rose-200",
  info: "text-sky-200",
  warn: "text-amber-200",
};

const MARK: Record<Tone, string> = {
  error: "text-rose-400",
  info: "text-sky-400",
  warn: "text-amber-400",
};

const CLOSE: Record<Tone, string> = {
  error: "text-rose-400 hover:text-rose-200",
  info: "text-sky-400 hover:text-sky-200",
  warn: "text-amber-400 hover:text-amber-200",
};

const ICON: Record<Tone, IconName> = {
  error: "warning",
  info: "info",
  warn: "warning",
};

/** A notice across the top of the map, until `onClose`: one line of `text`,
 * and under it, when given, the `detail` that explains it */
export function Banner({
  tone,
  text,
  detail,
  icon = ICON[tone],
  onClose,
}: {
  tone: Tone;
  text: string;
  detail?: string;
  icon?: IconName;
  onClose: () => void;
}) {
  return (
    <div
      role={tone === "info" ? "status" : "alert"}
      className="panel pointer-events-auto flex w-full max-w-md items-start gap-3 py-3 pl-4 pr-2 text-sm"
    >
      <span className={`mt-px ${MARK[tone]}`}>
        <Icon name={icon} />
      </span>
      <div className="min-w-0 flex-1 py-0.5">
        <p className={`font-medium ${TEXT[tone]}`}>{text}</p>
        {detail && <p className="mt-0.5 text-slate-300">{detail}</p>}
      </div>
      <button
        onClick={onClose}
        aria-label={t.close}
        title={t.close}
        className={`grid size-7 shrink-0 place-items-center rounded-full ${CLOSE[tone]}`}
      >
        ✕
      </button>
    </div>
  );
}
