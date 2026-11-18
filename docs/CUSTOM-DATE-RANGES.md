# Custom date ranges in AI Agents

Choose **Custom range…** from the existing period menu, select **From** and **To**
calendar dates, then **Apply**. The displayed title identifies the selected dates.
Spending, tokens, model/project breakdowns and the trend all use that same range.
Plan limits, live work and the 13-week activity map retain their existing scope.

The end date includes its whole local calendar day. Internally the interval ends
at the following midnight, using calendar arithmetic so daylight-saving days can
be shorter or longer than 24 hours. Future dates cannot be selected. A reversed
range disables Apply and explains the invalid order. Cancel or dismissing the
popover leaves the saved period and statistics unchanged.

The dates are saved together in `notchAgentsDateRange`, as two ISO calendar-date
strings in one JSON preference. This preserves the chosen calendar dates after
a time-zone change and participates in the existing settings backup. Malformed
or impossible dates are ignored; a custom period with no valid dates falls back
to Today. No session content or usage counters are stored in this preference.

Applying a new range rebuilds the existing in-memory summary cache, without
restarting or rereading the log readers. New usage then updates it incrementally.
While a changed range is being calculated, the page shows its loading state so
it does not label the old totals with the new dates. Charts group longer ranges
into at most 30 bars, with hover labels showing the covered calendar dates.
Only locally available history contributes; selecting dates does not recover
logs that have been deleted. This feature builds on the all-time history change
proposed in PR #3830 and implements the custom-range portion of issue #3225.

Validation commands:

```sh
./build.sh --test-suite=agents --test-suite=settings
./build.sh --dev
'./build/stage.noindex/Vorssaint (Developer).app/Contents/MacOS/VorssaintDeveloper' --selftest
```

Local validation: the agents suite passed 2,572 checks and the settings suite
passed 666 checks (3,238 total). The Developer app build, bundled selftest and
strict installed-bundle signature verification passed. On a Mac mini M1 with
macOS 15 in English, native accessibility and screenshots verified the picker,
reversed-date validation, Cancel preserving the previous period, and Apply
updating the selected dates and the statistics together. The live log check
also surfaced SQLite warnings from the unchanged OpenCode reader; a clean
console is not claimed. Optimized/full-suite CI, VoiceOver interaction and
large-history performance were not verified locally.
