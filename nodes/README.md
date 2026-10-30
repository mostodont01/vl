# Node definitions

A node type is defined by a JSON file. The files in this folder are VL's
built-in nodes, loaded at startup (a broken file stops the app with an error
naming it). Your own nodes are imported into a project with
**File → Import Node…**: VL copies the JSON and the code files it lists into
the project file. See `examples/robocars/` for importable examples.

```json
{
    "id": "add",                     // Unique, stable. Saved in project files — don't rename.
    "group": "Math",                 // Shift+A menu section and node colour (default "Other").
    "title": "Add",                  // Shown in the node header and the Shift+A search.
    "description": "Adds A and B",
    "code": ["src/add.cpp", "src/add.hpp"],         // Code files, relative to this JSON.
    "app_widget": { "class": "AddWidget" },         // Optional, see below.
    "inputs": [
        { "id": "a", "name": "A", "type": "int32",
          "widget": { "kind": "number", "default": 0 } }
    ],
    "outputs": [
        { "id": "result", "name": "Result", "type": "int32" }
    ],
    "settings": [
        { "id": "mode", "name": "Mode", "type": "string",
          "widget": { "kind": "select", "options": ["a", "b"] } }
    ]
}
```

(JSON doesn't allow comments — they're only here for explanation.)

- **inputs** — sockets on the left. An input with a `widget` shows that editor
  while nothing is connected; without one it's a plain socket.
- **outputs** — sockets on the right. No widgets.
- **settings** — values on the node with no socket at all. `widget` is required.
  Add `"app_widget_only": true` to a setting that only matters for the app
  widget (like its label); it's hidden while the node's eye is closed.

- **code** — the node's C++ source and header files, relative to the JSON
  file and inside its folder (subfolders are fine). Imported with the node.

Group and socket type colours are set per project in the **Settings** tab;
importing a node with a new group or type asks for its colour.

Socket and setting ids must be unique within a node (inputs and settings
share one namespace). Wires only connect sockets with exactly the same `type`.

## Widget kinds

| kind       | options                           | default if omitted |
|------------|-----------------------------------|--------------------|
| `number`   | `default`, `min`, `max`           | `0`                |
| `string`   | `default`                         | `""`               |
| `select`   | `options` (required), `default`   | first option       |
| `checkbox` | `default`                         | `false`            |

Numbers are whole numbers when the type starts with `int`/`uint`
(e.g. `int32`), otherwise decimals. `"widget": "number"` is shorthand for
`{ "kind": "number" }`.

## App widgets

A node with `app_widget` shows something in the compiled app (a number
display, a number input, a LiDAR view, ...). Such nodes get an eye in their
header to choose whether the widget is shown; the compiled app runs
fullscreen and arranges all shown widgets automatically.

The widget itself is written in the node's own C++ code; `class` names the
class there. The C++ interface widgets implement is designed together with
the compiler, so for now it is only stored.
