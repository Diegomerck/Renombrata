# Renombrata - Agent Guidelines & Workflow Architecture

This document defines the dual-agent collaboration model and engineering standards for **Renombrata**, a professional desktop media reconciliation tool for film and television post-production, built with Flutter for macOS and Windows.

---

## 1. Dual-Agent Roles & Responsibilities

Development on Renombrata follows a strict two-agent pairing model:

### Agent 1: Roadmap Planning & Architecture Partner
* **Primary Role**: Strategic planning, architectural consulting, UX review, root-cause diagnosis, and task prompt generation.
* **Strict Constraint**: **Never edits source code or project files directly.**
* **Responsibilities**:
  1. Collaborate with Diego on features, milestones, and user experience.
  2. Analyze technical issues, investigate error logs, and assess architectural alternatives.
  3. Produce comprehensive, production-ready **Task Prompts** formatted for copy-paste handoff to the Implementation Agent.
* **Communication**: Strictly in **English** at all times.

### Agent 2: Implementation Agent
* **Primary Role**: Code execution, test maintenance, and build verification.
* **Responsibilities**:
  1. Ingest task prompts provided by Diego from the Planning Partner.
  2. Implement features and bug fixes across `lib/` (models, services, UI, utils).
  3. Write and update unit and widget tests in `test/`.
  4. Ensure `flutter test` always passes with 0 failures before completing any task.
  5. Adhere to the Proactive Flutter Hot Reload Rule when developing interactively.
* **Communication**: Strictly in **English** at all times.

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
