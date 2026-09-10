# Command bar calculator

Type an expression in the command bar. Return copies the displayed answer.
Tab puts the numerical answer back in the field so you can continue calculating.
Tab preserves more precision than the rounded display, without thousands separators.

Missing closing brackets are inferred only when the expression can otherwise be
fully evaluated. For `2*(3+4`, the field draws a dim `)` without changing your text,
selection, clipboard contents, or undo history. Typing the closing bracket makes it
ordinary text. The answer row also shows the completed expression, including when
the field has scrolled or the query ends with `=`. Extra or mismatched brackets are
rejected, as are unfinished operands such as `2*(3+`.

## Supported expressions

| Input | Meaning |
| --- | --- |
| `2(3+4)` | Implicit multiplication, yielding 14 |
| `sqrt(81)` | Square root, yielding 9 |
| `sin(pi/2)` | Sine in radians, yielding 1 |
| `2pi` | Twice pi |
| `ln(e)` | Natural logarithm, yielding 1 |
| `log(100)` or `log10(100)` | Base-10 logarithm, yielding 2 |
| `1e-9*2` | Scientific notation |
| `480+15%` | Relative percentage, yielding 552 |
| `20% of 480` | Percentage of a value, yielding 96 |

Functions: `sqrt`, `abs`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `ln`,
`log`, `log10`, `exp`, `floor`, `ceil`, and `round`. Each takes one bracketed
argument. Trigonometric functions take radians; inverse functions return radians.
Constants are `pi`, `π`, and `e`. Round and square brackets can be nested.

Arithmetic retains locale-aware number parsing and formatting. A lone number,
ordinary search text, dates, invalid domains, division by zero, and non-finite
results do not produce calculator answers. Expressions are limited to 120
characters and bounded nesting. This is a Double-based calculator, not an
arbitrary-precision or financial accounting engine.

## Checks

`./build.sh --test` runs the calculator cases in the existing `Tests/MetricsTests.swift`
suite and the native ghost-rendering check in `Tests/CommandBarGhostBracketsTests.swift`.
The rendering check needs a macOS graphical session, as provided by the CI runners.

Manual checks in the command bar should cover typing and deleting closing brackets,
caret movement, horizontal scrolling, IME composition, Tab followed by another
operator, undo after Tab, Return-to-copy, and ordinary searches containing brackets.
