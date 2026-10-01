/** How fast you walk on the level, in km/h: the steps offered, and what is
 *  assumed until you say, which is also the service's own */
export const WALK_KMH = { min: 0.5, max: 8, step: 0.5, usual: 4.5 } as const;

const key = "commuterlviv.walk";

export function heldSpeed(): number {
  const held = Number(localStorage.getItem(key));
  return held >= WALK_KMH.min && held <= WALK_KMH.max ? held : WALK_KMH.usual;
}

export function holdSpeed(kmh: number) {
  localStorage.setItem(key, String(kmh));
}
