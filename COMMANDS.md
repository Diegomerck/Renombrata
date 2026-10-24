# Renombrata - Developer Command Reference & Operations Manual

This document is the official operational cheat-sheet and command reference for building, running, testing, and debugging **Renombrata** on Windows and macOS.

---

## 1. Quick Start (Desktop Launch)

Renombrata is built natively for desktop platforms using Flutter.

### Run in Debug Mode (with Interactive Terminal)
```bash
# Windows desktop launch
flutter run -d windows

# macOS desktop launch
flutter run -d macos
```

### Inspect Available Devices / Targets
```bash
flutter devices
```

### Build Production Releases
```bash
# Windows production release bundle
flutter build windows

# macOS production release bundle (.app / dmg)
flutter build macos
```

---

## 2. Interactive Terminal Controls (While App is Running)

When `flutter run` is active in your terminal, single-key controls allow real-time development and inspection without restarting the process:

| Key | Action | Description |
| :---: | :--- | :--- |
| **`r`** | **Hot Reload** | Sub-second widget tree re-assembly. Preserves state while applying UI and build logic updates immediately. |
| **`R`** | **Hot Restart** | Re-initializes application state and restarts the Dart VM from `main()`. Much faster than a full rebuild. |
| **`h`** | **Help** | Prints the list of available interactive Flutter CLI commands. |
| **`d`** | **Detach** | Detaches the terminal CLI session while leaving the desktop application running on your desktop. |
| **`c`** | **Clear Screen** | Clears terminal console output. |
| **`q`** | **Quit / Terminate** | Gracefully closes the running desktop application process. |

> [!TIP]
> Always prefer **Hot Reload (`r`)** for iterative UI styling and layout tuning. Use **Hot Restart (`R`)** when modifying initial state, static constants, or `initState()` life-cycle logic.

---

## 3. Dependency & Environment Setup

Manage Dart and Flutter dependencies, clean build artifacts, and resolve platform bindings:

```bash
# Install / resolve dependencies from pubspec.yaml
flutter pub get

# Upgrade dependencies to latest compatible versions
flutter pub upgrade

# Clean build caches, CMake output, and ephemeral artifacts
flutter clean

# Full clean refresh chain (recommended after major branch switching or native config edits)
flutter clean && flutter pub get
```

---

## 4. Testing & Code Quality

Renombrata maintains strict test-driven standards. All tests must pass before code is merged or tasks completed.

### Running Tests
```bash
# Run the complete unit and widget test suite
flutter test

# Run tests with a concise progress reporter
flutter test --reporter compact

# Run an individual test file
flutter test test/media_preview_dialog_test.dart

# Run tests matching a specific description or name
flutter test --name "Slate Magnifier"
```

### Static Analysis & Linter
```bash
# Analyze code for warnings, errors, and style violations
dart analyze

# Automatically apply mechanical fixes for lint warnings
dart fix --apply

# Dry-run lint fixes to inspect proposed changes before applying
dart fix --dry-run
```

---

## 5. Desktop Platform Troubleshooting

### Windows (10 / 11)
* **C++ Compiler Prerequisite**:
  Visual Studio 2022 (Community or higher) with the **"Desktop development with C++"** workload installed is required to compile Windows native plugins and the C++ Runner.
* **`media_kit` Native Libraries (`libmpv-2.dll`)**:
  `media_kit` bundles dynamic C libraries. If you encounter errors about `libmpv-2.dll` missing or crashing during Hot Restart:
  1. Gracefully quit the terminal session (`q`).
  2. Relaunch with `flutter run -d windows` so CMake properly copies and links dynamic runtime DLLs into `build/windows/runner/Debug/`.

### macOS (Apple Silicon / Intel)
* **CocoaPods Dependency Management**:
  Native desktop plugins (such as `desktop_drop`) require CocoaPods. If native build errors occur:
  ```bash
  cd macos && pod install && cd ..
  ```
* **App Sandbox Entitlements**:
  To allow users to drag-and-drop or select external camera volumes (e.g. SD cards, CFast, SSDs), file-access entitlements must remain active in both `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:
  ```xml
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
  ```
* **Minimum Window Dimensions**:
  Renombrata enforces a minimum window resolution of `1100 x 720` natively in `MainFlutterWindow.swift` and in `main.dart` via `window_manager` to prevent UI clipping on slate forms.

---

## 6. Embedded Binary Toolchain

Renombrata is packaged as a **100% self-contained desktop application** with zero external CLI prerequisites.

* **Embedded MediaInfo Engine**:
  Embedded timecode extraction for standalone `.mov`, `.mp4`, and `.mxf` media is handled by `EmbeddedMetadataProbeService` (`lib/src/services/embedded_metadata_probe_service.dart`).
* **Binary Locations**:
  - Windows x64: `assets/bin/windows/mediainfo.exe`
  - macOS Universal: `assets/bin/macos/mediainfo`
* **Runtime Extraction**:
  The application automatically unpacks the appropriate executable to a persistent cache directory (`ApplicationSupportDirectory/renombrata_bin/`) upon first launch, sets execution permissions (`chmod +x` on macOS), and runs it silently in the background. No manual installation of MediaInfo or FFmpeg is needed.

---

## 7. Automated Desktop Field Releases (GitHub Actions)

To commit all current changes, stamp a new version tag, push to GitHub, and automatically trigger the Windows (.zip) and macOS (.zip) release compilation pipelines simultaneously, copy and run this single command in PowerShell:

```powershell
git commit -am "release: update field build"; git tag v1.0.0-beta.2; git push origin main --tags
```

> [!TIP]
> Replace v1.0.0-beta.2 with whatever version tag you want to release.
