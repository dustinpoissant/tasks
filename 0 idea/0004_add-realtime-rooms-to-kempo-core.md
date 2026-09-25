---
title: add-realtime-rooms-to-kempo-core
description: Add rooms to kempo's realtime layer - membership and presence, client-to-server messages, in-memory fan-out that bypasses Postgres, latest-wins backpressure and snapshot-on-join - so a kempo (CMS) extension can run a shared real-time world for 10-20 players
repos: kempo, kempo-server
status: idea
created: 2026-09-25
owner: TBD
qa: TBD
branches: {}
prs: {}
---

# add-realtime-rooms-to-kempo-core

## Description
Task 0003 built realtime **channels**: server-to-browser push, fanned out through Postgres `NOTIFY`, with optional persisted replay. That is right for "a payment changed status" and wrong for a shared game world, where players send input and every other player must see the result within a fraction of a second. This task adds the second mode: **rooms**.

A room is a set of connected players that talks to itself directly, from memory, in one process. It gives a kempo (CMS) extension what it needs to host something like a shared 2D world: who is here, messages from each player, updates out to the others, and a full snapshot for anyone joining.

**The motivating case.** A friend is building an HTML5 canvas, emoji-sprite, 2D tile RPG in the style of the early Pokemon games: towns, monsters, side quests, cave puzzles, and a world that changes as you walk it (a route walked repeatedly packs from grass into a dirt path and then gravel). The goal is for other players to join your world, see each other's sprites move, and see shared changes: path wear, shared monsters. The mental model is Minecraft multiplayer.

That game is the consumer, not the scope. Nothing here should know what a tile, a monster or a path is; the world simulation belongs to the game's own extension. This task builds the primitives underneath it.

## Requirements from the owner (2026-09-25)
- **Latency:** other players must feel current. Target a 20 updates-per-second tick (50 ms), with others drawn about 100 ms behind via interpolation on the client. An update cycle measured in seconds is not acceptable. Not an RTS: no lockstep, no hundreds of units.
- **Scale:** like Minecraft multiplayer. **10 players per world is the expected maximum, 20 at the outside.**
- **Two kinds of world, both required:**
  1. **A world that exists while its host is online.** Like joining a friend's Minecraft world. Free to the players; costs the platform almost nothing.
  2. **A persistent "realm" that stays available when the host is offline.** Paid, by monthly subscription.

## Design direction (proposed, not yet approved)
**Room traffic must not go through Postgres.** A `NOTIFY` per player per tick would serialize commits and back up behind my hub's one-at-a-time notification handling. The problem is throughput, not the latency of any single message. A room instead lives **in the memory of exactly one process**, sockets in it exchange frames directly, and the database is used only to save state (the path-wear map, monster state, quest progress), not to move it.

**One room primitive, two ways to run a world.** The same room supports both kinds the owner asked for:
- **Host-authoritative (the free, host-online world).** The host's browser runs the simulation. The server authenticates players, tracks membership and relays: guests' inputs go to the host, the host's state goes out to guests. The server does no game simulation, so hosting costs almost nothing. The world ends, or is saved by the host, when the host leaves.
- **Server-authoritative (the paid realm).** The extension registers a handler and the server runs the simulation, so the world keeps existing with nobody home.

The consequence for the game is large and should be told to its author early: **for the paid mode, the simulation must run in Node as well as in the browser.** The game engine should be split into a simulation core (state and rules, no canvas or DOM) and a renderer, so the same core runs in the host's browser for free worlds and in a kempo process for realms. Retrofitting that split later is expensive.

## What is needed in kempo core
- **Client-to-server messages.** Today a client can only `subscribe` and `unsubscribe`. Rooms need frames an extension handles: input, actions, chat.
- **Rooms with membership and presence.** Join, leave and drop events, and a way to ask who is in a room. A dropped connection gets a short grace period to rejoin as the same player.
- **Snapshot on join and reconnect.** A new or returning player gets the current world state, not a replay. (Channels' `since` replay is the wrong tool for a world.)
- **Latest-wins backpressure.** A slow client currently queues outbound frames in memory without limit (known limitation from task 0001). For positions only the newest matters, so an update to a backed-up client replaces the stale one instead of queueing behind it, and a persistently stuck client is disconnected. This needs a small kempo-server change to expose how much is queued on a socket.
- **Limits.** Per-client message rate, frame size, and room size, so one bad client cannot flood a room.
- **Process ownership.** A room lives in one process. On a single server this is automatic. If kempo runs on several, a room must be assigned to exactly one (a Postgres advisory lock is the obvious candidate); document what happens when its process dies.
- **A tick helper (optional).** A fixed-rate loop that batches changes and broadcasts them, so extension authors do not each write one.
- **Browser client support.** Room join, send, receive, rejoin with a snapshot, and the existing reconnect behavior.

## Acceptance Criteria (draft, to be refined)
- [ ] {A client can send frames to code an extension registers, and an extension can send frames to one player, all players, or all but one}
- [ ] {Room join, leave and drop events are delivered; presence can be queried; a dropped player can rejoin within a grace period as the same player}
- [ ] {A joining or reconnecting player receives a snapshot supplied by the extension}
- [ ] {Room traffic never touches Postgres: verified by a test that runs a room with the database unreachable}
- [ ] {Measured target: with 20 players each sending at 20 Hz in one room on one process, p95 fan-out latency stays under 50 ms on the reference machine, and the number is recorded in the docs}
- [ ] {A slow or stuck client cannot grow server memory without bound and cannot delay other players; a stale queued update is replaced by a newer one}
- [ ] {Limits on message rate, frame size and room size are enforced with clear errors}
- [ ] {Host-authoritative and server-authoritative rooms both work from the same primitive, each demonstrated by an example}
- [ ] {A room is owned by exactly one process, and the behavior when that process dies is defined and tested}
- [ ] {An entitlement hook lets an extension decide who may open a room or a realm (see below)}
- [ ] {Docs, spec, and a working example extension: a tiny shared 2D world with visible players and a shared changing tile, proven in a real browser with two tabs}

## Repos Involved
- **kempo** (core): rooms, presence, messages, snapshots, limits, browser client, docs.
- **kempo-server**: expose queued bytes per socket so backpressure can be enforced. Small, but it is a real change to a published package.

## Out of scope
- **The game itself**, and any knowledge of tiles, monsters, paths or quests. The game's extension owns those.
- **Billing.** A realm subscription is a separate concern. See dependencies.
- **Anti-cheat and server-side validation of game rules.** Kempo can authenticate and rate-limit; deciding that a move or a hit is legal is the game's job, and matters mainly for PvP.
- **Binary protocols.** JSON frames are enough for 20 players at 20 Hz; revisit only if measurement says otherwise.
- **Voice, and relayed peer-to-peer (WebRTC) transport.**

## Dependencies and sequencing
- **Task 0003 (realtime channels)** must be merged and released first. Rooms build on its authenticated socket route, session re-checking and browser client. At the time of writing 0003 is complete on its branch and not yet merged.
- **The paid realm needs recurring billing, which does not exist.** kempo-payments handles Stripe payment intents; a subscription product (charge monthly, and lapse gracefully) is a separate piece of work. Kempo's established pattern for paid access is **the permission is the entitlement**: a permission (through a group) says a user may open or keep a realm, and whatever handles billing grants or revokes it. That keeps this task free of any billing dependency: it only needs the hook in the criteria above, and a lapsed subscription should stop a realm without destroying its saved world, the same "lapse without deleting" seam kempo-user-dirs uses.
- **Follow-up tasks after this one:** (a) the game's own extension: worlds, invites, host and realm modes, persistence, and its simulation core; (b) realm subscriptions on top of payments.

## Open questions
- **Where the host-authoritative simulation runs is the game author's call**, but it drives the design above. Confirm with the friend that a simulation core separated from rendering is acceptable, since realms depend on it.
- **When a free world's host leaves, what happens?** The world ends, the host's browser saves it locally, or it is saved to the server. This affects whether free worlds need any server storage at all.
- **Realm capacity.** How many realms one server should run, which sets when several processes (and room ownership across them) actually matter.
- **How players find each other:** an invite link, a friends list, or a public list of joinable worlds.
- **PvP:** confirm it is a later phase. It changes the trust model, since the server would then have to arbitrate rather than relay.
