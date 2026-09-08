# Standalone Tests

Run `./build.sh --test` from the repository root on Apple Silicon macOS. It
compiles `Tests/*.swift` with the existing production-source list, runs the
standalone executable, runs `PreferenceCleanupTests.sh`, and sweeps test
preferences. There is no XCTest dependency or SwiftPM test target.

## Organization

- `MetricsTests.swift` owns assertion counting, ordered invocation, and the final
  result/exit status. Keep feature assertions and resource ownership out of it.
- Feature files expose `run(expect:)`. Descriptively named additional entry points
  preserve the original execution order for features with later regression checks.
- `BuildContractTests`, `HarnessSourceTests`, and `RepositoryContractTests` contain
  cross-cutting build, test-corpus, resource, source, and lifecycle contracts.
  Feature-specific wiring checks remain next to their behavioral tests.
- `LocalizationTests` and `CommandBarLocalizationTests` contain broad string and
  format contracts. Feature-specific translations may also be tested by their owner.
- `TestSupport.swift` contains only helpers used across suites. Keep private
  fixtures with their feature, including Scratchpad's storage checks and the
  existing SpeedTest URL protocol.
- `PreferenceCleanupTests.sh` separately tests the post-process preference sweep.

## Adding Tests

Add checks to the owning feature suite. For a new suite, add a Swift file directly
under `Tests/`, expose `run(expect: (Bool, String) -> Void)`, and call it explicitly
from `MetricsTests.main()`. The build discovers files automatically, but execution
is deliberately explicit. Report every assertion through the supplied callback;
do not add another counter or call `exit` from a suite.

Use behavior assertions for callable logic and source-contract assertions only
for wiring that the standalone binary cannot exercise. Repository scans must keep
their production-source scope: test files intentionally contain unsafe examples
and API names used as search needles. Run from the root so those paths resolve.

## Isolation

Execution stays serial and on the main thread. AppKit, keyboard-layout overrides,
and some preference fixtures are process-wide, so this is not a parallel runner.
The harness pins metric formatting to `en_US_POSIX`; tests that temporarily change
it must restore that setting. Restore keyboard layouts and shared preferences
before returning, and keep temporary directories and buffers within the suite
that creates them. Cleanup defers work in returning suites, not in the harness
that ends with `exit`.

UserDefaults fixture names must start with `vorss.tests.` or
`com.vorssaint.tests.` and be literal strings or locally declared string literals.
`HarnessSourceTests` checks every compiled Swift test file against the prefixes
read from the build script, resolving reused fixture names before each call.

The detached-process test is intentionally two-phase: `run(expect:)` returns a
finalizer that the harness calls late, retaining the original observation window
for delayed duplicate launches. Do not finalize it immediately after setup.
