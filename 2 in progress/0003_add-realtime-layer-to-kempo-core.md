---
title: add-realtime-layer-to-kempo-core
description: Build the realtime layer in kempo (CMS core) on kempo-server's WebSocket transport - authenticated sockets, channels, a Postgres LISTEN/NOTIFY bus across processes, persisted messages with replay, a browser client, and an admin connection view - so kempo (CMS) extensions can push to clients
repos: kempo, kempo-server
status: in progress
created: 2026-09-25
owner: Dustin
qa: Dustin
branches:
  kempo: 0003_add-realtime-layer-to-kempo-core
  kempo-server: 0003_add-realtime-layer-to-kempo-core
prs: {}
---

# add-realtime-layer-to-kempo-core

## Description
kempo-server 3.4.0 (task 0001) added the WebSocket **transport**: a `WS.js` route file, framing, an origin check, a heartbeat, and an in-process registry (`sockets()`, `broadcast()`). It deliberately stopped there. This task is the layer above it, inside kempo (CMS core): the API and database plumbing that turns a raw socket into something a kempo (CMS) extension can use.

An extension author should be able to write, without touching sockets:

```javascript
import { realtime } from 'kempo/server/sdk.js';

realtime.registerChannel({ name: 'kempo-payments:status', persist: true, authorize: ({ user }) => user.canSeePayments });
// ...later, in a Stripe webhook handler:
await realtime.publish({ channel: 'kempo-payments:status', data: { id, status: 'paid' } });
```

and have every subscribed browser, on any kempo process, receive it, including a browser that briefly lost its connection.

The first intended consumer is kempo-payments live status (its admin list and detail pages only update on a manual Refresh today). That consumer is a separate task; this one builds the layer it needs.

## Design decisions
**Decided by the owner (2026-09-25):**
1. **Lives in kempo core**, not a separate extension.
2. **Postgres `LISTEN`/`NOTIFY` is the cross-process bus, and messages are also persisted for replay.** Together these are the standard outbox pattern: a publish inserts a row into a table and `NOTIFY`s; other processes learn about it from the notification and read the row. `NOTIFY` alone keeps nothing, so it could not support replay by itself, and its payload is limited to about 8KB; persisting removes the second limit for persisted channels. The cost is that this task now owns both a bus and a table.
3. **v1 includes all four:** the server SDK, a browser client, missed-message replay, and an admin connection view.

**Defaults chosen during refinement (please veto any you disagree with):**
- **Channel names are `<extension-name>:<channel>`, with the prefix enforced** at registration, so two extensions cannot collide. Core's own channels use `kempo:`. Each user also has an implicit `user:<id>` channel for "send to this person".
- **Default deny.** A channel must be registered with an `authorize` check before anyone can subscribe. The check runs on subscribe, against the existing permissions system.
- **Persistence is opt-in per channel** (`persist: true`), not for every publish, so ephemeral traffic does not write a row. Retention is per channel, default 24 hours.
- **Clients may not publish to arbitrary channels.** *(Amended 2026-09-25: a client can now send a message to a channel it is subscribed to, but only a handler the channel's owner declared receives it. See the extension surface below.)*
- **Owner and QA are Dustin**, matching task 0001.

## Architecture
Follows the four-layer rule in AGENTS.md: `server/utils/` is HTTP-agnostic and returns `[error, data]` tuples; the HTTP layer only extracts data and calls it.
- **HTTP layer:** `src/kempo/api/realtime/WS.js`, served at `/kempo/api/realtime`. Thin: reads `request.cookies.session_token`, calls a util, wires socket events to utils.
- **Utils:** `server/utils/realtime/` (register/subscribe/unsubscribe/publish, the bus, replay, pruning). Plain-data arguments, testable with no mocking.
- **Schema:** a `realtimeMessage` table in `server/db/schema.js` (monotonic `id`, `channel`, `data` jsonb, `createdAt`, index on `(channel, id)`), added by a real migration (`drizzle-kit generate`).
- **Bus:** its own module holding a **dedicated** listening connection, separate from the pooled query client in `server/db/index.js`.
- **SDK:** exported through `server/sdk.js`.
- **Browser client:** `src/kempo/realtime.js`, served at `/kempo/realtime.js` next to the existing `fetch.js` and `sdk.js`.
- **Admin:** `src/admin/realtime/` page plus an entry in `src/admin/nav.fragment.html`, gated by a new `system:realtime:read` permission seeded where the other `system:*` permissions are (`scripts/init-db.js`).

**Wire protocol (draft, to be finalized in implementation).** JSON frames. Client to server: `{type:'subscribe', channel, since?}`, `{type:'unsubscribe', channel}`. Server to client: `{type:'subscribed', channel}`, `{type:'message', channel, id?, data}`, `{type:'gap', channel}`, `{type:'error', channel?, code, msg}`.

## Acceptance Criteria
**Transport and auth**
- [x] `WS.js` under `src/kempo/api/realtime/` accepts an upgrade in a stock consumer install through the `/kempo/**` wildcard mapping (kempo-server 3.4.0 or later), refuses with 401 when there is no valid session, and inherits kempo-server's origin check.
- [x] Verified with kempo's **real** `middleware/kempo.js` in the chain, in a real browser (Chrome) and in an automated test that runs a real kempo-server process. Done against a separate kempo-server instance on the kempo test database, **not kempo-demo**: kempo-demo is a shared server on the demo's real data, and testing there would have meant changing its schema and restarting a server other sessions may be using.
- [x] A socket is tied to its user, and server code can publish to a user's `user:<id>` channel.
- [x] A socket is closed within a bounded time after its session is invalidated (logout, expiry, password change). A long-lived socket must not outlive the session that authenticated it.

**Channels and SDK**
- [x] `registerChannel({ name, authorize, persist, retention })` enforces the extension-name prefix, rejects a collision with an error tuple, and is exported from `server/sdk.js`.
- [x] Subscribe and unsubscribe work over the socket. An unauthorized or unregistered channel gets an error frame and the connection stays open.
- [x] `publish({ channel, data })` can be called from any server code (an HTTP route, a webhook handler, a hook) and reaches subscribers held by this process and by other processes.
- [x] Every util follows the AGENTS.md rules: no HTTP objects, error tuples, plain-data arguments.

**Cross-process bus**
- [x] The listening connection is dedicated, not taken from the query pool, and survives a dropped database connection: it reconnects, re-listens, and logs rather than crashing the process.
- [x] A test with two kempo server instances on one database shows a publish in one reaching a subscriber connected to the other.
- [x] A non-persisted message over the `NOTIFY` size limit returns a clear error tuple instead of failing silently. A persisted message sends only its id over `NOTIFY` and the receiver reads the row.

**Persistence and replay**
- [x] The `realtimeMessage` table and its migration exist. Persistence is opt-in per channel and each channel has its own ordering.
- [x] Subscribing with `since: <id>` delivers the missed persisted messages in order before live ones, with **no gap and no duplicate at the boundary** between backlog and live delivery.
- [x] Rows older than the channel's retention are pruned. A client asking for a `since` older than what remains gets a `gap` frame, so it knows to refetch fully instead of silently missing messages.

**Browser client**
- [x] `/kempo/realtime.js` connects, subscribes, and reconnects automatically with backoff, resubscribing with the last id it saw. Close code 1001 (server restarting) reconnects promptly.
- [x] It does not retry forever on an auth failure (401 or a session-invalidated close), and reports connection state to the caller.
- [x] Verified in a real browser by stopping and restarting the server and by dropping and restoring the database connection.

**Admin view**
- [x] `/admin/realtime`, gated by `system:realtime:read`, lists this process's connections (user, path, channels, connected since, last activity) and per-channel counts, and says plainly that it shows only this process.
- [x] Built with kempo-css utilities and `<k-icon>`, no custom CSS or unicode icons (AGENTS.md). Any new icon goes in kempo core's `src/kempo/icons/`, in Material Symbols style.

**Quality and delivery**
- [x] Tests cover: auth, prefix enforcement, authorization, cross-process delivery, the replay boundary race, the `gap` case, retention pruning, reconnect, and session-invalidation close.
- [x] **The DB-backed tests actually run.** kempo's DB suites report `(SKIPPED)` and count as passing when no database is reachable, so confirm with `npx kempo-test -l normal | grep -i skipped` that none of the new ones skipped, using the test database on port 5434.
- [x] Docs: a realtime page in `docs/`, the README, and an extension-author guide with the payments example above. (kempo has no CHANGELOG; release notes go where kempo keeps them.)
- [x] `npm run build` emits `dist/kempo/api/realtime/WS.js` and `dist/kempo/realtime.js`, and the full suite passes.
- [ ] Released through kempo's normal release process.

## Extension surface (scope added 2026-09-25)
The owner clarified that the point of this task is to make kempo's WebSocket capability a **generic primitive that future extensions build on**, the way `createPage` or `createUser` are: exposed through hooks and server SDK functions, with nothing game-, blog- or chat-specific in core. A game's shared world, a blog's live comments and a chat room should all be the same primitive at different rates. The first pass built channels, publish, replay and a browser client but left the extension points out; that was too narrow. This section adds them.

A shared real-time game world was raised as a stress test, not a plan: sub-second updates, 10 to 20 players per world, roughly 20 updates a second each. It is the capacity target to size against. The extension that would host it is future work and out of scope.

**Design constraints (why the surface is shaped this way)**
- Kempo's hook system reads the database on **every** trigger and awaits handlers in order. That is right for rare lifecycle events and wrong for per-message traffic, so lifecycle uses hooks and incoming messages use a handler resolved once into memory.
- Postgres `NOTIFY` fan-out serializes commits and cannot carry high-rate traffic. A channel that needs speed gets a process-local scope that never touches the database.

**Acceptance criteria**
- [x] **Lifecycle hooks** fire through the existing hook system without delaying the socket: `realtime:connected`, `realtime:disconnected`, `realtime:subscribed`, `realtime:unsubscribed`. A `realtime:before_subscribe` guard hook lets an extension refuse a subscription with custom logic, following the `middleware:before_page` precedent.
- [x] **Client-to-server messages.** A client can send a message to a channel it is subscribed to. A channel declares an `onMessage` handler (in `kempo-config.json`, or as a function when registered in code), resolved once and cached in memory. A client that is not subscribed to the channel is refused. A handler that throws sends an error to that client only.
- [x] **Acknowledgements.** A message sent with a `ref` gets an `ack` carrying the handler's return value, or an error, so a client can await a reply.
- [x] **Fast channels.** A channel declared `scope: "process"` delivers in memory to this process's subscribers and never touches Postgres. It cannot persist. The default scope stays cross-process.
- [x] **SDK functions** for acting on connections: send to one connection, close a connection, list a channel's subscribers, alongside the existing `publish`, `registerChannel` and `listConnections`. Anything process-local says so in its name or docs.
- [x] **Browser client** gains `send(channel, data)` returning a promise for the ack, and a way to receive direct messages.
- [x] **Per-connection limits in core:** message rate (default generous, configurable) and connections per user, with clear errors and a close code the client understands.
- [x] **kempo-server transport hardening:** expose how much is queued on a socket; a send option that drops when the connection is backed up (for latest-wins data); a hard ceiling that disconnects a stuck client so memory cannot grow without bound; and configurable caps on total connections and connections per IP. Core degrades cleanly on kempo-server 3.4.0, which lacks these.
- [x] **Capacity is measured**, not estimated: a test with 20 clients in one channel each sending at 20 per second on one process records fan-out latency, and the number goes in the docs.
- [ ] Tests, spec and docs updated for all of the above, and verified in a real browser.

## Repos Involved
- **kempo** (core), all of the work.
- **kempo-server**: the transport hardening above (queued-bytes visibility, drop-when-backed-up, a stuck-client ceiling, connection caps). Released separately as a minor.

## Out of scope for v1
- **kempo-payments live status.** The first consumer, its own task (0001 follow-up #3).
- **Presence / "who is online".** Needs shared cross-process state; not requested.
- **Cross-process admin view.** The admin page shows only its own process. Aggregating across processes would need a request/response over the bus.
- **Redis or any other broker.**

## Notes
**Design constraints found during refinement. These are easy to get wrong and are worth deciding early.**
- **Replay ordering.** A `bigserial` id is assigned at insert, not at commit, so two publishes on one channel can commit out of order. A client that replays `id > since` could then permanently skip a row that committed late. Publish should take a transaction-scoped advisory lock per channel (`pg_advisory_xact_lock`) so a channel's rows commit in id order, and insert the row and send the `NOTIFY` in the same transaction.
- **The backlog/live boundary.** To avoid both gaps and duplicates: start buffering live messages for the new subscriber first, then read the backlog up to the current max id, then flush buffered messages with an id above that. Test this deliberately; it is the most likely place for a subtle bug.
- **`LISTEN` and connection poolers.** `LISTEN` does not work through a transaction-mode pooler such as PgBouncer. Kempo's own docker-compose connects directly, but document the requirement for anyone who puts a pooler in front of Postgres.
- **A revoked session and an open socket.** Authorization runs on subscribe, so permission changes do not affect an existing subscription. That is acceptable for v1 but should be stated in the docs. Session invalidation is different and is an acceptance criterion above.

**Test hygiene (from earlier incidents).** Each kempo repo has its own throwaway database on its own port; kempo's is 5434. Never point a test suite at kempo-demo's database (its tests purge tables), and never run `drizzle-kit push` from one repo against another repo's database, because it drops the other repo's tables. Use `drizzle-kit generate` and a migration for the new table.

**History.** Task 0001 fixed the kempo-server blockers this depended on: upgrades now resolve through custom and wildcard routes (kempo serves its whole API through `"/kempo/**": "../node_modules/kempo/dist/kempo/**"`), and middleware now receives the enhanced request and response. kempo's build walks all of `src/` by file extension with no filename filter, so a `WS.js` under `src/kempo/api/**` is emitted to `dist/`, but that is from reading `scripts/build.js`, not from running a build.

**Sizing.** This is a large task: a bus, a table, a client, an admin page, and an SDK. If it needs to ship in pieces, the natural cut is (1) SDK, transport and bus, (2) persistence and replay, (3) browser client and admin view, since each is useful and testable on its own. Say so at approval if you would rather split it.


## Implementation notes (2026-09-25, branch `0003_add-realtime-layer-to-kempo-core`, 3 commits, not merged, not released)
Everything in the acceptance criteria is built except the release, which is waiting on a decision. 451 kempo node tests pass with a database (zero `(SKIPPED)`), and 402 pass with none, where the three new DB-backed files report `(SKIPPED)` as designed. Under the fixed testing framework (1.5.0) kempo's suite also has no masked failures.

**How it differs from the plan, and why**
- **Permission is `system:realtime:read`**, not `view`, to match the existing `:read` names.
- **Extension channels are declared in `kempo-config.json`, not only registered in code.** Reading kempo showed extensions are declarative: hooks and config live in the database and load lazily, so an imperative `registerChannel` in an extension's module could run *after* the first subscriber connects. The `extension` table already stores each extension's `kempo-config.json` snapshot, so every process resolves declared channels from the database with no load-order dependency, and disabling an extension closes its channels. `registerChannel` remains for application code and only works for modules loaded at startup; both are documented.
- **Two tables, not one.** `realtimeChannel` holds a per-channel `prunedThrough` watermark, since ids are shared across channels and a gap cannot be inferred from id arithmetic.
- **Sessions are re-checked on an interval (default 30 s), not revoked instantly.** That meets "within a bounded time" and works across processes, since a signed-out session is found by whichever process holds the socket. Verified: closes with 4401 in about 2 s at a 3 s interval.
- **The admin permission name in nav**: the nav does not gate by permission; the page and API do.

**Bugs found and fixed while building this** (all with a test that fails without the fix, checked by mutation)
- **The browser client never retried under Node.** A browser fires `error` then `close` for a refused connection; Node's WebSocket fires only `error`. The client waited for `close`, so one failed attempt ended reconnection for good. Found by the end-to-end test.
- **A file overwritten by a case-insensitive filesystem.** Creating `hub.js` next to `Hub.js` silently replaced the class with its accessor. Renamed the accessor `getHub.js` and recorded the rule in the spec. kempo's `package-invariants` test already checks import case.
- **A test message ending in the word "from"** made kempo's import scanner report a bogus package, since its regex reads `from '`.
- **My mutation harness reported three real tests as "missed"** because its filters matched no test name. Now it reports `NORUN` when nothing matched.

**Verification**
- 16 hub tests against real Postgres, with two `Hub` instances standing in for two processes: cross-process delivery, ordering under 30 concurrent publishes, the replay boundary race repeated at eight different timings, gap detection, pruning, size limits, session revocation, and recovery after the LISTEN connection is killed. 8 mutations of the critical logic, all caught.
- 9 end-to-end tests with a real kempo-server process, the real middleware and the built `dist`, including the client reconnecting and replaying across a server restart.
- Real Chrome: connect, receive messages published from a separate process (persisted, with ids, and on the user's own channel), the unknown-channel 404 reaching `onError`, reconnect after a server restart replaying exactly the two missed messages with none repeated, and signing out closing the socket and stopping the client. The admin page renders with correct styling and lists the live connection.
- `npm run build` emits `dist/kempo/api/realtime/WS.js` and `dist/kempo/realtime.js`, which settles the earlier "not confirmed by a build" note.

**Upgrade impact for existing installs.** New tables need applying (`drizzle-kit push` or generate/migrate), and `init-db.js` should be re-run to create the permission. Administrators already pass every permission check, so the admin page works before that.

**Not done, needs a decision:** merging to `master` and releasing. Pushing to `master` runs kempo's publish workflow, which publishes a patch on any push not marked `[skip ci]`. A feature this size should be a `minor` run manually, as with kempo-server 3.4.0.

**Deliberately not included:** upgrading kempo's own `kempo-testing-framework` (still 1.4.7). Its suite has no masked failures under 1.5.0, but the bump churns the lockfile (puppeteer 24 to 25) and belongs in its own change.

## Extension surface: implementation notes (2026-09-25)
Built on the same branch in both repos: kempo `0003_add-realtime-layer-to-kempo-core` (commits `4cd5939`, `4cbcc66`, `abee63c`, `e32fc5b`) and kempo-server `0003_add-realtime-layer-to-kempo-core` (commit `e43d179`). Nothing merged or released. 485 kempo node tests pass with a database (zero `(SKIPPED)`, `package-invariants` included) and 414 pass with none, where the eight database entries report `(SKIPPED)` as designed.

**What exists now**
- Channels take `scope` (`cluster` | `process`), `onMessage` and `dropIfBackedUp`, declared in `kempo-config.json` or passed to `registerChannel`. An extension's `onMessage` is a path confined to its own package, loaded once and cached; a declaration that cannot be honoured closes the channel.
- Hooks `realtime:connected`, `disconnected`, `subscribed`, `unsubscribed`, and the fail-closed guard `realtime:before_subscribe`.
- `send` frames with acks (`ref`), ordered per-connection handling, a rate limit (close `1008` after five windows over), a bounded queue, `sendToConnection` / `closeConnection` / `listSubscribers`, a per-user connection cap (`4429`, the browser client stops with status `refused`), and the browser client's `send()` and `onDirect()`.
- kempo-server: `bufferedAmount`, `send(..., { dropIfBackedUp })`, a buffer ceiling (`1013`), `maxConnections`, `maxConnectionsPerIp`, `trustProxy`, with 10 tests. Unreleased; it needs a minor. Core on 3.4.0 simply does not get those protections.

**Findings worth keeping**
- **The capacity test found a real latency bug.** The first runs had a ~200 ms p99. I suspected Nagle and delayed ACK, and disproved it: the tail appeared in whichever phase ran first, whatever the client or socket options. The cause was the first message of each run paying for a dynamic `import` of the handler. The hub now loads a channel's handler when a subscription is granted, and a hub test fails if that call is removed (mutation-checked). The capacity test also asserts p99 under 150 ms, and it failed under the same mutation.
- **The test's own senders were slow.** `setInterval(..., 50)` on Windows ticks at about 15 ms granularity and delivered well under the intended rate. Senders now catch up to a schedule, so the real rate is 400 sends a second, and the test reports the achieved rate.
- **Measured** (loopback, one machine, 20 clients x 20 messages a second into one `process` channel that republishes: 400 in, 8,000 out a second, both a raw no-delay client and Node's built-in WebSocket): nothing lost; p50 about 2 ms, p95 4 to 8 ms, p99 5.5 to 10 ms, slowest 6 to 16 ms. Recorded in `docs/realtime.md` with its caveats (loopback, shared CPU, Windows timers).
- **Mutation testing has to run the whole file for `realtime-http`.** Its first test is the setup, so a name filter skips it and the rest fail spuriously; `dist/` must be rebuilt for route mutations. Noted at the top of that test file.
- **Fixture handlers must not import the SDK by a relative string.** `package-invariants` scans every `from '...'` in test files, including ones inside written fixture source, and reported them as unresolvable. The fixtures now import the SDK by an absolute file URL built at run time.
- **Real browser verification** (Chrome, separate server on port 9911 with the kempo test database, not kempo-demo): send and ack round trip, a handler's `{ code, msg }` reaching the sender, a thrown `Error` arriving as a generic `500` with no internal text, `sendToConnection` reaching the `onDirect` listener, `403` not subscribed, `405` no handler, `504` on timeout, the guard hook's `451` reaching `onError`, all five hooks firing with the right data and no session token, a fourth connection for a user capped at three ending as `refused`, a 250-message burst against a limit of 100 a second giving exactly 100 acks and 150 `429`s, replay from `since: 0` and live delivery of messages published from another process, and the admin API answering `403` to a non-admin. Everything created for it (users, group, permission, extension, hooks, messages, files) was removed and the database checked to be empty of it.

**Still open:** the release criterion (kempo needs a manual `minor`, and the merge to `master` must carry `[skip ci]` so the publish workflow does not also cut a patch), and a kempo-server minor for the hardening. Both wait for an explicit go-ahead.
