# Screaming Penguin — Agent Entry Point

This document defines standing instructions for any automated agent operating on this repository.

Agents must read and follow this document on **every run**.  
This file is considered **read-only by default** and must not be modified unless the prompt explicitly instructs the agent to edit it.

---

## 1. Required Reading Before Any Changes

Before performing any modifications, the agent must read:

- `docs/DESIGN_v0.md`
- `docs/DEV_ROADMAP.md`
- `docs/DEV_PHILOSOPHY.md`
- `docs/SP_BIBLE.md`

The agent must align all planned changes with:

- The v0 scope and architecture from `DESIGN_v0.md`
- The currently active phase and checkpoint in `DEV_ROADMAP.md`
- The development principles outlined in `DEV_PHILOSOPHY.md`

If changes do not clearly fit the documented scope, the agent should expect to halt or request clarification.

---

## 2. Bible Handling — Additive Only

`docs/SP_BIBLE.md` is a protected, additive-only log of project history.

Agents must:

- Never overwrite, delete, reorder, or reformat existing Bible content.
- Only append new entries **at the end of the file**.
- Use the following template verbatim:

```markdown
## Entry NNN — <Short Title>

**Date:** YYYY-MM-DD

<2–5 sentences summarizing what changed and why. Reference key files or milestones.>

NNN must be incremented monotonically, zero-padded (001, 002, 003…).

⸻

3. Entrypoint Safety

This document is canonical.
Agents must not modify it unless a prompt explicitly instructs specific changes.
All updates to workflow processes should occur in the other development documents, not here.
