# VL — Visual Language

VL is a visual programming language for programming a RoboCars competition
robot. Programs are built as dataflow graphs, similar to Blender's node
editor: nodes have typed inputs and outputs connected by wires, and
incompatible types (e.g. `LidarScan` to `int32`) can't be connected.

VL is a visual front end for a compiler, not a runtime: the goal is to
translate the graph into C++ that runs on the robot.

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

Early node editor front end. VL is a visual front end for a compiler: the graph
will eventually be translated to C++, not run inside the app.

- Typed nodes and sockets; only wires between matching types are allowed
- Shift+A to add nodes, drag the header to move, Ctrl+click to multi-select, Delete to remove
- Drag from any socket to create a wire; drag a wire off an input to move or delete it
- Right-click an input to disconnect it, right-drag to pan, wheel to zoom

## Structure

- `main.py` — starts the Qt application, seeds a demo graph and loads QML
- `graph_model.py` — node catalog, node instances and typed connections
- `ui/Main.qml` — application window (toolbar, canvas, inspector)
- `ui/components/NodeCanvas.qml` — canvas: navigation, wires, selection, add-node popup
- `ui/components/Node.qml` — a single node and its sockets
- `ui/components/SocketTypes.js` — shared colours for socket data types
- `requirements.txt` — Python dependency

## License

MIT — see [LICENSE](LICENSE).
