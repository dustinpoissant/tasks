---
title: add-realtime-layer-to-kempo-core
description: Build the realtime layer in kempo (CMS core) on kempo-server's WebSocket transport - authenticated sockets, channels, a Postgres LISTEN/NOTIFY bus across processes, persisted messages with replay, a browser client, and an admin connection view - so kempo (CMS) extensions can push to clients
repos: kempo
status: ready
created: 2026-09-25
owner: Dustin
qa: Dustin
branches: {}
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
- **Clients only subscribe.** They cannot publish to arbitrary channels, and there are no client-to-server message handlers for extensions in v1 (see out of scope).
- **Owner and QA are Dustin**, matching task 0001.

## Architecture
Follows the four-layer rule in AGENTS.md: `server/utils/` is HTTP-agnostic and returns `[error, data]` tuples; the HTTP layer only extracts data and calls it.
- **HTTP layer:** `src/kempo/api/realtime/WS.js`, served at `/kempo/api/realtime`. Thin: reads `request.cookies.session_token`, calls a util, wires socket events to utils.
- **Utils:** `server/utils/realtime/` (register/subscribe/unsubscribe/publish, the bus, replay, pruning). Plain-data arguments, testable with no mocking.
- **Schema:** a `realtimeMessage` table in `server/db/schema.js` (monotonic `id`, `channel`, `data` jsonb, `createdAt`, index on `(channel, id)`), added by a real migration (`drizzle-kit generate`).
- **Bus:** its own module holding a **dedicated** listening connection, separate from the pooled query client in `server/db/index.js`.
- **SDK:** exported through `server/sdk.js`.
- **Browser client:** `src/kempo/realtime.js`, served at `/kempo/realtime.js` next to the existing `fetch.js` and `sdk.js`.
- **Admin:** `src/admin/realtime/` page plus an entry in `src/admin/nav.fragment.html`, gated by a new `system:realtime:view` permission seeded where the other `system:*` permissions are (`scripts/init-db.js`).

**Wire protocol (draft, to be finalized in implementation).** JSON frames. Client to server: `{type:'subscribe', channel, since?}`, `{type:'unsubscribe', channel}`. Server to client: `{type:'subscribed', channel}`, `{type:'message', channel, id?, data}`, `{type:'gap', channel}`, `{type:'error', channel?, code, msg}`.

## Acceptance Criteria
**Transport and auth**
- [ ] `WS.js` under `src/kempo/api/realtime/` accepts an upgrade in a stock consumer install through the `/kempo/**` wildcard mapping (kempo-server 3.4.0 or later), refuses with 401 when there is no valid session, and inherits kempo-server's origin check.
- [ ] Verified in a real browser against kempo-demo, with kempo's **real** `middleware/kempo.js` in the chain (kempo-server's own tests only exercise a stand-in).
- [ ] A socket is tied to its user, and server code can publish to a user's `user:<id>` channel.
- [ ] A socket is closed within a bounded time after its session is invalidated (logout, expiry, password change). A long-lived socket must not outlive the session that authenticated it.

**Channels and SDK**
- [ ] `registerChannel({ name, authorize, persist, retention })` enforces the extension-name prefix, rejects a collision with an error tuple, and is exported from `server/sdk.js`.
- [ ] Subscribe and unsubscribe work over the socket. An unauthorized or unregistered channel gets an error frame and the connection stays open.
- [ ] `publish({ channel, data })` can be called from any server code (an HTTP route, a webhook handler, a hook) and reaches subscribers held by this process and by other processes.
- [ ] Every util follows the AGENTS.md rules: no HTTP objects, error tuples, plain-data arguments.

**Cross-process bus**
- [ ] The listening connection is dedicated, not taken from the query pool, and survives a dropped database connection: it reconnects, re-listens, and logs rather than crashing the process.
- [ ] A test with two kempo server instances on one database shows a publish in one reaching a subscriber connected to the other.
- [ ] A non-persisted message over the `NOTIFY` size limit returns a clear error tuple instead of failing silently. A persisted message sends only its id over `NOTIFY` and the receiver reads the row.

**Persistence and replay**
- [ ] The `realtimeMessage` table and its migration exist. Persistence is opt-in per channel and each channel has its own ordering.
- [ ] Subscribing with `since: <id>` delivers the missed persisted messages in order before live ones, with **no gap and no duplicate at the boundary** between backlog and live delivery.
- [ ] Rows older than the channel's retention are pruned. A client asking for a `since` older than what remains gets a `gap` frame, so it knows to refetch fully instead of silently missing messages.

**Browser client**
- [ ] `/kempo/realtime.js` connects, subscribes, and reconnects automatically with backoff, resubscribing with the last id it saw. Close code 1001 (server restarting) reconnects promptly.
- [ ] It does not retry forever on an auth failure (401 or a session-invalidated close), and reports connection state to the caller.
- [ ] Verified in a real browser by stopping and restarting the server and by dropping and restoring the database connection.

**Admin view**
- [ ] `/admin/realtime`, gated by `system:realtime:view`, lists this process's connections (user, path, channels, connected since, last activity) and per-channel counts, and says plainly that it shows only this process.
- [ ] Built with kempo-css utilities and `<k-icon>`, no custom CSS or unicode icons (AGENTS.md). Any new icon goes in kempo core's `src/kempo/icons/`, in Material Symbols style.

**Quality and delivery**
- [ ] Tests cover: auth, prefix enforcement, authorization, cross-process delivery, the replay boundary race, the `gap` case, retention pruning, reconnect, and session-invalidation close.
- [ ] **The DB-backed tests actually run.** kempo's DB suites report `(SKIPPED)` and count as passing when no database is reachable, so confirm with `npx kempo-test -l normal | grep -i skipped` that none of the new ones skipped, using the test database on port 5434.
- [ ] Docs: a realtime page in `docs/`, the README, and an extension-author guide with the payments example above. (kempo has no CHANGELOG; release notes go where kempo keeps them.)
- [ ] `npm run build` emits `dist/kempo/api/realtime/WS.js` and `dist/kempo/realtime.js`, and the full suite passes.
- [ ] Released through kempo's normal release process.

## Repos Involved
- **kempo** (core), all of the work.
- kempo-server is **not expected to change**. If something turns out to need it, that is its own task, not scope creep here.

## Out of scope for v1
- **kempo-payments live status.** The first consumer, its own task (0001 follow-up #3).
- **Client-to-server message handlers for extensions.** No consumer needs them yet; clients only subscribe.
- **Presence / "who is online".** Needs shared cross-process state; not requested.
- **Cross-process admin view.** The admin page shows only its own process. Aggregating across processes would need a request/response over the bus.
- **Outbound backpressure in kempo-server.** A slow client still queues frames in memory (known limitation from 0001). Fine for low-rate status pushes; worth its own task before any high-rate use.
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
