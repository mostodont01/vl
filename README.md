# VL — Visual Language

VL is a visual dataflow programming language. Programs are built as node
graphs, similar to Blender's node editor: nodes have typed inputs and outputs
connected by wires, and incompatible types (e.g. `LidarScan` to `int32`)
can't be connected.

VL is a visual front end for a compiler, not a runtime: the goal is to
translate the graph into C++ (or another compiled language) that runs on the
target hardware.

VL started as a way to program a RoboCars competition robot, so its first
nodes are robotics-oriented, but the language isn't tied to it.

Built with Python, PySide6 and Qt Quick (QML). Linux-first.

## Run on Ubuntu

```bash
sudo apt update
sudo apt install python3 python3-venv
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
python main.py
```

If creating the virtual environment fails because Ubuntu manages Python packages externally, make sure `python3-venv` is installed and run the commands from your project directory.

## Current state

Early node editor front end.

- Typed nodes and sockets; only wires between matching types are allowed.
  Feedback loops (including a node feeding itself) are allowed.
- Nodes are defined in JSON files in `nodes/` (see `nodes/README.md`), including
  inline fields shown on unconnected inputs and node settings
- Projects are saved as `.vl` files; startup screen with recent projects
- Undo/redo for adding, deleting, moving, connecting and editing values
- Nodes with an app widget have an eye toggle in their header: whether the
  widget is shown in the compiled app (which lays widgets out automatically)
- Shift+A menu grouped by category

### Controls

| Action | Input |
|---|---|
| Add node | Shift+A (↑/↓ to move, Enter to open a category or add a node) |
| Select / move | Click / drag a node |
| Toggle in selection | Ctrl+click |
| Box select | Shift+drag on empty canvas |
| Deselect all | Click empty canvas |
| Delete selected | Delete / Backspace |
| Copy / paste / duplicate | Ctrl+C / Ctrl+V / Ctrl+D |
| Undo / redo | Ctrl+Z / Ctrl+Shift+Z or Ctrl+Y |
| New / open / save / save as | Ctrl+N / Ctrl+O / Ctrl+S / Ctrl+Shift+S |
| Connect | Drag from any socket to a compatible one |
| Move or delete a wire | Drag it off its input; drop on empty canvas to delete |
| Disconnect input | Right-click the input |
| Pan / zoom | Right-drag / mouse wheel |
| Frame all | Home, or the Frame All button |
| Compile options | Ctrl+B, or the Compile button (Enter compiles) |

## Structure

- `main.py` — starts the app: loads the node catalog and QML
- `node_catalog.py` — loads and validates the node JSON files
- `graph_model.py` — nodes, values, typed connections, undo/redo, clipboard
- `project.py` — project files, unsaved-changes tracking, recent projects, compile settings
- `compiler.py` — compile options and the (not yet implemented) compiler entry point
- `nodes/` — one JSON file per node type
- `ui/Main.qml` — application window: toolbar, File menu, inspector, startup popup, dialogs
- `ui/components/NodeCanvas.qml` — canvas: navigation, wires, selection, clipboard, add-node popup
- `ui/components/Node.qml` — a single node and its rows
- `ui/components/ValueWidget.qml` — inline value editors (number, string, select, checkbox)
- `ui/components/CompilePopup.qml` — compile options popup
- `ui/components/MessageBox.qml` — themed message / confirmation dialog
- `ui/components/ShortcutMenuItem.qml` — menu item with a shortcut hint
- `ui/components/SocketTypes.js` — shared colours for socket data types
- `requirements.txt` — Python dependency

## License

MIT — see [LICENSE](LICENSE).
