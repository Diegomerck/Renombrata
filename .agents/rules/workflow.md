# Renombrata — Single-Conversation Workflow & Token Optimization Rules

These rules govern all AI pair-programming interactions within the Renombrata project to optimize credit, token quota, and conversational context efficiency.

---

## 1. Default Mode: PLANNING (Zero Code Edits)

By default, every turn is treated strictly as **PLANNING / Brainstorming**.

### Strict Operational Constraints in PLANNING Mode:
- **Zero File Modifications**: NEVER edit, create, move, or delete source code or project configuration files.
- **Zero State Modification**: NEVER execute builds, test runs (`flutter test`), or mutating shell commands. (Safe read-only file reads or inspections to understand architecture are permitted when necessary).
- **Focus**: Clarify requirements, surface edge cases, evaluate architectural trade-offs, review UI/UX decisions, and align on specifications first.
- **Concise Token Economy**: Keep responses tight, clear, and focused. Avoid verbose explanations or redundant summaries to preserve context budget and token quota.

---

## 2. Transitioning to IMPLEMENTATION

Code modifications and test execution are ONLY unlocked when the user explicitly prefixes or starts their prompt with:
1. **`IMPLEMENTATION`**: Triggers full execution workflow via the assessed subagent tier (`flash` by default to conserve quota, `pro` for high complexity; draws from Gemini quota).
2. **`IMPLEMENT: INHERIT`**: Dispatches the implementation subagent strictly using `Model: "inherit"`. The subagent directly adopts whichever model and provider is currently selected in the main chat model picker (e.g., Claude Opus, Claude Sonnet, GPT-4o), drawing strictly from that specific quota.
3. **`QUICK FIX`**: Direct modification for microscopic adjustments (single typo, 1-line bug fix, single styling value) without subagent overhead.

If a message does not begin with `IMPLEMENTATION`, `IMPLEMENT: INHERIT`, or `QUICK FIX`, remain strictly in **PLANNING** mode.

---

## 3. Automatic Complexity Assessment & Execution Tiers

The user should never have to guess whether a task is easy or complex. During the **PLANNING** phase, the agent must evaluate the proposed changes and explicitly declare the recommended execution tier:

### Tier 1: Standard Tier
- **Scope**: 1–2 files, localized UI adjustments, widget layout/styling, isolated component updates, straightforward bug fixes.
- **Delegation**: Subagent invoked with `Model: "flash"` to conserve quota and execution credits (used when triggering `IMPLEMENTATION`).

### Tier 2: High Tier
- **Scope**: Multi-file refactoring, state management transitions, reconciliation engine logic, complex async/backend sync, intricate algorithms.
- **Delegation**: Subagent invoked with `Model: "pro"` (used when triggering `IMPLEMENTATION`).

### Tier 3: Inherited Model Mode (`IMPLEMENT: INHERIT`)
- **Scope**: Any implementation task where the user wants the subagent to run under the exact model/provider active in the chat picker (Claude, OpenAI, etc.).
- **Delegation**: Subagent invoked strictly with `Model: "inherit"`, using that provider's quota.

### Tier 4: Quick Fix (Direct)
- **Scope**: Trivial one-liner adjustments, minor typo corrections, or single-property styling fixes.
- **Execution**: Applied directly by the main agent without invoking a subagent.

### Model Safeguard:
- **NEVER** invoke expensive models (such as Argon) unless the user explicitly requests them by name in their prompt or activates them via `IMPLEMENT: INHERIT`.

---

## 4. Single-Conversation Architecture & Maintenance

- **Continuous Context**: Both planning and implementation remain in the single conversation thread to retain complete project memory and historical rationale without re-explaining context.
- **Token Hygiene (`/compact`)**: When context length grows or after completing a milestone, proactively remind the user to trigger `/compact` to summarize previous dialogue and reset per-turn token overhead.

---

## 5. Implementation Verification Protocol

When `IMPLEMENTATION` or `IMPLEMENT: INHERIT` is triggered:
1. Dispatch the subagent at the pre-assessed tier (`flash` or `pro` for `IMPLEMENTATION`, or `inherit` for `IMPLEMENT: INHERIT`).
2. Implement code changes across `lib/` and corresponding tests in `test/`.
3. Verify the project builds and runs all tests (`flutter test`) with 0 failures.
4. Report back with a concise, high-level summary of changed files and test outcomes.

