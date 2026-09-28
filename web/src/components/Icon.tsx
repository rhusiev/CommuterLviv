const PATHS = {
  sort: "M4 6h16M4 12h10M4 18h5",
  swap: "M7 20V4M3 8l4-4 4 4M17 4v16M13 16l4 4 4-4",
  locate: "M12 8a4 4 0 1 0 0 8 4 4 0 1 0 0-8M12 2v3M12 19v3M2 12h3M19 12h3",
  origin: "M12 7a5 5 0 1 0 0 10 5 5 0 1 0 0-10",
  destination: "M12 21s-7-6.5-7-11.5a7 7 0 0 1 14 0C19 14.5 12 21 12 21ZM12 7.5a2 2 0 1 0 0 4 2 2 0 1 0 0-4",
  clock: "M12 3a9 9 0 1 0 0 18 9 9 0 1 0 0-18M12 7v5l3 2",
  walk: "M13 3.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 1 0 0-3M9 21l3-7 3 3v4M8 12l2-4h4l2 4M11 8l1 6",
  pin: "M9.5 3h5l-.5 6.5 3 2.5v1.5H7V12l3-2.5ZM12 13.5V21",
  trash: "M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13",
  plus: "M12 5v14M5 12h14",
  check: "M5 12l5 5 9-10",
  clear: "M6 6l12 12M18 6 6 18",
} as const;

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
      <path d={PATHS[name]} />
    </svg>
  );
}
