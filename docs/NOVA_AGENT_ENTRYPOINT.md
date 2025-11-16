This file gives standing orders for any automated agent working on this repository.

# Screaming Penguin — Agent Entry Point

This document defines standing instructions for any automated agent (code generation or refactoring) operating on this repository.

Agents must read and follow this document on **every run**.

---

## 1. Required Reading Before Changes

Before making any modifications, the agent must:

1. Read the following documents:
   - `docs/DESIGN_v0.md`
   - `docs/DEV_ROADMAP.md`
   - `docs/DEV_PHILOSOPHY.md`
   - `docs/SP_BIBLE.md`
2. Align planned changes with:
   - The v0 scope and architecture in `DESIGN_v0.md`.
   - The current milestone in `DEV_ROADMAP.md`.
   - The principles in `DEV_PHILOSOPHY.md`.

If a change does not clearly fit within the documented scope or philosophy, the agent should expect human review and potential revision of the docs before proceeding.

---

## 2. Bible Handling — Additive Only

`docs/SP_BIBLE.md` is a protected, additive-only document.

Agents must:

- **Never** overwrite, reorder, or delete existing content in `docs/SP_BIBLE.md`.
- Always add new entries **at the end** of the file.
- Use the following template for each new entry:

```markdown
## Entry NNN — <Short Title>

**Date:** YYYY-MM-DD

<2–5 sentences describing what changed and why. Reference key files or milestones if relevant.>

•Increment NNN monotonically (zero-padded to three digits).
•Use an ISO-formatted date (UTC or project-local, but consistent).
```

Unless explicitly instructed otherwise for a specific change, every pull request or significant agent-run should include a new Bible entry summarizing its impact.

⸻

3. Documentation Discipline

When behavior changes, documentation must be updated in the same change set:
•If runtime behavior or interfaces change:
•Update docs/DESIGN_v0.md or successors.
•If roadmap/milestones change:
•Update docs/DEV_ROADMAP.md.
•If guiding principles change:
•Update docs/DEV_PHILOSOPHY.md.
•Always keep examples and config schemas in sync with actual code.

Documentation changes should be verbatim and conform exactly to instructions in the human-authored prompt or review comments.

⸻

4. Scope and Safety Constraints

Agents must:
•Respect the v0 scope unless explicitly instructed to work on future milestones.
•Avoid introducing:
•New external dependencies without justification.
•Destructive behaviors without safety checks and tests.
•Prefer small, reviewable changes over broad refactors.

For destructive paths (partitioning, filesystem creation, etc.), agents must ensure that:
•Safety checks are present.
•Code paths are covered by tests where practical.
•Behavior is logged clearly enough for QEMU-based verification.

⸻

5. Testing Expectations

When adding or modifying runtime logic:
•Prefer adding or updating tests under tests/.
•Keep test harness scripts simple and documented.
•When feasible, wire new behavior into a QEMU-based scenario (even if manual at first).

The agent is not required to configure CI services but should maintain ci/ and test-related scripts in a clean, extensible state.

⸻

6. Commit and Change Structure

Each logical unit of work should:
•Be as self-contained as reasonably possible.
•Include:
•Code changes.
•Tests (where applicable).
•Documentation updates.
•A new Bible entry.

The goal is to keep the repository history understandable and traceable through docs/SP_BIBLE.md.

---
