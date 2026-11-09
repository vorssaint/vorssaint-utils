# Browser Picker & Link Routing

*   **Author:** ysamjo
*   **Status:** Proposed
*   **Date:** 2026-10-31

--------------------------------------------------------------------------------

## Overview

A native macOS link routing and browser selection subsystem for `vorssaint/vorssaint-utils`. When configured as the default HTTP/HTTPS handler on macOS, Vorssaint intercepts incoming web links clicked across external applications, evaluates configured URL routing rules, and directs traffic immediately to target browsers or specific profiles, falling back to a lightweight HUD panel at the mouse pointer.

## The Problem

macOS allows only a single global default web browser. Users operating across distinct work and personal contexts, multiple browsers (e.g., Safari, Chrome, Arc, Brave), or isolated browser profiles frequently encounter unwanted context switching, manual URL copying, or private links opening inside enterprise profiles. Third-party utilities like Velja and Browserosaurus address this, but Vorssaint users require an in-tree, private, and zero-dependency solution adhering to Vorssaint's strict in-tree modular architecture and security model.

## Goals

*   **System Default Handler**: Register Vorssaint as an HTTP/HTTPS URL handler via `CFBundleURLTypes` in `Resources/Info.plist`, with a toggleable status in the Feature Hub and clean restoration of previous handlers.
*   **Browser & Profile Discovery**: Enumerate installed browser applications via `NSWorkspace` and discover user profiles across Chromium (Local State) and Firefox (`profiles.ini` / profile groups).
*   **Fast Pointer HUD**: Provide a non-activating floating HUD at `NSEvent.mouseLocation` displaying detected browser targets with direct keyboard accelerators (number keys, arrows, Return, Esc).
*   **Rule-Based Routing**: Match incoming links against prioritized rules supporting exact hosts, wildcards (`*.zoom.us`, `jira.*`, `https://meet.google.com/*`), and regular expressions before falling back to the picker HUD.
*   **Modular In-Tree Integration**: Integrate as an optional tool under `FeatureCatalog.AppFeature.browserPicker` with zero external binary dependencies.

## Non-Goals

*   **HTML Document Viewing**: Vorssaint will not register for `public.html` or local file handling. Local files remain associated with dedicated browsers.
*   **Non-Browser Protocol Routing**: Arbitrary custom URL schemes (e.g., `slack://`, `zoommtg://`) will not be routed. Handling is strictly restricted to `http` and `https`.
*   **Dynamic Plugin System**: In accordance with Issue #770, no dynamic third-party extension or external script loading will be supported. All routing logic is compiled in-tree.
*   **Cloud Rule Synchronization**: Rules are persisted locally in macOS `UserDefaults` and included in local settings backups; no external synchronization service is provided.

## Critical User Journeys (CUJs)

### CUJ 1: Automated Rule Routing to Specific Browser Profile

*   **Given**: Vorssaint is registered as the system default web browser. A rule maps `jira.*` to Chrome with profile "Work".
*   **When**: The user clicks `https://jira.company.com/browse/PROJ-123` in an external application (e.g., Slack or Mail).
*   **Then**: macOS delivers the URL event to Vorssaint. Vorssaint matches the link against `BrowserPickerRule`, bypasses the HUD, and launches Chrome using `--profile-directory="Profile 1"` opening the URL directly. The calling app remains frontmost.

### CUJ 2: Fallback Pointer HUD Selection

*   **Given**: Vorssaint is the default browser. No configured rule matches `https://news.ycombinator.com`.
*   **When**: The user clicks the link in a terminal or document.
*   **Then**: A non-activating floating panel appears adjacent to `NSEvent.mouseLocation`. The user presses `1` (or arrows + Return). The selected browser opens the URL, and the HUD closes immediately.

### CUJ 3: On-the-Fly Rule Creation from Picker HUD

*   **Given**: The user is presented with the HUD for an unrouted link `https://github.com/vorssaint/vorssaint-utils`.
*   **When**: The user holds `Option` while selecting Safari, or clicks "Rule for this site...".
*   **Then**: A rule is remembered or configured in the editor. Subsequent links to `github.com` and its subdomains route to Safari automatically without presenting the HUD.

## Technical Plan (Architecture)

### Architectural Components

1.  **URL Interception Layer (`AppDelegate` / `Info.plist`)**:
    *   Registers `CFBundleURLTypes` for `http` and `https`.
    *   `NSAppleEventManager` catches `kAEGetURL` events and forwards validated URLs to `BrowserPickerService.shared.handle(url:)`.
2.  **Service & Discovery Layer (`Sources/Vorssaint/Services/BrowserPicker/`)**:
    *   `BrowserPickerService`: Manages link queue, rule evaluation, and HUD presentation.
    *   `BrowserPickerBrowsers`: Queries `NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://")!)`. Discovers profiles:
        *   Chromium: Parses `~/Library/Application Support/<Browser>/Local State` (`profile.info_cache`).
        *   Firefox: Parses `~/Library/Application Support/Firefox/profiles.ini` and `Profile Groups/*.sqlite`.
    *   `BrowserPickerDefaultBrowser`: Manages system default browser registration and rollback via Launch Services APIs (`LSSetDefaultHandlerForURLScheme`).
3.  **Rule Engine (`Sources/Vorssaint/Core/`)**:
    *   `BrowserPickerRule`: Encapsulates rule definition, target specification (`.application` or `.profile`), enabled status, and ordering.
    *   `BrowserPickerPatterns`: Evaluates wildcard globs (scheme, host with port, path) and case-insensitive regular expressions against incoming links.
4.  **UI & HUD Layer (`Sources/Vorssaint/UI/BrowserPicker/` & `UI/Settings/`)**:
    *   `BrowserPickerPanel`: Non-activating `NSPanel` floating at pointer location (`level = .floating`, `.nonactivatingPanel`).
    *   `BrowserPickerView`: SwiftUI interface displaying browser/profile badges, keyboard numbers, and link preview.
    *   `BrowserPickerRuleEditor`: Modal sheet and floating window editor supporting site and pattern specifications with live link matching validation.
    *   `BrowserPickerSettings`: Feature Hub configuration pane displaying default browser status, detected browsers/profiles, and reorderable rules list.

```
                    +--------------------------------+
                    | External App (Click HTTP Link) |
                    +---------------+----------------+
                                    | (Launch Services)
                                    v
                    +--------------------------------+
                    | Info.plist / AppDelegate       |
                    | (kAEGetURL Event Handler)      |
                    +---------------+----------------+
                                    |
                                    v
                    +--------------------------------+
                    |      BrowserPickerService      |
                    +-------+----------------+-------+
                            |                |
             Matches Rule   |                | No Rule Match
                            v                v
      +---------------------+---+   +--------+--------------------+
      | BrowserPickerRule Engine |   | BrowserPickerPanel (HUD)   |
      | - Site/Path Matching    |   | - Non-activating NSPanel   |
      | - Wildcard / Regex      |   | - Keyboard Accelerators    |
      +-------------+-----------+   +--------+--------------------+
                    |                        | User Selection
                    +-----------+------------+
                                |
                                v
               +--------------------------------+
               |  Target Execution              |
               |  - NSWorkspace.shared.open     |
               |  - Chromium: --profile-directory
               |  - Firefox: --profile <dir>    |
               +--------------------------------+
```

## Alternatives Considered

### Alternative A: Standalone Helper Application

*   **Pros**: Complete isolation from Vorssaint's main run loop, crashing or blocking IO does not impact desktop management tools.
*   **Cons**: Requires multi-process IPC, duplicate bundle signing credentials, and extra app bundle maintenance.
*   **Reason for Rejection**: Vorssaint features operate in-tree under modular catalog management (`FeatureCatalog`). A separate helper contradicts Vorssaint's unified architecture.

### Alternative B: External AppleScript Scripting for Profile Switching

*   **Pros**: Avoids inspecting on-disk profile directories in Application Support.
*   **Cons**: Demands explicit macOS Automation permissions (`NSAppleEventsUsageDescription`), causes visible prompt delays, and lacks universal AppleScript support across browsers.
*   **Reason for Rejection**: Command-line flag invocation via `NSWorkspace.openApplication` (`--profile-directory` and `--profile`) requires zero automation permissions and provides faster, deterministic process dispatch.

### Alternative C: Site-Only Matching without Wildcard/Regex Patterns

*   **Pros**: Simplest rule model with minimal configuration complexity.
*   **Cons**: Incapable of routing based on ports, scheme constraints (plain `http://*`), subdomain wildcards like `jira.*`, or specific URL path prefixes like `https://meet.google.com/*`.
*   **Reason for Rejection**: Power users with enterprise setups require flexible wildcard and regex matching (as tracked in Issue #2056).

--------------------------------------------------------------------------------

## Detailed Implementation Plan

### Target Files to Create/Modify

#### 1. `Sources/Vorssaint/Core/BrowserPickerPatterns.swift` (Create)

*   **Scope**: Core link matching engine.
*   **Proposed Changes**: Implements `BrowserPickerPattern` with kinds `.wildcard` and `.regularExpression`. Defines `Link` breakdown, glob parsing (`*`, `?`), host anchoring, scheme filtering, and case-insensitive regex evaluation.

#### 2. `Sources/Vorssaint/Core/BrowserPickerRules.swift` (Modify)

*   **Scope**: Rule storage and matching orchestration.
*   **Proposed Changes**: Add optional `pattern: BrowserPickerPattern?` to `BrowserPickerRule`. Update `covers()` to evaluate pattern matches when present, and update `BrowserPickerRuleDraft` to support editing pattern fields.

#### 3. `Sources/Vorssaint/Core/BrowserPickerStrings.swift` (Modify)

*   **Scope**: String catalogs for UI localization.
*   **Proposed Changes**: Add localized labels for pattern matching (`matchLabel`, `matchWildcard`, `matchRegularExpression`, `patternLabel`, `wildcardHint`, `regularExpressionHint`, `missingPatternHost`, `invalidRegularExpression`) across all 15 supported locales (`enUS`, `de`, `es`, `fr`, etc.).

#### 4. `Sources/Vorssaint/UI/BrowserPicker/BrowserPickerRuleEditor.swift` (Modify)

*   **Scope**: SwiftUI rule configuration sheet.
*   **Proposed Changes**: Embed a pattern kind `Picker` (Site vs Wildcard vs Regex) and a monospaced pattern `TextField`. Bind real-time matching evaluation against any waiting link (`testURL`).

#### 5. `Sources/Vorssaint/UI/Settings/BrowserPickerSettings.swift` (Modify)

*   **Scope**: Settings view in Feature Hub.
*   **Proposed Changes**: Display the pattern string in monospaced font and secondary pattern kind badge when rendering a rule row with an active pattern.

#### 6. `Tests/BrowserPickerTests.swift` (Modify)

*   **Scope**: Unit test suite.
*   **Proposed Changes**: Add `patterns(_:)` test group validating wildcard globbing, single character `?`, port preservation, anchored schemes, regexes, and encoding/decoding backward compatibility.

#### 7. `Tests/mutation_checks.py` (Modify)

*   **Scope**: Regression and mutation audit suite.
*   **Proposed Changes**: Register mutations ensuring regex/wildcard anchor constraints and pattern fallback logic are guarded by test assertions.

#### 8. `build.sh` (Modify)

*   **Scope**: Build script configuration.
*   **Proposed Changes**: Add `Sources/Vorssaint/Core/BrowserPickerPatterns.swift` to compilation file list.

### Verification Plan

*   **Unit Tests**: Run `./build.sh --test-suite=browser-picker` (verify all pattern test cases pass).
*   **Localization Verification**: Run `./build.sh --test-suite=localization` (verify 15 locales match schema without missing translations or em-dashes).
*   **Developer Build**: Run `./build.sh --dev` (ensure clean compilation against macOS SDK without warnings).
*   **Runtime Selftest**: Run `./build/VorssaintDeveloper --selftest` (verify internal integrity checks pass).

--------------------------------------------------------------------------------

*Drafted with EGM*
