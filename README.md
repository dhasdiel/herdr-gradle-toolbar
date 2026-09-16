# Gradle Toolbar

IntelliJ-style Gradle buttons for [herdr](https://herdr.dev), tuned for Kotlin Multiplatform projects.

Runs tasks in a shared bottom split pane (the "Run window"), resolves the project root by walking up to the nearest `gradlew`, and ships a popup task picker.

## Install

```
herdr plugin install dhasdiel/herdr-gradle-toolbar
```

Requires `python3` and a `gradlew`-based project. Works on macOS and Linux.

## Actions

| Action | Runs |
|---|---|
| `kmp.gradle-toolbar.build` | `./gradlew build` |
| `kmp.gradle-toolbar.test` | `./gradlew allTests` |
| `kmp.gradle-toolbar.check` | `./gradlew check` |
| `kmp.gradle-toolbar.clean` | `./gradlew clean` |
| `kmp.gradle-toolbar.assemble-debug` | `./gradlew assembleDebug` |
| `kmp.gradle-toolbar.run-jvm` | `./gradlew run` (Compose Desktop) |
| `kmp.gradle-toolbar.generate-mavlink` | `./gradlew generateMavlink` |
| `kmp.gradle-toolbar.rerun` | rerun the last task |
| `kmp.gradle-toolbar.stop` | interrupt the running task (ctrl+c) |
| `kmp.gradle-toolbar.tasks` | opens the task picker popup |

While a task runs the output pane title shows `gradle: <task>`; it flips to `✓`/`✗` and a notification fires when it finishes. If a build is still running, the next task gets a fresh pane.

## Customize tasks

The picker reads `tasks.txt` in the plugin config dir (`herdr plugin config-dir kmp.gradle-toolbar`). One per line: `Label|gradle args`.

A project can ship its own list: put `.herdr-gradle-tasks` (same format) at the repo root next to `gradlew` — it wins over the global file.

## Keybindings

```toml
[[keys.command]]
key = "prefix+b"
type = "plugin_action"
command = "kmp.gradle-toolbar.build"
description = "gradle build"

[[keys.command]]
key = "prefix+g"
type = "plugin_action"
command = "kmp.gradle-toolbar.tasks"
description = "gradle task picker"
```
