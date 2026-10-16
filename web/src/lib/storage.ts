/** JSON kept in local storage, which may be full, switched off, or hold what an
 *  older version wrote: a read of anything unparsable is null, and a write
 *  that fails is lost on the next reload only */
export function readJson<T>(key: string): T | null {
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

export function writeJson(key: string, value: unknown) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Lost: the next load reads what was there before
  }
}
