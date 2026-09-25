---
name: task-validate
description: Complete a task by moving it from "2 in progress" to "3 completed" state. Use this when the user has finished work. Checks PR statuses, verifies acceptance criteria are met, records merge information, and marks the task as complete.
---

# Validate and Complete Task

When the user wants to complete a task:

1. **List tasks** in "2 in progress" directory
2. **Select task** — Let user choose by ID
3. **Check PR statuses**:
   - For each repo with a PR
   - Query current status (Draft/Open/Ready/Merged)
   - Ask user: merged or ready to merge? (Y/N)
4. **Verify criteria**:
   - Read acceptance criteria from task
   - For each criterion, ask: satisfied? (Y/N)
5. **Consolidate info**:
   - Ask for optional completion notes
   - Update task with completed date
   - Record PR merge information
6. **Move to 3 completed** — Relocate file, update status
7. **Show summary** — Task completed, PRs status, links

## Template

All tasks use the `_template.md` file from the tasks repo. Completion info is tracked in the frontmatter and notes section. Owner and QA fields show who was responsible. To customize sections, edit `_template.md`.

## Running from Any Repo

This skill auto-detects the tasks repo location and works from any dev's machine:

1. Look for `TASKS_REPO_PATH` environment variable
2. Search for `.claude/.tasks-root` marker file in parent directories  
3. Search common locations: `~/dev/tasks`, `~/projects/tasks`, `~/tasks`
4. Look for directory with state folders: `0 idea/`, `1 ready/`, `2 in progress/`, `3 completed/`
5. Ask user if not found

**Result:** Works out-of-the-box for any dev who clones this repo. No setup needed.

## State Transitions

Task moves from **2 in progress** → **3 completed** ✓ Task Done
