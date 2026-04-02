# Autonomous Build Iteration

You are building a project from a specification. This is one iteration of an
autonomous loop — you have fresh context and NO MEMORY of prior iterations.
Everything you need to know about prior work is in files. Read them first.

## BEFORE DOING ANYTHING: Read state files

You MUST read these files before taking any action. Without them, you will redo
work that prior iterations already completed, or miss context about what failed.

1. **Progress log**: Read `{{PROJECT_DIR}}/progress.txt` FIRST — this tells you
   what prior iterations did, what passed, what failed, and what's blocked.
2. **Task list**: Read `{{PROJECT_DIR}}/tasks.json` — current status of each task.
3. **Tests**: Read files in `{{PROJECT_DIR}}/tests/` — the acceptance criteria.
4. **Manifest**: Read `{{PROJECT_DIR}}/tests/manifest.json` — test metadata including
   which tests are `"deferred": true` (dependencies unavailable in this environment).
5. **Environment**: If `{{PROJECT_DIR}}/env_available.json` exists, read it — this
   tells you what infrastructure is available (postgresql, docker, npm, etc.).
6. **Spec**: Read `{{SPEC_PATH}}` — the full specification (reference as needed).
7. **Existing code**: Scan `{{PROJECT_DIR}}/src/` or other code directories.

## What to do

### If this is the first iteration (progress.txt is empty or doesn't exist):
1. Read the spec and all test scripts
2. Decompose the spec into ordered tasks — write to `{{PROJECT_DIR}}/tasks.json`:
   ```json
   [
     {"id": 1, "step": "Step 1", "description": "...", "status": "pending", "depends_on": []},
     {"id": 2, "step": "Step 2", "description": "...", "status": "pending", "depends_on": [1]}
   ]
   ```
3. Align tasks with tests — each task should have corresponding test(s).
   If a test has `"step": "end_to_end"` in the manifest, create a task for it that
   `depends_on` ALL module-level tasks. This task wires modules together and runs
   last — after every individual module passes its own tests.
4. Start building task 1

### If this is a subsequent iteration:
1. Read progress.txt — understand what was done and what failed
2. Read tasks.json — find the next pending task (or a failed one to retry)
3. Build/fix that task
4. Run the relevant test(s)

## How to build

- Write code in `{{PROJECT_DIR}}/src/` (or wherever the spec implies)
- Keep changes focused — one task per iteration
- Run the relevant test after building: `python {{PROJECT_DIR}}/tests/test_stepN.py`
- If the test passes: mark the task as "done" in tasks.json
- If the test fails: read the error, try to fix. If stuck after 2 attempts, mark
  the task as "blocked" with the error message and move on
- If `manifest.json` has a `platform_deps` array, `pip install` each one on the
  first iteration. These are libraries the spec requires you to USE, not just
  install — build with them as the spec intended. Tests will verify actual usage.

## How to update progress

Append to `{{PROJECT_DIR}}/progress.txt`:

```
=== Iteration N (YYYY-MM-DD HH:MM) ===
Task: [task id and description]
Action: [what you did]
Test result: [PASS/FAIL + details]
Files changed: [list]
Status: [done/blocked/in_progress]
```

## How to update tasks.json

Update the status field of the task you worked on:
- `"done"` — test passes
- `"blocked"` — can't fix after retrying, include error in a "blocker" field
- `"in_progress"` — partially done, more work needed next iteration

## Completion check

After updating progress, check: are all **non-deferred** tasks "done"?
- Read tasks.json and manifest.json
- Skip tests marked `"deferred": true` in the manifest — their dependencies aren't
  available in this environment. Don't try to install missing infrastructure.
- Run all non-deferred tests — this includes `end_to_end` tests. All tests in the
  manifest (code, build, integration, end_to_end) must pass for COMPLETE. An
  end_to_end test that fails means modules aren't wired together yet, even if every
  individual module test passes.
- If all non-deferred tests pass: output `<promise>COMPLETE</promise>`
- If any non-deferred test fails or any non-deferred task not done: just exit
  normally (the loop will start a new iteration with fresh context)

## Rules

- One task per iteration. Don't try to do everything at once.
- If a task depends on another that isn't done yet, skip it and pick a different one.
- If all remaining **non-deferred** tasks are blocked, output `<promise>BLOCKED</promise>`
  with a summary of what's stuck. Deferred tasks don't count — they were excluded
  before the loop started because their dependencies aren't available.
- Don't modify files in `tests/` — those are the approved acceptance criteria.
- Read the spec carefully. The tests encode the spec's acceptance criteria. If your
  code passes the tests, it satisfies the spec.
- If `.env` or API credentials exist in the project directory, use real API endpoints.
  Do not mock APIs that the spec defines with concrete endpoints when credentials
  are available. Mock data hides integration failures that only surface with real APIs.
- If the spec names specific API endpoints (URLs, methods, parameters), implement
  actual HTTP calls to those endpoints — not simulated responses.
