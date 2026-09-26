# Claude Task Management Configuration

Configuration and guidelines for working with the collaborative task management system.

## Running Skills from Any Repo

You can run the `/task-*` skills from **any workspace**. 

**It just works:**
- Open Claude Code in any repo
- Type `/task-create`, `/task-refine`, `/task-do`, or `/task-validate`
- On first use in a new workspace, Claude will confirm the tasks repo path
- Tasks are created/updated in your central tasks repo

**No setup needed.** The skills handle everything automatically.

## Overview

This repo uses a state-based task management system where:
- Tasks are markdown files in numbered state directories
- File naming: `NNNN_taskname.md` (e.g., `0001_add-auth`)
- States: `0 idea` → `1 ready` → `2 in progress` → `3 completed`
- Each task tracks involved repos, branches, and PRs

## Skills

Four skills manage the task lifecycle:

### `/task-create`
**Create a new task** in "0 idea" state

- Prompt for task name (kebab-case)
- Prompt for description
- Prompt for affected repos (comma-separated)
- Auto-generate next task ID (0001, 0002, etc.)
- Create markdown file with template
- Show confirmation with full task file path

### `/task-refine`
**Refine task from "0 idea" → "1 ready"**

- List all tasks in "0 idea" directory
- Let user select by task ID
- Read and display current task content
- Ask what needs refinement
- Edit collaboratively:
  - Flesh out description
  - Define acceptance criteria (checklist format)
  - Confirm repos list
  - Add implementation notes if needed
- After refinement:
  - Ask user: "Ready to move to '1 ready' state? (Y/N)"
  - On Y: Update status field, move file to "1 ready" directory
  - On N: Keep in "0 idea" and ask what else needs work

### `/task-do`
**Do a task: "1 ready" → "2 in progress", and then actually build it**

- Take the task ID (or list "1 ready" and "2 in progress"); a task already in progress is resumed
- Read the task and each repo's AGENTS.md/CLAUDE.md, then for EACH repo, without asking:
  - Get it onto its default branch, up to date, and create/checkout `NNNN_taskname`
  - A repo the task calls new is created locally only; remote repos are never created unasked
  - Open a draft PR (repos with a remote, after the first push) and record the URL
- Update the task's `branches` and `prs`, move it to "2 in progress", commit and push the tasks repo
- **Implement every acceptance criterion**: tests (mutation-checked), full suite, real-browser or real-server verification, docs, commits and pushed branches
- Tick criteria only when built and verified; keep implementation notes in the task file
- Stop before merging to `main`/`master`, releasing/publishing, creating remote repos or deleting anything
- Report per criterion (done and verified, unverified, or left undone and why), branches, PRs, and the next step (`/task-validate`)

### `/task-validate`
**Complete task from "2 in progress" → "3 completed"**

- List all tasks in "2 in progress" directory
- Let user select by task ID
- Read task metadata (branches and prs)
- For EACH repo with a PR:
  - Check PR status via GitHub API or git branch
  - Report: [Repo] {branch} → PR #{number} [{status}]
    - Status: Draft, Open, Ready to Merge, Merged
  - Ask: "Is this ready to merge/already merged? (Y/N)"
- Verify acceptance criteria from task description:
  - Ask user for each criterion: "Satisfied? (Y/N)"
- Consolidation:
  - Ask: "Add completion notes? (optional)"
  - Update task file with completed date and any notes
- Move task to "3 completed" directory
- Show summary: task completed, all PRs status, link to merged PRs

## Task File Template

When creating a task, use this structure:

```markdown
---
title: {Task Name}
description: {One-line description}
repos: {repo1},{repo2}
status: {state name}
created: {YYYY-MM-DD}
branches: {}
prs: {}
---

# {Task Name}

## Description
{Detailed description of work needed}

## Acceptance Criteria
- [ ] {Criterion 1}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

## Repos Involved
- {repo1}
- {repo2}

## Notes
{Any additional context or requirements}
```

Fields to maintain:
- `status`: Matches directory state (idea, ready, in-progress, completed)
- `branches`: Map of repo → branch name
- `prs`: Map of repo → PR URL
- Acceptance criteria: Use checklist format for easy verification

## Interaction Patterns

### When User Reviews

Always ask for approval before state transitions:
```
Task refined. Ready to move to "1 ready"? (Y/N)
```

Never force a state transition without asking. (`/task-do` is the exception for starting: choosing to run it is the go-ahead to begin and to do the work.)

### When Creating Branches

`/task-do` creates the branch in each repo without asking; the task's repo list is the decision. It does not merge, release or create remote repositories without an explicit go-ahead.

### When Reporting Status

Be specific and actionable:
```
Task 0001: add-auth
├─ api-server: branch 0001_add-auth → PR #42 [Ready to Merge]
├─ web-client: branch 0001_add-auth → PR #15 [Merged] ✓
└─ Action: Merge api-server PR, then complete task
```

## Error Handling

- If task file doesn't exist: ask user if they want to create it
- If branch already exists: ask if user wants to checkout or create a new branch
- If PR creation fails: continue with manual PR option, don't block
- If repo path invalid: ask user for correct path to repo

## Cross-Session Continuity

Task metadata persists in markdown files, so:
- You can resume any incomplete task
- All branch/PR info is preserved
- Acceptance criteria status is tracked
- No state is lost between sessions

When resuming work: read task file first to understand current state.

## Git Operations

All git operations use bash/PowerShell native commands:
- Create branch: `git checkout -b NNNN_taskname`
- Check status: `git branch -a` or `git status`
- Create PR: via GitHub CLI `gh pr create` or GitHub web UI
- Track PR: store URL in task metadata

## Future Enhancements

Possible additions (not yet implemented):
- Task dependencies
- Task time estimation
- Automatic PR status polling
- Integration with GitHub issues
- Task filtering/search
