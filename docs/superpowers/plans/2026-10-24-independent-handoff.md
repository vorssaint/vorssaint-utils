# Independent handoff cards implementation plan

**Goal:** Show peer Keep Awake and Handoff cards, each with collapsed Options, and start handoff without a pre-existing Keep Awake session.

**Architecture:** The handoff card owns a separately persisted duration (default 60 minutes). Workflow preparation starts Keep Awake before connecting, retaining existing cancellation and brightness recovery. A repeated handoff restores the previous dimming baseline before starting a new session. Cancelling or failing handoff leaves the selected Keep Awake timer running; the existing Keep Awake switch can stop it. Completion hides progress and returns to the start control, without a persistent active label. Existing Keep Awake sessions use the handoff duration when starting a new handoff.

**Tech stack:** SwiftUI, Combine, existing Defaults registry and standalone workflow tests.

- [x] Add failing preparation tests: inactive session starts before connection; failed preparation has no side effects; duplicate starts do not prepare again.
- [x] Add the duration preference and workflow preparation hook; connect service startup and repeat handling.
- [x] Render peer cards, remove nested handoff controls from Keep Awake, add handoff's own Options and duration picker, and localize start labels.
- [x] Run workflow, hotspot, localization/settings and Keep Awake tests; build and manually inspect the inactive and expanded card layouts and direct-start flow.
- [x] Install the developer build, update the existing PR while preserving Draft, and report exact verification.
