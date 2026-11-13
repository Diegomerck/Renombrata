# Renombrata - Agent Guidelines & Workflow Architecture

This document defines the single-conversation workflow model and engineering standards for **Renombrata**, a professional desktop media reconciliation tool for film and television post-production, built with Flutter for macOS and Windows.

---

## 1. Single-Conversation Workflow Architecture

Renombrata development operates within a single-conversation pair programming model designed for token quota efficiency:

### Workflow Triggers & Execution Modes

| Mode / Trigger | When to Use | Agent Behavior |
| :--- | :--- | :--- |
| *(Default - No prefix)* | Architecture discussions, brainstorming, UI/UX scoping, design decisions | **PLANNING ONLY**: Zero code edits, zero builds or tests. The agent clarifies specs, assesses task complexity, and declares the recommended execution tier. |
| **`IMPLEMENTATION`** | Starting message with `IMPLEMENTATION` | **SUBAGENT EXECUTION**: Automatically dispatches a subagent at the assessed tier (`flash` by default to preserve quota, `pro` for high complexity), runs `flutter test`, and provides a concise summary. Draws from Gemini quota. |
| **`IMPLEMENT: INHERIT`** | Starting message with `IMPLEMENT: INHERIT` | **FORCED INHERIT SUBAGENT**: Dispatches the subagent strictly using `Model: "inherit"`. The subagent directly adopts whichever model and provider is currently selected in the main chat model picker (e.g., Claude Opus, Claude Sonnet, GPT-4o), drawing strictly from that specific quota. |
| **`QUICK FIX`** | Starting message with `QUICK FIX` | **DIRECT EDIT**: Applies trivial edits (single typo, 1-line styling) directly without subagent overhead. |

### Complexity & Execution Tiers (Assessed in Planning)
* **Standard Tier (`Model: "flash"`)**: 1–2 files, localized UI styling, widget adjustments, simple components. Keeps credit usage minimal.
* **High Tier (`Model: "pro"`)**: Multi-file refactors, reconciliation engine algorithms, state machine logic, complex tests.
* **Inherited Mode (`Model: "inherit"`)**: Triggered via `IMPLEMENT: INHERIT`. Adopts the model currently active in the chat picker.
* *Safeguard: Expensive models (e.g. Argon) are NEVER invoked unless explicitly requested by name or active in inherit mode.*

### Communication & Engineering Standards
* **Communication**: Strictly in **English** at all times.
* **Testing Integrity**: `flutter test` must always pass with 0 failures before completing any task.

---

## 2. Cross-Platform Engineering Standards

Renombrata is a cross-platform desktop application targeting **macOS** and **Windows**:

### macOS (Apple Silicon / Intel)
* **App Sandbox**: File-access entitlements must be preserved in `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:
  ```xml
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
  ```
* **Dependency Management**: CocoaPods (`brew install cocoapods`) is required for native desktop plugins that do not yet support Swift Package Manager (e.g., `desktop_drop`).
* **Minimum Window Dimensions**: Enforce `1100 x 720` natively in `MainFlutterWindow.swift` and in `main.dart` via `window_manager` to prevent UI truncation.

### Windows (10 / 11)
* **Prerequisites**: Visual Studio with the *"Desktop development with C++"* workload.
* **File System**: Use `path` package for cross-platform path separators and directory traversal.

---

## 3. Core Architectural Pillars

1. **Bitácora Digital**:
   - Two-tier slate card layout (Tier 1: Slate metadata; Tier 2: Inline SMPTE timecodes and collapsible notes).
   - High-contrast zebra striping (slate palette, crisp input borders, distinct card elevation in both Light and Dark themes).
   - Multi-take batch selection with tri-state master header checkbox, batch deletion confirmation, and undo support.

2. **Media Reconciliation Engine**:
   - Automatic matching of camera clips (`A001C001...`) against bitácora records.
   - Sidecar XML metadata pairing (`M01.XML`).
   - Interactive Conflict Resolver (`ConflictResolverDialog`) for duplicate takes with candidate comparison (file size, timestamp) and manual override persistence.
   - Intelligent Drag & Drop (`desktop_drop`) supporting camera card folders, `.xlsx`/`.xls` sheets, and `.renombrata` project files.
   - Audit logging, exportable CSV/Excel reports, and one-click rollback safety net (`rename_history.json`).

3. **Timecode & Standards**:
   - SMPTE timecode format: `HH:MM:SS:FF` with frame-rate awareness (23.98, 24, 25, 29.97, 59.94).
   - Validated via `TimecodeFormatter` and text input formatters.

---

## 4. Getting Started on Any Machine

Whenever cloning this repository to a new computer:

```bash
# 1. Fetch dependencies
flutter pub get

# 2. Verify all tests pass
flutter test

# 3. Launch on desktop
flutter run -d macos    # On macOS
flutter run -d windows  # On Windows
```
