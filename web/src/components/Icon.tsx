const PATHS = {
  sort: "M4 6h16M4 12h10M4 18h5",
} as const;

export type IconName = keyof typeof PATHS;

/** A 24-unit stroked glyph in the text colour */
export function Icon({ name, className = "size-5" }: { name: IconName; className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={className}
      fill="none"
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
