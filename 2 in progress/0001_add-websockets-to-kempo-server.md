---
title: add-websockets-to-kempo-server
description: Add WebSocket support (RFC 6455) to kempo-server's file-based routing so a route file can accept a socket upgrade, exchange messages with the browser, and be pushed to from other server code
repos: kempo-server
status: in progress
created: 2026-09-24
owner: Dustin
qa: Dustin
branches:
  kempo-server: 0001_add-websockets-to-kempo-server
prs: {}
---

# add-websockets-to-kempo-server

## Description
Let a kempo-server route accept a WebSocket connection and exchange messages with the browser, and give other server code a supported way to push to connected sockets. This task is the **transport layer only**. Channels/topics, presence, mapping a socket to a user, and the API that kempo (CMS) extensions would use to hook into it are a higher layer built on top of this (see Follow-ups).

**Why it has to live in kempo-server.** `src/index.js:44` creates the server with `http.createServer(await router(flags, log))` and registers no `upgrade` listener, so today a `new WebSocket()` handshake is served as an ordinary GET and gets whatever GET route, page or 404 sits at that path. A kempo (CMS) extension has no supported way to add this from outside: it ships routes, pages and hooks and is never handed the server. (Reaching the `http.Server` through `req.socket.server` and attaching an `upgrade` listener would technically work, but it bypasses routing, middleware and config, so it is not a foundation to build on.) Registering an `upgrade` listener diverts *every* upgrade request away from the router, so the middleware chain, route resolution and request wrapping all have to be invoked explicitly for the handshake.

**Decisions already made (from the design discussion):**
- **Zero runtime dependencies.** `package.json` describes kempo-server as "zero-dependency", and the same rule was applied to templating (no HTML parser). So the handshake and framing are implemented on Node built-ins (`crypto` for the SHA-1 accept key, the upgraded socket for frames), not with `ws`.
- **Route convention: a `WS.js` file**, alongside `GET.js` / `POST.js`, exporting a default function like every other route file. The same URL can serve a normal GET page and a socket. (Name to be confirmed, see Notes.)
- **Transport only.** No rooms, presence or user mapping here. A WS route authenticates the way HTTP routes already do: it reads `request.cookies.session_token` and calls kempo core's `getSession`. No change to kempo core is needed for this task.

## Acceptance Criteria
**Routing and handshake**
- [x] A `WS.js` route file accepts a WebSocket upgrade at its path, resolved by the same file-based rules as HTTP routes (static paths and `[param]` segments, with `request.params` populated). Support for custom/wildcard routes is decided and documented.
- [x] Only a file named exactly `WS.js` is ever run for an upgrade. `findFile` falls back to `index.js` / `CATCH.js` for a directory request, so an upgrade to a path with no `WS.js` (even one that has `GET.js`, `index.js` or `CATCH.js`) gets an HTTP 404 and the socket is closed. A normal HTTP request never executes `WS.js`.
- [x] The handshake follows RFC 6455 section 4: correct `Sec-WebSocket-Accept`; requires `Upgrade: websocket`, `Connection: Upgrade` and a valid `Sec-WebSocket-Key`; an unsupported `Sec-WebSocket-Version` gets 426 with `Sec-WebSocket-Version: 13`; a malformed handshake gets 400.
- [x] The route receives the same enhanced request HTTP routes get (`headers`, `cookies`, `query`, `params`, `path`) and can refuse the upgrade with an HTTP status (e.g. 401/403) before any socket is established, so cookie-session auth works exactly as it does for HTTP routes.
- [x] The configured middleware chain (CORS, rate limit, security, logging, custom middleware) runs for the handshake. A middleware that ends the response rejects the upgrade, and its status/headers/body reach the client. Which built-ins are meaningful for a 101 response is settled and documented.

**Messaging**
- [x] Text and binary messages work in both directions, including fragmented messages (reassembled), and all three payload-length forms (7-bit, 16-bit, 64-bit).
- [x] Client frames must be masked; an unmasked frame closes the connection with 1002. Text frames are validated as UTF-8; invalid UTF-8 closes with 1007.
- [x] Control frames behave per spec: a ping is answered with a pong echoing its payload; a control frame over 125 bytes or fragmented closes with 1002.
- [x] Close handshake works both ways: a client close is answered with a matching status, `socket.close(code, reason)` starts one, and the connection is torn down cleanly afterwards.

**Safety and lifecycle**
- [x] **Origin check:** because session cookies ride along on the handshake, a page on another site could otherwise open a socket as the logged-in user (cross-site WebSocket hijacking). The handshake `Origin` is validated against a configurable allow-list, defaulting to same-origin (Origin host matches the request Host); a mismatch gets 403. Behaviour for a request with no `Origin` (non-browser clients) is decided and documented.
- [x] **Limits:** a configurable maximum message size (default far below the 500MB `maxBodySize`) closes the connection with 1009 when exceeded, and the options are documented in CONFIG.md next to `maxBodySize`.
- [x] **Liveness:** the server pings idle connections on a configurable interval and drops any that fail to pong in time. After a client vanishes without a close frame, no socket or timer is leaked.
- [x] **Isolation:** an error, slow consumer or closed socket on one connection never crashes the process or affects other connections. Sending on a closed socket does not throw into route code. An exception in a route's handler closes that connection with 1011 and is logged.
- [x] **Shutdown:** when the server closes (including SIGINT), open sockets receive close 1001.

**Sending from outside the route**
- [x] There is a documented, supported way for code outside the `WS.js` route (an HTTP route such as a `POST.js` webhook handler, or a kempo (CMS) extension such as kempo-payments) to find and send to connected sockets. Connections can be filtered by route path and by data the route attached to the socket. The registry is shared across route modules and is not per-module state. It is single-process only, and the docs say so.

**Compatibility and quality**
- [x] A server with no `WS.js` behaves exactly as before. The existing test suite passes unchanged, and `package.json` still has no runtime `dependencies`.
- [x] Node tests cover: valid/invalid handshakes, framing (all length forms, masking, fragmentation, control frames, UTF-8), limits, origin check, heartbeat, middleware rejection, outside-sending, shutdown. Malformed-frame cases use raw sockets; happy paths may use Node's built-in `WebSocket` client.
- [x] Verified end to end in a real browser (Chrome DevTools) against the docs dev server with a working echo example: a page's `new WebSocket()` connects, echoes text and binary, reconnects after a reload, and an HTTP POST route pushes a message to the connected page.
- [x] Docs updated: README, CONFIG.md (new options), llms.txt, a new WebSockets page in `docs-src` (with nav entry) including the echo example and the scope limits, and a CHANGELOG `[Unreleased]` entry. `npm run build` regenerates `dist/` and the built server passes the same checks.

## Repos Involved
- **kempo-server** — all of the work: `src/index.js` (upgrade listener), a new WebSocket module for handshake/framing/registry, `src/defaultConfig.js` (`routeFiles` gains `WS.js`, plus the new options), `src/findFile.js` usage, tests, docs.
- **kempo (core)** — *not* touched by this task. The transport needs nothing from it; the follow-ups (channels, auth-to-user mapping, and a way for kempo (CMS) extensions to register socket handlers) will.

## Notes
**To confirm at approval (judgment calls I made):**
1. The `WS.js` filename, versus e.g. `SOCKET.js`. `WS.js` matches the existing METHOD-file convention, and a handshake is really a GET with `Upgrade: websocket`, so it needs its own name to coexist with `GET.js` at the same URL.
2. Scope is transport only; channels, presence and user mapping are deliberately deferred.
3. Origin defaults to same-origin, with an allow-list override.
4. Out of scope for v1: `permessage-deflate` and any other WebSocket *protocol* extension (unrelated to kempo extensions), `Sec-WebSocket-Protocol` subprotocol negotiation, and cross-process fan-out (this is a single-process registry).

**Implementation notes (verified against the code on 2026-09-24):**
- The router only sees requests Node emits as `request`. Once an `upgrade` listener exists, upgrades bypass `src/router.js` entirely, so the handshake path must resolve the file (`findFile(files, rootPath, path, 'WS', log)`), build the enhanced request (`createRequestWrapper` already parses cookies and query from headers and can be reused as-is), and run `MiddlewareRunner` itself. Existing middleware is written as `(req, res, next)` and expects a `res`; one likely approach is an `http.ServerResponse` bound to the socket so it can run and reject unchanged. Verify this against the built-ins in `src/builtinMiddleware.js` (compression and header-writing ones in particular).
- The upgrade has no request body, so skip the body buffering the router does before middleware.
- Route modules are re-imported with a `?t=` cache-buster or served from the module cache, so an open connection keeps the `WS.js` it started with and an edit only affects new connections. Document this.
- Registry hazard: kempo-server is symlinked in dev (`link:local`) and could appear twice in a consumer's dependency tree. The shared registry must be reachable from every copy (e.g. hang it off the server instance or a `Symbol.for` global), not module-scope state, or "outside-sending" silently finds no connections.
- Node v22.17.1 is installed here, so the global `WebSocket` client is available for tests. Note kempo-server declares no `engines` field.

**Release handling (important):**
- **Re-verified 2026-09-25 at task start:** that 3.4.0 work is now **pushed** (`main` is in sync with origin, working tree clean) but still **unpublished** â `package.json` says 3.3.0, the registry's latest is 3.3.0, and the CHANGELOG top is still `[Unreleased]`. So kempo core's `kempo-server >= 3.4.0` peer is still unsatisfied on the registry. Branched from `main` as it stands (`0001_add-websockets-to-kempo-server`). The WebSocket CHANGELOG entry joins the same `[Unreleased]` section, and 3.4.0 ships templating + WebSockets together unless it is released first.
- `.github/workflows/publish.yml` publishes a **PATCH on any push to `main`** unless the commit message contains `[skip ci]`; only a manual `workflow_dispatch` chooses the bump. This is a feature, so it needs a `minor` release run manually, sequenced with the pending 3.4.0 release chain, not a plain push.
- The `dist/render.js` line-ending noise noted on 2026-09-24 is gone; the working tree was clean at branch time. `npm run build` regenerates `dist/` anyway.

**Implementation notes (2026-09-25, all acceptance criteria met):**
- Landed as `src/websocket/` — `frames.js` (RFC 6455 encode/decode), `handshake.js`, `socket.js` (KempoSocket), `registry.js` (Symbol.for global), `index.js` (upgrade handler). `src/router.js` exposes `handler.upgrade`; `src/index.js` registers it and handles SIGINT/SIGTERM.
- Decisions confirmed as written: `WS.js` filename, transport-only scope, same-origin default with allow-list, and the v1 exclusions (no permessage-deflate, no subprotocol negotiation, single-process registry).
- No-`Origin` behaviour decided: **allowed by default**, with `requireOrigin: true` to tighten. Browsers always send `Origin` on a handshake, so its absence means a non-browser client with no ambient cookies — not the CSWSH threat the check exists for.
- Custom/wildcard routes decided: **not supported for upgrades**, documented. A socket route must live in the served tree.
- Compression middleware is skipped for upgrades (a 101 has no body, and it works by wrapping the response write path); the other four built-ins plus custom middleware run.
- 341 node tests pass (310 pre-existing + 31 new). Browser-verified via Chrome DevTools against `npm run dev`: connect, text echo, binary echo with bytes 250/255 intact, reconnect after reload, and an HTTP POST pushing to the connected page. SIGINT verified to deliver close 1001 and exit 0 (had to be triggered in-process — Windows cannot deliver a catchable SIGINT to a child).
- A live demo ships at `docs-src/websocket-demo.page.html` with `docs-src/echo/WS.js` and `docs-src/echo/push/POST.js`.

**Known limitation, not covered by the criteria:** outbound backpressure is unbounded. `socket.write()` returning `false` is ignored, so a slow consumer accumulates queued frames in memory. This cannot crash the process or affect other connections (which is what the isolation criterion required), but a drop-or-disconnect policy for a persistently slow consumer is worth a follow-up if sockets are ever used for high-rate fan-out.

**Follow-ups (separate tasks, not this one):**
1. **Cloud-save kempo (CMS) extension** for Tim's game: user accounts plus a REST endpoint persisting a JSON blob per user/game. Needs *no* WebSockets and can ship first, independently.
2. **A kempo-level realtime layer:** channels/topics, socket-to-user mapping via session, and an API for kempo (CMS) extensions to register socket handlers. Probably its own kempo (CMS) extension or a kempo core feature; to be decided when that task is written.
3. **kempo-payments live status**, the first consumer: the admin list/detail subscribe and the Stripe webhook handler pushes status changes (today they only update on Refresh or after an action).
4. **Generic multiplayer/presence + game-state kempo (CMS) extension**, proven with a tic-tac-toe demo. It is a bigger design problem (rooms, an authoritative state model) than this transport.
