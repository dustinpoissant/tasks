---
title: add-game-extension
description: Create a "game" kempo (CMS) extension that syncs game state and does real-time multiplayer updates on top of kempo core's built-in WebSocket realtime layer
repos: kempo-game (new), kempo
status: idea
created: 2026-09-26
owner: TBD
qa: TBD
branches: {}
prs: {}
---

# add-game-extension

## Description
Kempo core now ships a generic realtime layer (kempo 4.3.0 on kempo-server 3.5.0): channels, client-to-server handlers with acks, lifecycle hooks, fast in-memory `scope: "process"` channels, connection SDK functions, limits and backpressure. It deliberately contains nothing game-specific. This task is the first extension built on it: a **kempo (CMS) extension** named "game" that gives a developer the pieces for syncing game state and running real-time multiplayer, so a game does not have to talk to sockets itself.

It has two purposes. It is a useful extension, and it is the first real consumer of the realtime surface, which so far has only been exercised by tests and fixtures. Anything awkward about the surface that only shows up when an extension actually uses it should be fed back into core.

**Capacity target (from the realtime work, not a plan for a specific game):** a world of 10 to 20 players with roughly 20 updates a second each, sub-second latency between players standing next to each other. Measured on loopback, core carried 20 clients at 20 messages a second with about 2 ms median latency; the extension should stay within that envelope. Motivating example only: a 2D sprite RPG where a player either hosts a world for friends while they are online, or pays for a persistent shared world. That game is not built here.

## What core already provides (so the extension does not rebuild it)
- Channels declared in `kempo-config.json`, closed by default behind a permission.
- `scope: "process"` channels: in-memory delivery on one process, never touches Postgres, cannot persist. `dropIfBackedUp` for latest-wins data.
- `onMessage` handlers, loaded once and kept in memory, with acks and `{ code, msg }` errors. Handled in order per connection.
- Lifecycle hooks (`realtime:connected`, `disconnected`, `subscribed`, `unsubscribed`, and the `before_subscribe` guard). Hooks are for lifecycle only, never per-message.
- SDK: `publish`, `sendToConnection`, `closeConnection`, `listSubscribers`, `listConnections`.
- Limits: 10 connections per user, 100 messages a second per connection (both configurable).

## Constraints from core that shape the design
- **A process channel lives on one process.** A world must be served by one process, and everyone in it routed there (sticky routing at the load balancer). The extension has to say so plainly.
- **Connection functions are process-local.**
- **Hooks read the database on every call**, so per-tick or per-input work belongs in the `onMessage` handler and in memory, not in a hook.
- **Cluster channels go through Postgres `NOTIFY`**, so they suit low-rate things (lobby, chat, roster changes), not the game loop.

## Acceptance Criteria
Initial, to be sharpened in refinement.
- [ ] A new extension repo, installed and enabled through kempo's real extension install path (`installExtension`), from a package installed into a clean project. It declares its channels, permissions and hooks in `kempo-config.json`.
- [ ] **Worlds/rooms:** create, join and leave a world; a world has a bounded player count; joining is authorized by a permission and by the extension's own rules through the `before_subscribe` guard.
- [ ] **State sync:** clients send inputs to the world's handler; the server holds authoritative state and broadcasts it (whole snapshots and/or deltas) on a fast channel, using `dropIfBackedUp` where only the newest state matters.
- [ ] **Players leaving:** a disconnect or dropped connection is noticed through the lifecycle hooks and the player is removed from the world.
- [ ] **A tick loop** on the server that steps a world at a fixed rate, with clean start and stop when a world gains its first or loses its last player.
- [ ] **Client library** for browsers: join a world, send input, receive state, expose connection status, built on `/kempo/realtime.js`.
- [ ] **Persistence seam:** state is in memory by default; a world can be saved and restored through an interface the extension defines, so a persistent "realm" can be added later without changing the sync code. What is stored is not decided here.
- [ ] **Measured**, not estimated: a test with 20 clients in one world at 20 inputs a second records tick and delivery latency, and the numbers go in the docs.
- [ ] A small playable demo (not a full game) proving two browsers see each other move, verified in a real browser.
- [ ] Tests, docs and README, following the conventions of the other kempo (CMS) extensions (see kempo-files, kempo-thumbs, kempo-user-dirs).

## Repos Involved
- **kempo-game** (new): the extension itself.
- **kempo**: only for anything the work shows is missing from the realtime surface, kept minimal and fixed as its own change.

## Open questions (for refinement)
- **Authoritative server or relay?** Server-authoritative (the extension runs game rules) is safer against cheating and is what the handler model fits; a relay (clients trust each other) is simpler. The extension may support both, but one has to be the default.
- **How much game logic belongs in the extension?** The extension should provide rooms, sync and a tick loop and leave rules to the game developer, who supplies them as a module the way an extension supplies a hook. What the developer's module looks like is the main design question.
- **Snapshot or delta protocol**, and whether the extension defines a wire format or leaves it to the game.
- **Free hosted worlds versus persistent paid realms:** a monetization/subscription seam belongs to another extension (kempo-commerce and payments exist). This task should only leave a place for it, not build it.
- **Room routing across several processes:** documented requirement, or something the extension helps with?
- **Name and scope:** "game" as a package name (`kempo-game`) and whether it stays generic or grows toward a specific genre.

## Notes
- Write "kempo (CMS) extension", not a bare "the extension".
- The realtime docs are `docs/realtime.md` and the design record is `spec/concepts/realtime.md` in kempo.
- Test databases are per repo; never point a suite at kempo-demo's database.
