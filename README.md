# Collaborative Task Management System

A lightweight, git-integrated task management system designed for collaborative work with Claude. All tasks are tracked as markdown files and organized by state.

## Task States

Tasks flow through four states, each represented by a directory:

1. **`0 idea`** - New, unrefined tasks
2. **`1 ready`** - Refined and ready to start
3. **`2 in progress`** - Active work with branches/PRs
4. **`3 completed`** - Finished and merged

## Task File Format

Each task is a markdown file named: `NNNN_taskname.md`

- `NNNN` - 4-digit number (0001, 0002, etc.)
- `taskname` - kebab-case task name (e.g., `add-auth`, `fix-bug-123`)

### Example: `0001_add-user-auth.md`

```markdown
---
title: Add User Authentication
description: Implement JWT-based auth system
repos: api-server,web-client
status: in-progress
created: 2026-09-24
branches:
  api-server: 0001_add-user-auth
  web-client: 0001_add-user-auth
prs:
  api-server: https://github.com/org/api-server/pull/42
  web-client: https://github.com/org/web-client/pull/15
---

# Add User Authentication

## Description
Implement a complete JWT-based authentication system across the API server and web client. This includes:
- JWT token generation and validation
- Login/logout endpoints
- Protected routes on frontend
- Session persistence

## Acceptance Criteria
- [ ] Login endpoint returns JWT token
- [ ] Protected API routes reject unauthenticated requests
- [ ] Web client stores and sends token in requests
- [ ] Logout clears session
- [ ] Tests cover happy path and error cases

## Repos Involved
- api-server
- web-client

## Notes
- Use HS256 for JWT signing
- Session expires after 7 days
- Store token in localStorage on frontend (with considerations for XSS)
```

## Skills

### `/task-create`
Creates a new task in the "0 idea" state.

```bash
/task-create
# Claude prompts for:
# - Task name
# - Description (optional)
# - Repos affected
# - Creates task file with auto-incremented number
```

### `/task-refine`
Refines a task from "0 idea" → "1 ready".

```bash
/task-refine
# Claude:
# - Lists tasks in "0 idea"
# - Guides refinement of description, criteria, scope
# - Validates all required fields complete
# - Moves to "1 ready"
```

### `/task-do`
Starts a task, moving from "1 ready" → "2 in progress".

```bash
/task-do
# Claude:
# - Lists tasks in "1 ready"
# - Creates branches (NNNN_taskname) in each repo
# - Creates PRs if desired
# - Updates task metadata with branch/PR info
# - Moves to "2 in progress"
```

### `/task-validate`
Completes a task, moving from "2 in progress" → "3 completed".

```bash
/task-validate
# Claude:
# - Lists tasks in "2 in progress"
# - Checks PR statuses
# - Verifies acceptance criteria met
# - Consolidates merge info
# - Moves to "3 completed"
```

## Workflow Example

```
1. Have an idea → /task-create
   Creates 0001_new-feature.md in "0 idea"

2. Ready to work → /task-refine
   Flesh out requirements, move to "1 ready"

3. Start implementation → /task-do
   Create branches, move to "2 in progress"

4. Finished and merged → /task-validate
   Check PRs, move to "3 completed"
```

## Branch Naming Convention

All branches created for a task must follow the pattern: **`NNNN_taskname`**

This makes it easy to:
- Track which task a branch belongs to
- Search branches by task ID
- Maintain consistency across repos

Example branches:
- `0001_add-user-auth`
- `0002_fix-memory-leak`
- `0003_improve-error-handling`

## PR Tracking

Each task file tracks PRs for all involved repos:

```yaml
prs:
  repo1: https://github.com/org/repo1/pull/123
  repo2: https://github.com/org/repo2/pull/456
```

When a task is completed, all PRs should be merged. The `/task-validate` skill will verify this.

## Working Collaboratively with Claude

Each skill is designed to be interactive:

1. Claude presents options and asks for confirmation
2. You can edit, modify, or reject Claude's suggestions
3. Tasks only move to the next state after your review
4. Claude tracks progress and maintains task metadata

Typical interaction:
```
You: /task-create
Claude: What's the task name?
You: add-user-auth
Claude: Which repos does this touch?
You: api-server,web-client
Claude: Here's your new task [0001_add-user-auth.md]. Ready to refine? (Y/N)
```

## Directory Structure

```
tasks/
├── 0 idea/              # New tasks, not yet refined
├── 1 ready/             # Ready to start
├── 2 in progress/       # Active work
├── 3 completed/         # Finished tasks
├── .claude/
│   ├── skills/          # Skill documentation
│   │   ├── task-create.md
│   │   ├── task-refine.md
│   │   ├── task-do.md
│   │   └── task-validate.md
│   └── scripts/         # Helper scripts
│       └── task-helpers.ps1
├── README.md            # This file
└── CLAUDE.md           # Claude-specific configuration
```

## Quick Start

1. **Create your first task**
   ```bash
   /task-create
   ```

2. **Refine it when ready**
   ```bash
   /task-refine
   ```

3. **Start work on it**
   ```bash
   /task-do
   ```

4. **Complete and validate**
   ```bash
   /task-validate
   ```

That's it! The system handles numbering, file management, branching, and state transitions.
