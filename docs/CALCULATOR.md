# Command bar calculator

Type an expression in the command bar. Return copies the displayed answer.
Tab puts the numerical answer back in the field so you can continue calculating.
Tab preserves more precision than the rounded display, without thousands separators.

Missing closing brackets appear as ghost text without changing your input.
For example, `2*(3+4` evaluates as `2*(3+4)`. Mismatched brackets and unfinished
operands such as `2*(3+` do not produce an answer.

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

Numbers use your locale's separators. Expressions are limited to 120 characters
and use floating-point arithmetic rather than arbitrary precision.
