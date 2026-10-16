/** How much a banner matters: a failure, news, or a warning about what is shown */
export type Tone = "error" | "info" | "warn";

const TEXT: Record<Tone, string> = {
  error: "text-rose-200",
  info: "text-sky-200",
  warn: "text-amber-200",
};

const CLOSE: Record<Tone, string> = {
  error: "text-rose-400 hover:text-rose-200",
  info: "text-sky-400 hover:text-sky-200",
  warn: "text-amber-400 hover:text-amber-200",
};

/** One line across the top of the map, until `onClose` */
export function Banner({ tone, text, onClose }: { tone: Tone; text: string; onClose: () => void }) {
  return (
    <p className={`panel flex items-center gap-2 px-3 py-2 text-sm ${TEXT[tone]}`}>
      {text}
      <button onClick={onClose} className={CLOSE[tone]}>
        ✕
      </button>
    </p>
  );
}
