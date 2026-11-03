type Part = { d: string; dash?: string };

/** Also drawn on the map's canvas, for a low-floor vehicle */
export const PATHS_WHEELCHAIR =
  "M11 3.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 1 0 0-3M11 8v6h5l2.5 5M11 11h5M8 10.5a5.5 5.5 0 1 0 7 7.5";

const RING = (r: number) => `M12 ${12 - r}a${r} ${r} 0 1 0 0 ${2 * r}a${r} ${r} 0 1 0 0 ${-2 * r}`;

const PATHS = {
  menu: "M4 7h16M4 12h16M4 17h16",
  wheelchair: PATHS_WHEELCHAIR,
  account: "M12 4.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 1 0 0-7M5 20c1.2-3.4 4-5 7-5s5.8 1.6 7 5",
  layers: "M12 3 3 8l9 5 9-5-9-5ZM3 13l9 5 9-5",
  follow: [
    { d: `${RING(4)}M12 1v3M12 20v3M1 12h3M20 12h3` },
    { d: RING(8.5), dash: "3 3" },
  ],
  sort: "M4 6h16M4 12h10M4 18h5",
  swap: "M7 20V4M3 8l4-4 4 4M17 4v16M13 16l4 4 4-4",
  locate: `${RING(4)}M12 2v3M12 19v3M2 12h3M19 12h3`,
  origin: RING(5),
  destination: "M12 21s-7-6.5-7-11.5a7 7 0 0 1 14 0C19 14.5 12 21 12 21ZM12 7.5a2 2 0 1 0 0 4 2 2 0 1 0 0-4",
  clock: `${RING(9)}M12 7v5l3 2`,
  run: "M15 3a1.5 1.5 0 1 0 0 3 1.5 1.5 0 1 0 0-3M5 10l3-3h4l2 3 3 1M12 7l-2 6 3 3-1 5M10 13l-2 3H4",
  walk: "M13 3.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 1 0 0-3M9 21l3-7 3 3v4M8 12l2-4h4l2 4M11 8l1 6",
  pin: "M9.5 3h5l-.5 6.5 3 2.5v1.5H7V12l3-2.5ZM12 13.5V21",
  trash: "M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13",
  plus: "M12 5v14M5 12h14",
  minus: "M5 12h14",
  more: "M12 5h.01M12 12h.01M12 19h.01",
  check: "M5 12l5 5 9-10",
  clear: "M6 6l12 12M18 6 6 18",
  search: "M10.5 4a6.5 6.5 0 1 0 0 13 6.5 6.5 0 1 0 0-13M15.5 15.5 20 20",
  map: "M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2ZM9 4v14M15 6v14",
  info: `${RING(9)}M12 11v5M12 8v.01`,
  warning: "M12 3.5 2.5 20h19L12 3.5ZM12 10v4.5M12 17.5v.01",
  siren: "M7 17v-5a5 5 0 0 1 10 0v5M4.5 17h15v3.5h-15ZM12 2v2M4.5 5.5 6 7M19.5 5.5 18 7M12 10v3",
  down: "M6 9l6 6 6-6",
  up: "M6 15l6-6 6 6",
  right: "M9 6l6 6-6 6",
  left: "M15 6l-6 6 6 6",
} satisfies Record<string, string | readonly Part[]>;

const parts = (v: string | readonly Part[]) => (typeof v === "string" ? [{ d: v }] : v);

export type IconName = keyof typeof PATHS;

/** A 24-unit stroked glyph in the text colour; `filled` also fills it */
export function Icon({
  name,
  className = "size-5",
  filled = false,
}: {
  name: IconName;
  className?: string;
  filled?: boolean;
}) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={className}
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      {parts(PATHS[name]).map((p) => (
        <path key={p.d} d={p.d} strokeDasharray={p.dash} />
      ))}
    </svg>
  );
}
