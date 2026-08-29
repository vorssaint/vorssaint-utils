#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# CI quality gate for startup latency and menu-bar panel responsiveness.
# Measures real app launch + first menu bar interaction through Accessibility,
# repeats several times and fails when median latency exceeds configured budgets.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG_FILE=".github/ci/performance-gates.env"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

APP_PATH="${VORSSAINT_PERF_APP_PATH:-build/stage/Vorssaint.app}"
PROCESS="${VORSSAINT_PERF_PROCESS:-Vorssaint}"
ITERATIONS="${VORSSAINT_PERF_ITERATIONS:-4}"
WARMUP_RUNS="${VORSSAINT_PERF_WARMUP_RUNS:-1}"
STARTUP_TIMEOUT_MS="${VORSSAINT_PERF_STARTUP_TIMEOUT_MS:-12000}"
POPOVER_TIMEOUT_MS="${VORSSAINT_PERF_POPOVER_TIMEOUT_MS:-3000}"
STARTUP_BUDGET_MS="${VORSSAINT_PERF_STARTUP_BUDGET_MS:-2500}"
POPOVER_BUDGET_MS="${VORSSAINT_PERF_POPOVER_BUDGET_MS:-450}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ App bundle not found at $APP_PATH" >&2
    exit 1
fi

if ! command -v osascript >/dev/null 2>&1; then
    echo "✗ osascript not available on runner" >&2
    exit 1
fi

if (( ITERATIONS <= WARMUP_RUNS )); then
    echo "✗ ITERATIONS must be greater than WARMUP_RUNS" >&2
    exit 1
fi

now_ms() {
    python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

wait_until() {
    local timeout_ms="$1"
    local script="$2"
    local started now elapsed result
    started="$(now_ms)"
    while true; do
        result="$(osascript -e "$script" 2>/dev/null || true)"
        if [[ "$result" == "true" ]]; then
            return 0
        fi
        now="$(now_ms)"
        elapsed=$((now - started))
        if (( elapsed >= timeout_ms )); then
            return 1
        fi
        sleep 0.05
    done
}

discover_menu_bar_index() {
    local script='tell application "System Events"
tell process "'"$PROCESS"'"
set c1 to 0
set c2 to 0
try
set c1 to count of menu bar items of menu bar 1
end try
try
set c2 to count of menu bar items of menu bar 2
end try
if c2 >= c1 and c2 > 0 then
return "2"
else if c1 > 0 then
return "1"
else
return "0"
end if
end tell
end tell'
    osascript -e "$script" 2>/dev/null || echo "0"
}

click_menu_bar_item() {
    local index="$1"
    osascript -e 'tell application "System Events" to tell process "'"$PROCESS"'" to click menu bar item 1 of menu bar '"$index"'' >/dev/null
}

popover_exists() {
    local index="$1"
    osascript -e 'tell application "System Events" to tell process "'"$PROCESS"'" to return (exists pop over 1 of menu bar item 1 of menu bar '"$index"')' 2>/dev/null || echo "false"
}

ensure_app_stopped() {
    local _
    osascript -e 'tell application "'"$PROCESS"'" to quit' >/dev/null 2>&1 || true
    for _ in {1..80}; do
        if ! pgrep -xq "$PROCESS"; then
            return 0
        fi
        sleep 0.05
    done
    pkill -x "$PROCESS" >/dev/null 2>&1 || true
}

startup_samples=()
popover_samples=()

total_runs=$((ITERATIONS + WARMUP_RUNS))
echo "▸ Running $total_runs launch probes ($WARMUP_RUNS warmup + $ITERATIONS measured)"
for run in $(seq 1 "$total_runs"); do
    ensure_app_stopped

    launch_started="$(now_ms)"
    open "$APP_PATH"

    if ! wait_until "$STARTUP_TIMEOUT_MS" \
        'tell application "System Events" to return exists process "'"$PROCESS"'"'; then
        echo "✗ $PROCESS process did not appear in time (run $run)" >&2
        exit 1
    fi

    menu_bar_index="0"
    if ! wait_until "$STARTUP_TIMEOUT_MS" \
        'tell application "System Events" to tell process "'"$PROCESS"'" to return ((count of menu bar items of menu bar 1) > 0 or (count of menu bar items of menu bar 2) > 0)'; then
        echo "✗ menu bar item did not appear in time (run $run)" >&2
        exit 1
    fi
    menu_bar_index="$(discover_menu_bar_index)"
    if [[ "$menu_bar_index" == "0" ]]; then
        echo "✗ menu bar item index could not be resolved (run $run)" >&2
        exit 1
    fi

    startup_ms=$(( $(now_ms) - launch_started ))

    click_started="$(now_ms)"
    click_menu_bar_item "$menu_bar_index"
    if ! wait_until "$POPOVER_TIMEOUT_MS" \
        'tell application "System Events" to tell process "'"$PROCESS"'" to return (exists pop over 1 of menu bar item 1 of menu bar '"$menu_bar_index"')'; then
        echo "✗ menu panel did not open in time (run $run)" >&2
        exit 1
    fi
    popover_ms=$(( $(now_ms) - click_started ))

    # Close popover for clean next probe.
    osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
    sleep 0.1

    if (( run > WARMUP_RUNS )); then
        startup_samples+=("$startup_ms")
        popover_samples+=("$popover_ms")
        echo "  run $((run - WARMUP_RUNS)): startup ${startup_ms} ms, popover ${popover_ms} ms"
    else
        echo "  warmup: startup ${startup_ms} ms, popover ${popover_ms} ms"
    fi
done

ensure_app_stopped

startup_joined="$(printf '%s\n' "${startup_samples[@]}" | paste -sd, -)"
popover_joined="$(printf '%s\n' "${popover_samples[@]}" | paste -sd, -)"

read -r startup_median popover_median <<<"$(python3 - "$startup_joined" "$popover_joined" <<'PY'
import statistics
import sys

startup = [int(x) for x in sys.argv[1].split(",") if x]
popover = [int(x) for x in sys.argv[2].split(",") if x]
print(f"{int(statistics.median(startup))} {int(statistics.median(popover))}")
PY
)"

echo ""
echo "Startup median: ${startup_median} ms (budget ${STARTUP_BUDGET_MS} ms)"
echo "Popover median: ${popover_median} ms (budget ${POPOVER_BUDGET_MS} ms)"

failed=0
if (( startup_median > STARTUP_BUDGET_MS )); then
    echo "✗ Startup latency budget exceeded" >&2
    failed=1
fi
if (( popover_median > POPOVER_BUDGET_MS )); then
    echo "✗ Menu-bar responsiveness budget exceeded" >&2
    failed=1
fi

if (( failed == 0 )); then
    echo "✓ UI performance gate passed"
else
    exit 1
fi
