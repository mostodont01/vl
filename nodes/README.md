# Node definitions

Every `*.json` file in this folder defines one node type. They are loaded at
startup; a broken file stops the app with an error naming the file.

```json
{
    "id": "add",                     // Unique, stable. Saved in project files — don't rename.
    "category": "Math",              // Group in the Shift+A menu (default "Other").
    "title": "Add",                  // Shown in the node header and the Shift+A search.
    "description": "Adds A and B",
    "app_widget": { "kind": "number_display" },   // Optional, see below.
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

`kind` names a widget from VL's built-in widget library; other keys are
options for that widget. The library doesn't exist yet, so kinds are not
checked. Kinds used so far: `number_display`, `number_input`.
