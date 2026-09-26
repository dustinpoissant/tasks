---
title: add-game-extension
description: Create kempo-game, a generic kempo (CMS) extension that gives future games saved games with invited players, settings and state, a live multiplayer sync layer on kempo's realtime WebSockets, periodic and on-demand saves, a backend SDK, hooks and a frontend SDK, proven by a tiny tic-tac-toe game in its own extension
repos: kempo-game (new), kempo-tic-tac-toe (new), kempo
status: in progress
created: 2026-09-26
owner: Dustin
qa: Dustin
branches:
  kempo: 0004_add-game-extension
  kempo-game: 0004_add-game-extension
  kempo-tic-tac-toe: 0004_add-game-extension
prs: {}
---

# add-game-extension

## Description
Kempo core now ships a generic realtime layer (kempo 4.3.0 on kempo-server 3.5.0). This task builds the first kempo (CMS) extension on it: **kempo-game**, a generic layer that a real game is built on top of. It is **not a game**. It contains no rules, no board, no map, nothing about tic-tac-toe or blocks or combat. It gives a game developer the parts every multiplayer game needs, so the game is only its own rules and its own UI.

What kempo-game provides:
- **A "game"** is a saved record: a name, a type, an owner, settings, and a state. It can have one player (a saved single-player game) or many (the owner invites other users, who accept or decline).
- **Two kinds of data, kept apart on purpose.** `state` is what gets saved (a JSON document, as large as the game needs). `live` is what changes many times a second, such as player positions, and is **never written to the database** on its own. A game may choose to fold parts of `live` into what it saves.
- **A live connection** between the players' browsers, on a realtime channel, that carries inputs from clients and changes to `state` and `live` back out.
- **Saving:** automatic on an interval (default 30 seconds, only when something changed), on demand ("Save" button or SDK call), and when the last player leaves.
- **A backend SDK** other kempo (CMS) extensions call, **hooks** they can react to, and a **frontend SDK** for their browser code.

The proof is a separate, deliberately tiny **kempo-tic-tac-toe** extension that depends on kempo-game and contains only the rules and a board. The long-term target is a real-time 2D block game with player interactions, world editing, statuses, attacks and levels (a friend is building one on a canvas); that game is **not** built here, but this layer must not need redesigning to carry it.

## Design decisions
**Stated by the owner (2026-09-26):**
1. kempo-game is a generic layer, not a game, and a game is its own extension that depends on it.
2. A game can be single-player or have many players invited by its owner.
3. There is a realtime channel for constant communication between clients.
4. Fast-changing data (positions and the like) is **not** saved to the database on every change. It is saved on an interval (about 30 seconds), on demand, or at the moments below.
5. A game carries settings and generic data, even if that is one large JSON object.
6. Needs a backend SDK, hooks and a frontend SDK.
7. First test game is tic-tac-toe, in its own extension.

**Defaults chosen during refinement (please veto any you disagree with):**
- **The server is authoritative.** A game type supplies a module that decides what an input does; clients never write `state` directly. It is safer against cheating and is what core's handler model fits. A game that wants a relay (clients trust each other) can write a module that accepts and re-emits inputs as they are.
- **A game type is declared, not registered in code.** The game extension's `kempo-config.json` names its type and its module (`"game": { "types": [{ "name": "tic-tac-toe", "module": "./game.js", "minPlayers": 2, "maxPlayers": 2, "tickRate": 0 }] }`), and kempo-game reads that from the extension table, the way core reads declared channels. This has no load-order problem, since an imperative registration in an extension's module could run after the first player connects.
- **Two synced trees, patched.** `state` and `live` are each synced as a JSON Merge Patch (RFC 7386) batched per tick, with a version number, plus a full snapshot when a player joins or asks to resync. A client that sees a version gap asks for a snapshot. A game type that would rather send its own events can, since the module can also emit messages directly.
- **Ticks are optional.** `tickRate: 0` (tic-tac-toe) means the game reacts to inputs only and patches go out immediately. A positive rate runs a fixed-rate loop, calls the module's `onTick`, and flushes one batched patch per tick. The loop runs only while a game has live players.
- **Each live game has its own realtime channel** (one channel per game, with `scope: "process"`, meaning it delivers in memory on the server hosting the game and never through Postgres; nothing is spawned), registered in code when the game goes live and removed when it ends, with `authorize` checking the caller is a joined player and `onMessage` bound to that game. Core's process scope is what makes 20 updates a second per player affordable (no Postgres), and the channel lives only on the process hosting the game, so a subscribe to it anywhere else is refused, which is correct. This needs one small change in core: `unregisterChannel` is not in the SDK yet (see below).
- **Roles are per game.** One `owner` (the creator), the rest `player`. The owner invites, removes players, changes settings, and can delete the game. The owner cannot leave without first transferring ownership or deleting the game. Everyone joined can send inputs; the game type's module can restrict what a given role or player may do.
- **Saving is compare-and-swap on a version.** Each save writes `state` only if `stateVersion` is what this process last read, then increments it. A save that finds a different version means another process has been hosting the same game; this session stops, tells its players, and they rejoin. It is a safety net, not multi-process support.
- **One process hosts a game at a time.** Because process-scoped channels do not cross processes, everyone in a game must reach the same process. With several processes that means sticky routing by game id at the load balancer. v1 documents this and does not solve it.
- **Access is by permission plus membership.** `game:play` (create games, accept invitations, join), `game:admin` (see and delete any game, from the admin page). Membership in a specific game is a row, checked on every join, subscribe and input. Groups: `kempo-game:player` and `kempo-game:administrator`.

## What core already provides (so kempo-game does not rebuild it)
Channels behind a permission or an `authorize` function; `scope: "process"` in-memory delivery with `dropIfBackedUp`; `onMessage` handlers, ordered per connection, with acks and `{ code, msg }` errors; lifecycle hooks (`realtime:connected`, `disconnected`, `subscribed`, `unsubscribed`, and the `before_subscribe` guard); `publish`, `sendToConnection`, `closeConnection`, `listSubscribers`; per-user connection and per-connection message limits. Documented in kempo's `docs/realtime.md`.

**Constraints from core that shape the design**
- Hooks read the database on every call and run in order. They are for **lifecycle** (created, joined, saved), never for inputs or ticks. Per-input work happens in the game type's module, loaded once and held in memory.
- Process-scoped channels and connection functions only see the process they run on.
- A connection is limited to 100 messages a second and a user to 10 connections by default. Inputs at 20 a second are well inside that.

## Architecture
**Repo `kempo-game`** (follows kempo-files, kempo-thumbs and kempo-user-dirs: `kempo-config.json`, `install.js`/`update.js`/`uninstall.js`, `sdk.js` as `main`, `public/` scope, `admin/`, `hooks/`, `server/db/schema.js`, tests, docs, README, CHANGELOG, publish workflow; custom elements are `k-game-*`; its test database is a new one on its own port, 5440 unless taken).

**Tables** (declarative schema, created on install):
- `kempoGame`: `id`, `type` (`<extension>:<name>`), `name`, `ownerId`, `settings` jsonb, `state` jsonb, `stateVersion`, `createdAt`, `updatedAt`, `savedAt`.
- `kempoGamePlayer`: `gameId`, `userId`, `role` (`owner` | `player`), `status` (`invited` | `joined` | `declined`), `invitedBy`, `invitedAt`, `joinedAt`, `data` jsonb (per-player saved data such as level or inventory).

**Live session** (in memory, per hosted game): `state`, `live`, the joined players and their connections, a dirty flag, the pending patch, the tick timer, the autosave timer. Started on the first join, ended a short grace period after the last player leaves, after a final save.

**Game type module** (supplied by the game extension; every function optional):
`onCreate({ game })`, `onJoin({ session, player })`, `onLeave({ session, player })`, `onInput({ session, player, input })`, `onTick({ session, dt })`, `onSave({ session })` (may return extra data to fold into what is saved, for example part of `live`), `onLoad({ game })`. It changes the session with `session.state`, `session.live` and `session.players[userId].data` (changes are detected and turned into patches), can reject an input by throwing `{ code, msg }`, and can send an event to one player or all. It never touches sockets.

**Backend SDK** (`kempo-game/sdk`, error-tuple style like the rest of kempo): `createGame`, `getGame`, `listGames({ userId })`, `updateSettings`, `invitePlayer`, `acceptInvite`, `declineInvite`, `removePlayer`, `leaveGame`, `transferOwnership`, `deleteGame`, `saveGame`, and `getSession` (the live session of a game this process hosts).

**Hooks** fired by kempo-game for other extensions: `game:created`, `game:deleted`, `game:player_invited`, `game:player_joined`, `game:player_left`, `game:started` (session went live), `game:ended` (session ended), `game:saved`, and the guards `game:before_join` and `game:before_save` (throw `{ code, msg }` to refuse). Lifecycle only.

**Frontend SDK** (`public/sdk.js` and a browser module): list my games and invitations, create, invite, accept, decline, and `join(gameId)`, which returns a connection with the current `state` and `live`, `send(input)`, `save()`, `onState`, `onLive`, `onPlayerJoined`/`onPlayerLeft`, `onEvent`, and a connection status, built on `/kempo/realtime.js`. Plus a small game-agnostic lobby component (`k-game-lobby`: my games, create, invitations, invite by email) so a game does not have to build one, in kempo-css utilities and `<k-icon>`.

**Admin:** a page listing all games (type, owner, players, last saved, whether hosted right now) with delete, gated by `game:admin`.

**Repo `kempo-tic-tac-toe`:** depends on kempo-game (`"dependencies": ["kempo-game"]`). Declares one game type and ships the rules module (turn order, legal cell, win and draw detection) and a board page. Nothing in kempo-game may mention it.

**Repo `kempo`:** export `unregisterChannel` from the realtime SDK and document dynamic per-session registration of process channels. Kept to that, and as its own change and release, unless the work finds something else missing.

## Acceptance Criteria
**Games and players**
- [ ] Create a game of a declared type with a name, settings and an initial state (from the type's `onCreate`). The creator is the owner and a joined player. A game of one player needs no invitations.
- [ ] The owner invites users; an invitee can accept or decline; the owner can remove a player; a player can leave; the owner must transfer ownership or delete the game rather than leave. Player limits from the type (`minPlayers`, `maxPlayers`) are enforced.
- [ ] Every action is authorized by permission and by membership of that game. Someone who is not in a game cannot read its state, join its channel or send it input, and a test proves it.
- [ ] Settings and state are saved as JSON with no fixed shape, with a documented size limit that returns a clear error tuple instead of failing.

**Live sync**
- [ ] Joining a live game returns a snapshot of `state` and `live`, then patches. A client that misses a version gets a fresh snapshot. State and live always end up identical on every client.
- [ ] Inputs go through the type's module. An input from someone who is not a joined player, or one the module rejects, changes nothing and returns an error to that sender only.
- [ ] A game with a tick rate runs a fixed-rate loop only while players are present, batches one patch per tick, and uses `dropIfBackedUp` for `live` patches so a slow client falls behind rather than exhausting memory.
- [ ] A disconnect is noticed through core's lifecycle hook and the player is marked away; a player who does not come back is removed only if the type says so. A reconnecting player gets a snapshot.

**Saving**
- [ ] `live` is never written to the database by the sync path. A test drives many updates a second and shows zero writes for them.
- [ ] Autosave runs on the configured interval (default 30 seconds, a setting, per-type override, 0 disables), only when `state` or a player's `data` changed. `saveGame` saves on demand. The last player leaving saves and ends the session.
- [ ] A save is compare-and-swap on `stateVersion`; a stale writer is refused, its session ends, and its players are told.
- [ ] `onSave` may fold parts of `live` into what is saved, and `onLoad` restores them, so a game can persist positions if it wants to.
- [ ] Restarting the server and rejoining restores the last saved state. What was lost since the last save is exactly what the documentation says.

**SDKs, hooks, admin**
- [ ] The backend SDK, hooks and frontend SDK above exist, are documented with an example each, and use error tuples.
- [ ] Hooks fire with the documented data and never on the input or tick path.
- [ ] The lobby component and the admin page work in a real browser and follow AGENTS.md (kempo-css utilities, `<k-icon>`, no custom CSS).

**Proof**
- [ ] **kempo-tic-tac-toe** is a separate extension, installed through kempo's real extension install path from packages installed into a clean project. Two browsers sign in as two users, one invites the other, they play a full game to a win and to a draw, an illegal move is refused, closing and reopening a browser resumes the game, and a server restart restores the board. Verified in a real browser.
- [ ] **A built-in test game, "click race"** (in kempo-game's tests, never shipped; see Test fixture below) exercises the whole layer with two real WebSocket clients: it proves live sync, that `live` is never saved, the timed save, the win, and that a stranger is refused.
- [ ] **A capacity test** reusing the same click-race type with 20 players and an unreachable target: each player sends 20 clicks a second, and it records tick and delivery latency and the number of database writes (which stays at the autosave rate). It also runs several games at once, so the figure covers a single VPS hosting many games and not only one. The figures go in the docs with the same caveats as core's.
- [ ] **Mutation-checked** tests: each of the properties above (membership enforced, patches converge, live not saved, autosave only when dirty, CAS refusal) fails when the code that provides it is removed.

**Quality and delivery**
- [ ] DB-backed suites actually run (no `(SKIPPED)`) on kempo-game's own test database.
- [ ] Docs and README in both new repos; kempo's `docs/realtime.md` gains the dynamic-channel note.
- [ ] Released through each repo's normal process: kempo-game, kempo-tic-tac-toe, and the kempo minor for `unregisterChannel`, in that dependency order.

## Test fixture: click race
A deliberately tiny game type that lives in kempo-game's tests, installed through the same declared-type path a real game extension uses, so the tests exercise the real thing and not a shortcut. It is not shipped in the package.

- **Rules:** two players each click as fast as they can; the first to reach 100 wins. Each player sees their own score and their opponent's.
- **Data split:** the scores are `live` (they change many times a second and are never written to the database). The result (`status: "finished"`, `winner`) is `state`, which is saved.
- **Type settings:** `minPlayers` 2, `maxPlayers` 2, a `target` of 100 (a setting on the game, so the capacity test can make it unreachable), `tickRate` 20 so patches are batched, and a short per-type autosave interval so the tests do not sit for 10 seconds (the default and the 10 to 30 second range are covered by a test that injects a clock).
- **Input:** `{ type: "click" }`. The module increments the sender's score, and at the target sets the result and rejects every later click with a `409`.
- **What the tests assert, with real clients:**
  - Two clients sign in as two users, one creates a game and invites the other, who accepts; both join.
  - Both click at machine speed. The winner is exactly the first to reach the target, no score ever exceeds it, and after the last patch both clients hold identical `state` and `live`.
  - Each client's view of the opponent's score matches the server's.
  - While the race runs, the game's row in the database is untouched (`stateVersion` and `savedAt` do not change); only after the win does the timed save write the result, once.
  - A click after the win is refused; a click from a user who is not in the game is refused and changes nothing; a third user cannot join or subscribe.
  - Killing a client mid-race is noticed, and it gets a fresh snapshot on return.
  - Restarting the server mid-race loses only the scores (they were `live`); restarting after the win keeps the result.
- **A real-browser run** of the same game uses an actual button, to confirm the frontend SDK works outside Node.

## Repos Involved
- **kempo-game** (new): the layer.
- **kempo-tic-tac-toe** (new): the proof game.
- **kempo**: export `unregisterChannel` and the docs note only.

## Out of scope
- **Any real game.** The block game, its world format, combat, levels and canvas rendering belong to their own extension.
- **Several processes hosting one game.** v1 needs sticky routing and says so. A shared lease or handing a game between processes is future work.
- **Lag compensation, client-side prediction, interpolation.** A game does those in its own client code.
- **Matchmaking, public game lists, spectators, chat.** Chat is a channel a game or another extension can add.
- **Monetization** (paid persistent realms, subscriptions): a seam for kempo-payments and kempo-commerce later. This task leaves the permission checks where a paywall would sit and builds no billing.
- **Save history, undo or branching.** One current state per game.
- **Redis or any broker,** and any change to how kempo core's realtime layer itself works.

## Notes
- Write "kempo (CMS) extension", not a bare "the extension".
- **Why `live` and `state` are separate:** a game's positions change 20 times a second per player and must not touch the database; its world and progress change rarely and must survive a restart. Keeping them apart in the model, not just in the game's code, is what makes the 30-second save safe.
- **Why per-game channels are registered in code:** the channels are created and destroyed as games start and end, which a static declaration cannot describe. That is safe for a `process`-scoped channel because it only ever needs to exist on the process hosting the game, and the join request registers it before the client subscribes. Core's docs warn against registering channels outside startup for channels that other processes must resolve; that warning does not apply to a channel that only exists on one process.
- **Fallback if that proves awkward:** one declared channel for the whole extension with the extension fanning out to each game's players using `sendToConnection`. It works with today's core but every game shares one channel's subscriber list, so it is the second choice.
- Hooks are DB-backed and run in order; keep them off the input path (see `kempo/spec/concepts/realtime.md`).
- Test databases are per repo; never point a suite at kempo-demo's database, and never run one repo's `drizzle-kit push` against another's database.
- Read `kempo/docs/realtime.md` and the sibling extensions (kempo-files, kempo-user-dirs) before starting, and follow their layout.
