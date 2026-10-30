import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "./api";
import { t } from "./i18n";
import type { Me, Place, RouteSet } from "./types";

/** The account signed in and what it keeps on the server - route sets, pins
 * and places - with the routes picked and the line that says what failed.
 * `linked` are the routes the address named when the page opened: they win
 * over the account's active set. */
export function useSession(linked: string[] | null) {
  /** Undefined while asking, null when signed out */
  const [me, setMe] = useState<Me | null | undefined>(undefined);
  const [picked, setPicked] = useState<Set<string>>(new Set(linked ?? []));
  const [sets, setSets] = useState<RouteSet[]>([]);
  const [active, setActive] = useState<string | null>(null);
  const [pinIds, setPinIds] = useState<string[]>([]);
  const [places, setPlaces] = useState<Place[]>([]);
  const [notice, setNotice] = useState<string | null>(null);

  const failed = useCallback((err: unknown) => {
    if (err instanceof ApiError && err.status === 401) {
      setMe(null);
      return;
    }
    setNotice(err instanceof Error ? err.message : t.noService);
  }, []);

  const load = useCallback(
    () =>
      api.me().then((who) => {
        setMe(who);
        setSets(who.sets.sets);
        setActive(who.sets.active);
        // The account's active set only decides when the link names no routes
        const set = who.sets.sets.find((s) => s.id === who.sets.active);
        if (set && linked === null) setPicked(new Set(set.routes));
        setPinIds(who.sets.pins);
        setPlaces(who.sets.places);
        setNotice(null);
      }, failed),
    [failed, linked],
  );

  useEffect(() => {
    void load();
  }, [load]);

  const signOut = async () => {
    // Signed out whether or not the request landed
    await api.logout().catch(() => undefined);
    setMe(null);
  };

  const savePins = (ids: string[]) => {
    setPinIds(ids);
    // Optimistic: a failed save comes back at the next sign-in
    void api.setPins(ids).catch(() => undefined);
  };

  const keepPlaces = (next: Place[]) => {
    setPlaces(next);
    void api.setPlaces(next).catch(() => undefined);
  };

  const togglePicked = (id: string) =>
    setPicked((was) => {
      const next = new Set(was);
      if (!next.delete(id)) next.add(id);
      return next;
    });

  const refreshSets = async () => {
    const s = await api.sets();
    setSets(s.sets);
    setActive(s.active);
  };

  const routeSets = {
    sets,
    active,
    activate: (s: RouteSet) => {
      setPicked(new Set(s.routes));
      setActive(s.id);
      void api.activateSet(s.id).catch(failed);
    },
    /** Exactly the routes of `ids` - every route, or none - which no saved
     *  set is */
    watchOnly: (ids: string[]) => {
      setPicked(new Set(ids));
      setActive(null);
      void api.activateSet(null).catch(failed);
    },
    create: async (name: string) => {
      await api.createSet(name, [...picked]);
      await refreshSets();
    },
    update: async (s: RouteSet) => {
      await api.updateSet(s.id, s.name, [...picked]);
      await refreshSets();
    },
    remove: async (s: RouteSet) => {
      await api.deleteSet(s.id);
      await refreshSets();
    },
  };

  return {
    me,
    load,
    signOut,
    failed,
    notice,
    setNotice,
    picked,
    togglePicked,
    routeSets,
    pinIds,
    /** Only shown: for pins the server already has, or is being sent */
    showPins: setPinIds,
    savePins,
    places,
    keepPlaces,
  };
}
