/** How fast you walk on the level, in km/h: the steps offered, and what is
 *  assumed until you say, which is also the service's own */
export const WALK_KMH = { min: 0.5, max: 8, step: 0.5, usual: 4.5 } as const;

/** How fast you would walk to catch a bus, in km/h: up to a brisk run, which
 *  is also the service's limit. Off until you say */
export const HURRY_KMH = { min: WALK_KMH.min, max: 12, step: WALK_KMH.step } as const;

const key = "commuterlviv.walk";
const hurryKey = "commuterlviv.hurry";

export function heldSpeed(): number {
  const held = Number(localStorage.getItem(key));
  return held >= WALK_KMH.min && held <= WALK_KMH.max ? held : WALK_KMH.usual;
}

export function holdSpeed(kmh: number) {
  localStorage.setItem(key, String(kmh));
}

/** The hurry pace kept, or null when it is off */
export function heldHurry(): number | null {
  const raw = localStorage.getItem(hurryKey);
  const held = Number(raw);
  return raw && held >= HURRY_KMH.min && held <= HURRY_KMH.max ? held : null;
}

export function holdHurry(kmh: number | null) {
  if (kmh === null) localStorage.removeItem(hurryKey);
  else localStorage.setItem(hurryKey, String(kmh));
}
