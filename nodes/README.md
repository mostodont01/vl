# Node definitions

A node type is defined by a JSON file. The files in this folder are VL's
built-in nodes, loaded at startup (a broken file stops the app with an error
naming it). Your own nodes are imported into a project with
**File → Import Node…**: VL copies the JSON and the code files it lists into
the project file. See `examples/robocars/` for importable examples.

```json
{
    "id": "add",                     // Unique, stable. Saved in project files — don't rename.
    "class": "Add",                  // The C++ class implementing the node (see below).
    "group": "Math",                 // Shift+A menu section and node colour (default "Other").
    "title": "Add",                  // Shown in the node header and the Shift+A search.
    "description": "Adds A and B",
    "code": ["src/add.cpp", "src/add.hpp"],         // Code files, relative to this JSON.
    "app_widget": { "title_setting": "mode" },      // Optional, see below.
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
fullscreen and arranges all shown widgets automatically, with one shared
text size. `"title_setting": "label"` uses that setting's value as the
widget title (otherwise the node title).

The widget is drawn by the node's C++ class in `drawWidget()` with
[Dear ImGui](https://github.com/ocornut/imgui), inside `#ifdef VL_GUI`.

## The C++ class

`"class"` names the C++ class implementing the node, defined in one of its
`code` headers. It derives from `vl::Node` and has one member per socket and
setting, named after their ids (so ids must be C++ identifiers, unique
within the node):

```cpp
#include "vl/runtime.hpp"

class Add : public vl::Node {
public:
    vl::Input<int32_t> a;          // inputs:   vl::Input<T>, read with get()
    vl::Input<int32_t> b;
    vl::Output<int32_t> result;    // outputs:  vl::Output<T>, write with set()
    // settings: plain members, e.g. `float frequency = 10;`

    void process() override { result.set(a.get() + b.get()); }
};
```

- `setup()` runs once at the start; call `runEvery(seconds)` there for
  sources like sensors.
- `process()` runs whenever an input receives a new value (using the latest
  value of the others), once every input has a value. Wires that close a
  feedback loop don't start a run; they only update the value.
- `requestProcess()` runs `process()` again, e.g. after a widget changed.

See `runtime/vl/runtime.hpp` for the details, `nodes/src/` for the built-in
nodes and `examples/robocars/` for nodes with separate `.cpp` files.

## Custom socket types

`int32`, `float32`, `bool` and `string` are built in. Any other type needs
a C++ definition, declared by the nodes that use it:

```json
"types": { "LidarScan": { "cpp": "LidarScan", "header": "src/lidar_scan.hpp" } }
```

The header must be listed in `code`. Several nodes may ship the same header;
it is included only once (they must be identical).
