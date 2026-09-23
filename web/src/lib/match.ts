/** Stop names matched the way people type them: words in any order, each a
 * prefix of some word of the name, one slip allowed in a word of four letters
 * or more. "шевч пл" finds "Площа Шевченка", "стрийска" finds "Стрийська". */

const WORD = /[\p{L}\p{N}]+/gu;

/** Case, accents and apostrophes gone, so й matches и and ʼ is not typed */
export const fold = (s: string) =>
  s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ'ʼ’]/g, "");

export const words = (s: string) => fold(s).match(WORD) ?? [];

/** Fewest edits turning `q` into some prefix of `w` */
function prefixEdits(q: string, w: string): number {
  let row = Array.from({ length: w.length + 1 }, (_, j) => j);
  for (let i = 1; i <= q.length; i++) {
    const next = [i];
    for (let j = 1; j <= w.length; j++) {
      next[j] = Math.min(row[j]! + 1, next[j - 1]! + 1, row[j - 1]! + (q[i - 1] === w[j - 1] ? 0 : 1));
    }
    row = next;
  }
  return Math.min(...row);
}

function wordScore(q: string, name: string[]): number {
  let best = 0;
  for (const w of name) {
    if (w.startsWith(q)) return 3;
    if (q.length >= 3 && w.includes(q)) best = Math.max(best, 2);
    else if (q.length >= 4 && best < 1 && prefixEdits(q, w) <= 1) best = 1;
  }
  return best;
}

/** How well a folded name answers the query's words; 0 is not at all */
export function score(query: string[], name: string[]): number {
  let total = 0;
  for (const q of query) {
    const s = wordScore(q, name);
    if (s === 0) return 0;
    total += s;
  }
  return total;
}
