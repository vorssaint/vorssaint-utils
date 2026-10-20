# Command Bar Custom Scripts & Responses

Vorssaint's Command Bar allows you to define custom script shortcuts (`CommandBarLink`) that execute local executables or shell scripts and present their responses directly in the launcher.

## Overview

When you type a script link's name in the Command Bar (optionally followed by arguments):
1. **Debounced Execution**: The script runs in the background with a 0.25s debounce period (`CommandBarScriptRunner`).
2. **Response Generation**:
   - If the script outputs **plain text**, it generates a single answer row (legacy behavior).
   - If the script outputs **JSON**, it generates **multiple selectable option rows**.
3. **Execution / Copy**: Selecting any row and pressing <kbd>Return</kbd> copies its value to the clipboard and closes the bar.

---

## Output Formats

### 1. Legacy Plain Text (Single Response Row)

Any non-JSON text printed to `stdout` is treated as a single response row:
```sh
#!/bin/sh
echo "https://github.com/vorssaint/vorssaint-utils"
```
The Command Bar renders this as a single answer row. Pressing <kbd>Return</kbd> copies the string to the clipboard.

---

### 2. JSON Array of Strings (Multiple Option Rows)

```json
[
  "First Option",
  "Second Option",
  "Third Option"
]
```
Each string in the array produces a selectable row in the Command Bar. Pressing <kbd>Return</kbd> on any row copies that string.

---

### 3. JSON Array of Objects (Rich Options)

Each object can configure custom display and copy properties:
```json
[
  {
    "title": "PR #101: Fix authentication bug",
    "subtitle": "Author: Alice • Status: Approved",
    "value": "https://github.com/vorssaint/vorssaint-utils/pull/101"
  },
  {
    "title": "PR #102: Add unit tests for runner",
    "subtitle": "Author: Bob • Status: In Review",
    "value": "https://github.com/vorssaint/vorssaint-utils/pull/102"
  }
]
```

#### Supported Keys:
- **`title`** (or `name`, `label`, `text`): The main text displayed on the row.
- **`subtitle`** (or `detail`, `description`, `hint`): Secondary description text rendered beneath the title. Defaults to the standard copy hint if omitted.
- **`value`** (or `arg`, `copy`, `text`, `content`): The text copied to the clipboard when this row is selected. Defaults to `title` if omitted.

---

### 4. Wrapped JSON Object (`items` / `options` / `results`)

Scripts following popular workflow conventions (e.g. Alfred or Raycast JSON formats) are also parsed automatically:
```json
{
  "items": [
    {
      "title": "Docker: api-server",
      "subtitle": "Port 8080 (Running)",
      "value": "docker restart api-server"
    },
    {
      "title": "Docker: postgres-db",
      "subtitle": "Port 5432 (Running)",
      "value": "docker restart postgres-db"
    }
  ]
}
```
Supported container keys: `"items"`, `"options"`, `"results"`, `"rows"`, and `"data"`.

---

## Configuration in Settings

You can register and manage custom script links in **Settings → Command Bar → Links & Scripts**:
* **Name**: The trigger prefix keyword to type in the Command Bar (e.g., `pr`, `ports`, `docker`).
* **Kind**: Select `Terminal / Script`.
* **Destination**: Path to your script (e.g. `~/.bin/list-prs` or `/usr/local/bin/my-tool`).
* **Runs without argument**:
  * **Off**: Typing the name prompts for trailing arguments (e.g., typing `pr ` and waiting for input).
  * **On**: The script runs as soon as you finish typing its name, without requiring arguments.
* **Runs directly**:
  * If assigned a dedicated global row shortcut, runs silently in the background without opening the Command Bar window.
