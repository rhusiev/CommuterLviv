import { useState, type DragEvent } from "react";

export const moved = <T>(list: T[], from: number, to: number): T[] => {
  const next = [...list];
  next.splice(to, 0, ...next.splice(from, 1));
  return next;
};

/** Dragging a list into another order. The order being built lives here, so the
 * rows move under the finger while only the order the finger is let go on is
 * written out. `row(i)` is spread onto the element that is dragged. */
export function useReorder<T>(list: T[], onDone: (next: T[]) => void) {
  const [drag, setDrag] = useState<{ at: number; list: T[] } | null>(null);

  const row = (i: number) => ({
    draggable: true,
    onDragStart: () => setDrag({ at: i, list }),
    onDragOver: (e: DragEvent) => {
      e.preventDefault();
      if (!drag || drag.at === i) return;
      setDrag({ at: i, list: moved(drag.list, drag.at, i) });
    },
    onDragEnd: () => {
      if (drag) onDone(drag.list);
      setDrag(null);
    },
    "aria-grabbed": drag?.at === i,
  });

  return { shown: drag?.list ?? list, row };
}
