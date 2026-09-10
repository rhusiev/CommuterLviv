"""End to end checks for the live service, against a running `commuterlviv serve`.

Takes two unspent invite codes, because two of the assertions need a second one:

    python3 -m commuterlviv admin invite      # twice, keep the codes
    python3 check_live.py <code> <code2>

It registers `smoke_user` and leaves it behind, so a rerun needs a database
whose `users`, `auth_events` and `access_codes` have been truncated. Cookie
names are the unprefixed ones, so this expects COMMUTERLVIV_DEV=true - under secure
cookies they are `__Host-` prefixed and nothing here would find them.
"""

import asyncio
import json
import os
import sys

import requests
import websockets

BASE = os.environ.get("COMMUTERLVIV_CHECK_BASE", "http://127.0.0.1:8099")
ORIGIN = os.environ.get("COMMUTERLVIV_ORIGINS", "http://127.0.0.1:5173").split(",")[0]
CODE, CODE2 = sys.argv[1], sys.argv[2]
ok, bad = [], []


def check(name, cond, extra=""):
    (ok if cond else bad).append(name)
    print(("PASS " if cond else "FAIL ") + name, extra)


def csrf(s):
    return {"Origin": ORIGIN, "X-CSRF-Token": s.cookies.get("lp_csrf") or ""}


s = requests.Session()
r = s.get(BASE + "/api/me")
check("anonymous is refused", r.status_code == 401, r.text[:80])

# Both clients read this before anyone is signed in: it decides whether the
# sign-in screen offers an invite field, a sign-up button, or neither
r = s.get(BASE + "/api/health")
check("health says which registration is on",
      r.json().get("registration") in ("open", "code", "closed"), r.text[:80])

r = s.post(BASE + "/api/register", json={"username": "smoke_user", "password": "correct horse battery"},
           headers={"Origin": ORIGIN})
check("register without a code is refused", r.status_code == 400, r.text[:80])

r = s.post(BASE + "/api/register", json={"username": "smoke_user", "password": "short", "code": CODE},
           headers={"Origin": ORIGIN})
check("short password is refused", r.status_code == 400, r.text[:80])

r = s.post(BASE + "/api/register/" + "0" * len(CODE),
           json={"username": "smoke_user", "password": "correct horse battery"},
           headers={"Origin": ORIGIN})
check("a wrong code in the link is refused", r.status_code == 400, r.text[:80])

r = s.post(BASE + "/api/register/" + CODE,
           json={"username": "smoke_user", "password": "correct horse battery",
                 "remember": True},
           headers={"Origin": ORIGIN})
check("register through the invite link", r.status_code == 200, r.text[:120])
if r.status_code != 200:
    sys.exit("everything below needs the account this failed to create - spend two fresh codes")
check("session cookie set", "lp_sess" in s.cookies)
check("csrf cookie set", "lp_csrf" in s.cookies)
check("remember cookie set", "lp_remember" in s.cookies)

r = s.post(BASE + "/api/register/" + CODE2,
           json={"username": "smoke_user", "password": "correct horse battery"},
           headers={"Origin": ORIGIN})
check("duplicate username is refused", r.status_code == 400, r.text[:80])

r = s.get(BASE + "/api/me")
check("me after register", r.status_code == 200 and r.json()["username"] == "smoke_user", r.text[:120])

r = s.get(BASE + "/api/catalog")
cat = r.json()
check("catalog", r.status_code == 200 and len(cat["routes"]) > 10, str(len(cat.get("routes", []))))
tag = r.headers["ETag"]
r = s.get(BASE + "/api/catalog", headers={"If-None-Match": tag})
check("catalog 304", r.status_code == 304)

names = [x["id"] for x in cat["routes"][:3]]
r = s.post(BASE + "/api/sets", json={"name": "Work", "routes": names}, headers=csrf(s))
check("create a set", r.status_code == 201, r.text[:160])
sid = r.json().get("id") if r.status_code == 201 else None

r = s.post(BASE + "/api/sets", json={"name": "Work", "routes": names}, headers=csrf(s))
check("duplicate set name is refused", r.status_code == 400, r.text[:80])

r = s.post(BASE + "/api/sets", json={"name": "Bogus", "routes": ["definitely-not-a-route"]}, headers=csrf(s))
check("unknown route is refused", r.status_code == 400, r.text[:80])

r = s.post(BASE + "/api/sets", json={"name": "NoCsrf", "routes": names}, headers={"Origin": ORIGIN})
check("missing csrf token is refused", r.status_code == 403, r.text[:80])

r = s.post(BASE + "/api/sets", json={"name": "BadOrigin", "routes": names},
           headers={"Origin": "https://evil.example", "X-CSRF-Token": s.cookies.get("lp_csrf")})
check("foreign origin is refused", r.status_code == 403, r.text[:80])

if sid:
    r = s.put(BASE + f"/api/sets/{sid}", json={"name": "Home", "routes": names[:1]}, headers=csrf(s))
    check("rename a set", r.status_code == 200 and r.json()["name"] == "Home", r.text[:120])
    r = s.post(BASE + "/api/sets/active", json={"id": sid}, headers=csrf(s))
    check("activate a set", r.status_code == 200, r.text[:80])
r = s.post(BASE + "/api/sets/active", json={"id": "00000000-0000-0000-0000-000000000000"}, headers=csrf(s))
check("activating a foreign set 404s", r.status_code == 404, r.text[:80])

stops = ",".join(str(i) for i in range(5))
r = s.get(BASE + f"/api/arrivals?stops={stops}")
check("arrivals", r.status_code == 200 and "stops" in r.json(), r.text[:120])
# Whichever vehicle the first stop expects is one that is certainly tracked,
# so its own list should not be empty either
due = next((v for v in r.json().get("stops", {}).values() if v), None)
if due:
    r = s.get(BASE + f"/api/vehicle?veh={due[0]['veh']}")
    check("one vehicle's stops ahead",
          r.status_code == 200 and r.json()["stops"], r.text[:120])
else:
    print("SKIP one vehicle's stops ahead - nothing is due at those stops")
r = s.get(BASE + "/api/vehicle?veh=nonsense")
check("a vehicle that is not a number is refused", r.status_code == 400, r.text[:80])
r = s.get(BASE + "/api/vehicle?veh=65535")
check("an untracked vehicle is empty, not an error",
      r.status_code == 200 and r.json()["stops"] == [], r.text[:120])

# Two points a few km apart, near the centre and near Sykhiv: any planner
# worth having finds a ride between them, and the walk is long enough that it
# cannot be the only answer
r = s.get(BASE + "/api/plan?from=49.8397,24.0297&to=49.8003,23.9950")
if r.status_code == 503:
    print("SKIP journey planner - this service has no walk.npz")
else:
    got = r.json() if r.status_code == 200 else {}
    opts = got.get("options", [])
    check("a journey is planned", r.status_code == 200 and opts, r.text[:200])
    check("its legs run from the door to the door, in order",
          all(o["legs"][0]["a"] == -1 and o["legs"][-1]["b"] == -1
              and all(a["arr"] <= b["dep"] and a["b"] == b["a"]
                      for a, b in zip(o["legs"], o["legs"][1:]))
              for o in opts), str(opts)[:300])
    check("ranked by arrival",
          [o["arr"] for o in opts] == sorted(o["arr"] for o in opts),
          str([o["arr"] for o in opts]))
r = s.get(BASE + "/api/plan?from=nonsense&to=49.8,24.0")
check("a journey from nowhere is refused",
      r.status_code in (400, 503), r.text[:80])

r = s.get(BASE + "/api/status")
check("status is not readable by an ordinary account",
      r.status_code == 404, r.text[:200])


async def ws_test(cookies, expect_ok, label):
    header = "; ".join(f"{k}={v}" for k, v in cookies.items())
    try:
        async with websockets.connect(
                BASE.replace("http", "ws", 1) + "/ws",
                additional_headers={"Origin": ORIGIN, "Cookie": header}) as w:
            hello = json.loads(await asyncio.wait_for(w.recv(), 10))
            await w.send(json.dumps({"type": "routes", "routes": [0, 1, 2]}))
            frames, binary = 0, 0
            try:
                while frames < 3:
                    m = await asyncio.wait_for(w.recv(), 12)
                    frames += 1
                    binary += isinstance(m, bytes)
            except asyncio.TimeoutError:
                pass
            check(label, expect_ok and hello.get("type") == "hello",
                  f"hello={str(hello)[:80]} frames={frames} binary={binary}")
    except Exception as exc:
        check(label, not expect_ok, repr(exc)[:120])

jar = {k: v for k, v in s.cookies.items()}
asyncio.run(ws_test(jar, True, "websocket with a session"))
asyncio.run(ws_test({}, False, "websocket without a session is closed"))

remember = {"lp_remember": s.cookies["lp_remember"]}
s2 = requests.Session()
s2.cookies.update(remember)
r = s2.get(BASE + "/api/me")
check("remember-me restores a session", r.status_code == 200, r.text[:120])
rotated = [c.value for c in s2.cookies if c.name == "lp_remember"]
check("remember-me rotated", any(v != remember["lp_remember"] for v in rotated))
check("remember-me issued a session", "lp_sess" in s2.cookies)

s3 = requests.Session()
s3.cookies.update(remember)
r = s3.get(BASE + "/api/me")
check("replayed remember-me inside the grace window still works", r.status_code == 200, r.text[:80])

r = s2.post(BASE + "/api/password", json={"old": "wrong password here", "new": "another good passphrase"},
            headers=csrf(s2))
check("wrong old password is refused", r.status_code == 400, r.text[:80])
r = s2.post(BASE + "/api/password", json={"old": "correct horse battery", "new": "another good passphrase"},
            headers=csrf(s2))
check("change the password", r.status_code == 200, r.text[:120])
r = s.get(BASE + "/api/me")
check("other sessions die on a password change", r.status_code == 401, r.text[:80])

s4 = requests.Session()
r = s4.post(BASE + "/api/login", json={"username": "smoke_user", "password": "correct horse battery"},
            headers={"Origin": ORIGIN})
check("the old password no longer works", r.status_code == 401, r.text[:80])
# A 500 here rather than a 401 is what a malformed X-Forwarded-For used to
# cause: `auth_events.ip` is an `inet` column and the failed-login audit write
# is on this path, so a bad header broke every sign-in on the deployment
r = s4.post(BASE + "/api/login", json={"username": "smoke_user", "password": "correct horse battery"},
            headers={"Origin": ORIGIN, "X-Forwarded-For": "not-an-address}"})
check("a malformed forwarded address does not break login",
      r.status_code == 401, f"{r.status_code} {r.text[:80]}")
r = s4.post(BASE + "/api/login", json={"username": "smoke_user", "password": "another good passphrase"},
            headers={"Origin": ORIGIN})
check("login with the new password", r.status_code == 200, r.text[:120])
r = s4.get(BASE + "/api/me")
check("sets survive a re-login",
      r.status_code == 200 and len(r.json()["sets"]["sets"]) == 1, r.text[:160])
r = s4.post(BASE + "/api/logout", headers=csrf(s4))
check("logout", r.status_code == 200, r.text[:80])
r = s4.get(BASE + "/api/me")
check("logged out is anonymous", r.status_code == 401, r.text[:80])

s5 = requests.Session()
codes = [s5.post(BASE + "/api/login", json={"username": "smoke_user", "password": "nope nope nope"},
                 headers={"Origin": ORIGIN}).status_code for _ in range(9)]
check("login rate limit trips", 429 in codes, str(codes))

print(f"\n{len(ok)} passed, {len(bad)} failed")
for b in bad:
    print("  failed:", b)
sys.exit(1 if bad else 0)
