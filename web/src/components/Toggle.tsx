/** An on/off setting: its label, and a box at the row's end */
export function Toggle(p: { label: string; on: boolean; onChange: (on: boolean) => void }) {
  return (
    <label className="flex cursor-pointer items-center justify-between gap-3 rounded-md px-2 py-1.5 text-sm text-slate-300 hover:bg-raised/70">
      {p.label}
      <input
        type="checkbox"
        checked={p.on}
        onChange={(e) => p.onChange(e.target.checked)}
        className="size-4 accent-accent"
      />
    </label>
  );
}
