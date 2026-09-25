---
title: fix-rescan-listener-leak
description: onRescan registers a listener on a module-level singleton emitter and never removes it, so every router built in one process leaks a listener and one rescan() fans out to all of them
repos: kempo-server
status: implemented on the 0001 branch, awaiting validation
created: 2026-09-25
owner: TBD
qa: TBD
branches: {}
prs: {}
---

# fix-rescan-listener-leak

## Description
`src/rescan.js` holds a single module-level `EventEmitter`. `onRescan(callback)` does `emitter.on('rescan', callback)` and there is no way to undo it. `src/router.js` calls `onRescan(...)` once per `router()` call, so every router constructed in a process adds a listener that lives until the process dies.

Two consequences, one cosmetic and one not:

1. **Listener accumulation.** Past ten routers, Node prints `MaxListenersExceededWarning: Possible EventEmitter memory leak detected. 11 rescan listeners added`. Noise, but it is the symptom pointing at the real problem.

2. **Every rescan fans out to every router.** Because the emitter is a singleton and listeners are never removed, one `rescan()` call runs a full `getFiles` directory scan for *each* registered router, including routers whose server has long since closed. The `done` callback is then invoked once per listener, but `rescan()` wraps it in a promise, so it resolves on whichever router answers first and silently discards the rest. A caller asking "how many files are there now?" gets an answer from an arbitrary router, not necessarily its own.

**Impact is low in production and real everywhere else.** A normal deployment builds one router per process, so nothing above ever triggers. It bites when several servers share a process: the test suite (which is how this surfaced), anything embedding kempo-server, and any future multi-root setup.

**This is pre-existing and was not introduced by the WebSocket work** (task 0001). That task's tests create many routers in one process, which is what made the warning visible. `onRescan` has been called from `router.js` since well before it.

## Acceptance Criteria
- [ ] {Creating many routers in one process no longer accumulates listeners or prints MaxListenersExceededWarning}
- [ ] {A router stops responding to rescan once its server is closed, rather than scanning on behalf of a dead server}
- [ ] {Decide and document what `rescan()` means when several routers exist: does it target one, return per-router counts, or stay process-wide? The current behaviour of "resolve with whichever answers first" is not a defensible contract either way}
- [ ] {Existing rescan tests pass unchanged, and a new test covers the many-routers-in-one-process case}
- [ ] {UTILS.md and llms.txt updated if the `rescan` / `onRescan` signature changes}

## Repos Involved
- **kempo-server** — `src/rescan.js`, `src/router.js` (the `onRescan` registration around line 170), plus tests and docs.

## Notes
Likely shapes for a fix, to be settled at refinement:
- Have `onRescan` return a disposer function, and have `router()` expose it (e.g. on the returned handler) so an embedder or test can release it.
- Or hang the emitter off the router/server instance rather than module scope, which also fixes the fan-out, but changes what the exported `rescan()` means for existing consumers.
- Or keep the singleton and have the router unregister on the server's `close` event, which is the smallest change but only helps servers that are closed properly.

Watch for the same consideration that applied in task 0001: kempo-server can appear more than once in a resolved dependency tree (symlinked in local dev, or hoisted plus nested), so module-level state is per-copy. Any redesign should be explicit about whether rescan is meant to be process-wide across copies or scoped to one server.

`rescan` is a published export (`kempo-server/rescan`) and is documented in UTILS.md and README, so a signature change is a breaking change for consumers and should be weighed against the low production impact.

## Implemented (2026-09-25, on branch `0001_add-websockets-to-kempo-server`)
Done as part of the 0001 branch rather than separately, because the bug was making the suite flaky: once more than ten routers existed in the process, `rescan()` in the full test run resolved with a dead router's 0 and failed a test, deterministically (14 routers registered, the first 11 answers were 0).
- A router unregisters when its server closes. It learns its server from the first request or upgrade it sees. `router()`'s handler also exposes `dispose()` for embedders whose server never receives one.
- `rescan()` now waits for every registered router and resolves with the **largest** count, instead of the first to answer. With one router (every normal deployment) nothing changes. It rejects only if every router failed, and resolves 0 when none are registered.
- This also removes the `MaxListenersExceededWarning`.
- The three fix shapes listed above were not used as written: no signature change to the exported `rescan()`, so it is not a breaking change. `onRescan` (internal) now returns a disposer.
- Regression tests cover unregister-on-close, `dispose()`, largest-count-wins, error handling and the empty case; mutation-checked.
- Still open: with several *live* servers in one process, `rescan()` rescans all of them and returns only the largest count. That is documented in UTILS.md; a per-server rescan would need an API change.
