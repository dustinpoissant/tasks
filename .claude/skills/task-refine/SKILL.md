---
name: task-refine
description: Refine a task from "0 idea" state to "1 ready" state. Use this when the user wants to flesh out requirements, acceptance criteria, and scope for a task before starting work. Validates all fields are complete before moving to ready.
---

# Refine and Ready a Task

When the user wants to refine a task:

1. **List tasks** in "0 idea" directory
2. **Select task** — Let user choose by ID
3. **Review current content** — Display the task file
4. **Refine details**:
   - Flesh out description with requirements
   - Define clear acceptance criteria (checklist format)
   - Confirm all repos involved
   - Add implementation notes if needed
5. **Validate** — Ensure all required fields complete
6. **Move to 1 ready** — Relocate file and update status
7. **Get approval** — Ask user before finalizing

## Template

All tasks use the `_template.md` file from the tasks repo. During refinement, fill in sections including:
- Owner — Who is handling this task
- QA — Who will verify it when done

To customize sections for all future tasks, edit `_template.md`.

## Running from Any Repo

This skill auto-detects the tasks repo location and works from any dev's machine:

1. Look for `TASKS_REPO_PATH` environment variable
2. Search for `.claude/.tasks-root` marker file in parent directories  
3. Search common locations: `~/dev/tasks`, `~/projects/tasks`, `~/tasks`
4. Look for directory with state folders: `0 idea/`, `1 ready/`, `2 in progress/`, `3 completed/`
5. Ask user if not found

**Result:** Works out-of-the-box for any dev who clones this repo. No setup needed.

## State Transitions

Task moves from **0 idea** → **1 ready** → Next use /task-do to start work.
