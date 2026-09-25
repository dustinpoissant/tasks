---
title: add-realtime-layer-to-kempo-core
description: Build the realtime layer in kempo (CMS core) on top of kempo-server's new WebSocket transport, so socket connections map to signed-in users and kempo (CMS) extensions can register socket handlers and push to clients
repos: kempo, kempo-server
status: idea
created: 2026-09-25
owner: TBD
qa: TBD
branches: {}
prs: {}
---

# add-realtime-layer-to-kempo-core

## Description
Task 0001 added the WebSocket **transport** to kempo-server: a `WS.js` route file, framing, an origin check, a heartbeat, and a shared registry (`sockets()`, `broadcast()`) for pushing from outside the route. It deliberately stopped there. This task is the layer above it, inside kempo (CMS core): the API and database plumbing that turns a raw socket into something a kempo (CMS) extension can use.

That was follow-up #2 in 0001: channels/topics, socket-to-user mapping via the session, and a way for extensions to register socket handlers. The first consumer in mind is kempo-payments live status (the admin list/detail subscribing, and the Stripe webhook handler pushing status changes, which today only refresh on a manual Refresh or after an action).

**Needs 0001 merged and released first.** WebSockets live on branch `0001_add-websockets-to-kempo-server` and join the still-unpublished kempo-server 3.4.0. Kempo core already peers on `kempo-server >= 3.4.0`, so once 3.4.0 ships with WebSockets that range is sufficient, but the work here cannot be installed by anyone until then.

## Findings so far (verified against the code on 2026-09-25)
- **Resolved in 0001 (2026-09-25): kempo's API is served through a wildcard custom route, which upgrades used to ignore.** `app-public/.config.json` maps `"/kempo/**": "../node_modules/kempo/dist/kempo/**"`, which is how everything under `src/kempo/api/**` reaches consumers. 0001 decided (and documented) that custom and wildcard routes do **not** apply to WebSocket upgrades: only a `WS.js` in the served tree is resolved. So a `WS.js` placed at `src/kempo/api/**/WS.js` would have 404'd on the handshake in every consumer. Fixed on the 0001 branch: upgrades now resolve exact custom route, then wildcard, then the served tree, and a `..` segment is refused. Verified against the built `dist` with a wildcard mapping shaped like kempo's. **Still to confirm in a real kempo install:** that kempo's build actually emits `WS.js` into `dist/kempo/api/**` (its build copies and minifies `src/kempo/api`; not checked).
- **Kempo middleware on the handshake: found and fixed a real bug in 0001, verified against a stand-in, not against the real file.** The upgrade path used to hand middleware raw Node objects, so `middleware/kempo.js` (which reads `request.path` / `request.cookies` and calls `response.redirect()`) would have thrown on every handshake. Fixed in 0001. `tests/websocket-kempo-layout.node-test.js` in kempo-server now reproduces a kempo install, including a stand-in for the middleware and the `/kempo/**` wildcard mapping, and covers cookie auth, the origin check, the /account auth gate on a handshake, and targeted pushes from an HTTP route. **Not yet done:** running the *real* `middleware/kempo.js`. It imports kempo's database layer, so it needs a DB. Reading it, a request under `/kempo/api/**` reaches `getEnabledExtensions()` and `extensionPublicDirs()` (both DB) and then `next()`; worth confirming once there is a real install to test in.
- **`routeFiles` is not deep-merged.** kempo-server merges config shallowly for that key, so a consumer whose `.config.json` sets its own `routeFiles` silently loses `WS.js`. The stock `app-public/.config.json` does not set it, so this only affects consumers who did.
- **Session lookup already fits.** `server/utils/auth/getSession.js` takes a token, not a request, which is what the four-layer rule requires. The `WS.js` HTTP-layer file reads `request.cookies.session_token` and passes it in. The origin check from 0001 already guards the cookie-riding-along hazard.
- **Database:** `server/db/index.js` creates one `postgres-js` client from `DATABASE_URL` and merges the framework schema with the app schema. Extensions expose `db` and `schema` through `server/sdk.js`.
- **Layering rules that apply** (from AGENTS.md): anything in `server/utils/` must be HTTP-agnostic and return `[error, data]` tuples, so channel/subscription logic lives there, and the `WS.js` file is thin HTTP-layer glue.

## Acceptance Criteria
- [x] {Custom-route blocker resolved in 0001, see Findings}
- [ ] {A `WS.js` under kempo's API accepts an upgrade in a stock consumer install, authenticated by the existing session cookie, and refuses with 401 when there is none}
- [ ] {A socket is mapped to its user, so a push can target "this user" rather than a raw socket}
- [ ] {Channels/topics: a client can subscribe and unsubscribe, and server code can publish to a channel}
- [ ] {A supported API for kempo (CMS) extensions to register socket handlers and publish, exposed through `server/sdk.js`}
- [ ] {Authorization: an extension can declare who may subscribe to a channel, checked against the existing permissions system}
- [ ] {Confirm the real `middleware/kempo.js` behaves correctly on a handshake in a real install (verified against a stand-in in kempo-server's tests)}
- [ ] {Tests, docs, and a README/CHANGELOG update}

## Repos Involved
- **kempo** (core) - the realtime layer: API route(s), `server/utils/` logic, `server/sdk.js` exports, docs.
- **kempo-server** - already changed in 0001 (custom/wildcard routes for upgrades); not expected to change again for this task.

## Notes
**Open question: what "database connection infrastructure" should mean.** The request was to add "the API layers and database connection infrastructure", and that phrase is ambiguous. Candidates, none of them decided:
1. **Session lookup on connect only.** Uses the existing `db` and `getSession`; no new infrastructure. Probably not what was meant, since it needs nothing new.
2. **Persisting subscriptions or presence in Postgres**, so state survives a restart and can be inspected. Needs new tables in `server/db/schema.js` and a migration.
3. **Postgres `LISTEN`/`NOTIFY` as the cross-process bus.** 0001's registry is single-process, and the database is the one shared piece every kempo process already connects to. This would lift the "behind a load balancer, a socket is only reachable from its own process" limitation without adding Redis. It probably needs a dedicated connection rather than the shared query client, which is why it would count as infrastructure. It also raises delivery-guarantee and payload-size (NOTIFY is limited to about 8KB) questions.

Option 3 is the one that gives this task a real reason to have a database layer, so it is worth confirming at refinement, but it is a guess about intent.

**Also unresolved:** whether the realtime layer is core or its own kempo (CMS) extension (0001 left this open), and channel naming and namespacing so two extensions cannot collide.

**Known limitation inherited from 0001:** outbound backpressure is unbounded. A slow consumer queues frames in memory. Fine for low-rate status updates like the payments case, worth addressing before high-rate fan-out.
