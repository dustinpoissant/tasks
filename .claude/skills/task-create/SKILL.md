---
name: task-create
description: Quickly capture a new task idea in the "0 idea" state. Use this to dump rough, unrefined ideas without fleshing them out. Ask for task name and a quick idea, then create the file. Perfect for capturing ideas you'll refine later.
---

# Quick Capture Task Idea

When the user wants to capture a rough idea:

1. **Get task name** — Ask for a kebab-case name (e.g., `add-auth`, `fix-memory-leak`)
2. **Review conversation context** — Look back at recent conversation for context about WHY this feature is needed
3. **Extract key details** — If context exists, intelligently extract:
   - Why it's needed (the "why" from discussion)
   - Initial acceptance criteria based on what was discussed
   - Any specific technical details or requirements mentioned
4. **Get repos** — Ask which repos this might touch (or "unknown" if unsure)
5. **Find next number** — Auto-increment task ID (0001, 0002, etc.)
6. **Create file** — Create markdown with extracted details plus template placeholders for refinement
7. **Ask to commit** — "Commit this task to git? (Y/N)"

**Key principle:** Capture what's already known from context without requiring a full refinement pass. Leave room for detailed refinement later.

## File Format

Uses the `_template.md` file from the tasks repo. Fill in placeholders:
- `{TASK_TITLE}` — The task name
- `{TASK_DESCRIPTION}` — One-line idea
- `{REPOS}` — Comma-separated repos (or "unknown")
- `{STATUS}` — "idea"
- `{CREATED_DATE}` — Today's date
- `{OWNER}` — Who is handling this task (optional, can be "TBD")
- `{QA}` — Who will QA/verify this task (optional, can be "TBD")
- Leave other sections as template placeholders

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

Task starts in **0 idea** → Later: `/task-refine` to move to **1 ready**.
