"""Graph model for the VL node editor.

The model owns the node instances placed on the canvas, their values and the
typed connections between them. QML only displays this state and asks the
model to change it; all validation happens here.

Undo/redo works by snapshots: before every change the whole graph is stored
as a plain dict (the same shape as a saved project), and undo restores the
previous snapshot. Graphs are small, so this is cheap and it can't drift out
of sync with the actual operations.
"""

import copy
from dataclasses import dataclass, field
from typing import Any

from PySide6.QtCore import QAbstractListModel, QModelIndex, Qt, Slot, Signal, Property

from node_catalog import NodeDef


@dataclass
class Node:
    id: str     # Instance id, e.g. "read_lidar-0".
    type: str   # Key into the node catalog.
    x: float    # Position in canvas world coordinates.
    y: float
    # Current values of the node's settings and widget inputs, by id.
    values: dict[str, Any] = field(default_factory=dict)
    # Only meaningful for nodes with an app widget: show it in the compiled app.
    widget_visible: bool = True


@dataclass
class Connection:
    """A wire from an output socket to an input socket."""
    id: str
    source_node: str
    source_port: str
    target_node: str
    target_port: str
    data_type: str = ""


def connection_id(source_node: str, source_port: str, target_node: str, target_port: str) -> str:
    return f"{source_node}:{source_port}->{target_node}:{target_port}"


class GraphModel(QAbstractListModel):
    """Exposes nodes as list rows and connections as a QML property."""

    IdRole = int(Qt.ItemDataRole.UserRole) + 1
    TypeRole = IdRole + 1
    TitleRole = IdRole + 2
    XRole = IdRole + 3
    YRole = IdRole + 4
    InputsRole = IdRole + 5
    OutputsRole = IdRole + 6
    SettingsRole = IdRole + 7
    ValuesRole = IdRole + 8
    HasAppWidgetRole = IdRole + 9
    WidgetVisibleRole = IdRole + 10

    MAX_UNDO_STEPS = 200

    connectionsChanged = Signal()
    historyChanged = Signal()
    # Emitted after any change to the graph's content (used for "unsaved changes").
    graphChanged = Signal()
    # Human-readable errors (e.g. a rejected connection).
    diagnosticsMessage = Signal(str)
    issuesChanged = Signal()

    def __init__(self, catalog: dict[str, NodeDef]):
        super().__init__()
        self.catalog = catalog
        self.nodes: list[Node] = []
        self.connections_dict: dict[str, Connection] = {}
        self._undo_stack: list[dict] = []
        self._redo_stack: list[dict] = []
        self._clipboard: dict | None = None
        self.graphChanged.connect(self.issuesChanged)

        # Socket/setting lists in the shape QML wants, built once per node type.
        self._qml_sockets = {
            type_id: {
                "inputs": [self._socket_to_qml(s) for s in d.inputs],
                "outputs": [self._socket_to_qml(s) for s in d.outputs],
                "settings": [self._socket_to_qml(s) for s in d.settings],
            }
            for type_id, d in catalog.items()
        }

    @staticmethod
    def _socket_to_qml(s) -> dict[str, Any]:
        return {
            "id": s.id,
            "name": s.name,
            "type": s.type,
            "widget": s.widget.to_qml(s.type) if s.widget else None,
            "appWidgetOnly": getattr(s, "app_widget_only", False),
        }

    # -- QAbstractListModel interface ---------------------------------------

    def roleNames(self):
        return {
            self.IdRole: b"nodeId",
            self.TypeRole: b"nodeType",
            self.TitleRole: b"title",
            self.XRole: b"nodeX",
            self.YRole: b"nodeY",
            self.InputsRole: b"nodeInputs",
            self.OutputsRole: b"nodeOutputs",
            self.SettingsRole: b"nodeSettings",
            self.ValuesRole: b"nodeValues",
            self.HasAppWidgetRole: b"hasAppWidget",
            self.WidgetVisibleRole: b"widgetVisible",
        }

    def rowCount(self, parent=QModelIndex()):
        if parent.isValid():
            return 0
        return len(self.nodes)

    def data(self, index, role=Qt.ItemDataRole.DisplayRole):
        if not index.isValid() or not 0 <= index.row() < len(self.nodes):
            return None

        node = self.nodes[index.row()]

        if role == self.IdRole:
            return node.id
        if role == self.TypeRole:
            return node.type
        if role == self.TitleRole:
            return self.catalog[node.type].title
        if role == self.XRole:
            return node.x
        if role == self.YRole:
            return node.y
        if role == self.InputsRole:
            return self._qml_sockets[node.type]["inputs"]
        if role == self.OutputsRole:
            return self._qml_sockets[node.type]["outputs"]
        if role == self.SettingsRole:
            return self._qml_sockets[node.type]["settings"]
        if role == self.ValuesRole:
            return node.values
        if role == self.HasAppWidgetRole:
            return self.catalog[node.type].app_widget is not None
        if role == self.WidgetVisibleRole:
            return node.widget_visible

        return None

    # -- Properties for QML -------------------------------------------------

    @Property("QVariantList", notify=connectionsChanged)
    def connections(self) -> list[dict[str, Any]]:
        return [
            {
                "id": c.id,
                "sourceNode": c.source_node,
                "sourcePort": c.source_port,
                "targetNode": c.target_node,
                "targetPort": c.target_port,
                "dataType": c.data_type,
            }
            for c in self.connections_dict.values()
        ]

    @Property(int, notify=connectionsChanged)
    def connectionCount(self) -> int:
        return len(self.connections_dict)

    @Property("QVariantList", constant=True)
    def availableNodeTypes(self) -> list[dict[str, str]]:
        """Catalog entries for the add-node popup, sorted by category, then title."""
        return [
            {"typeId": d.type_id, "title": d.title, "description": d.description, "category": d.category}
            for d in sorted(self.catalog.values(), key=lambda d: (d.category.lower(), d.title.lower()))
        ]

    @Property(bool, notify=historyChanged)
    def canUndo(self) -> bool:
        return bool(self._undo_stack)

    @Property(bool, notify=historyChanged)
    def canRedo(self) -> bool:
        return bool(self._redo_stack)

    @Property("QVariantList", notify=issuesChanged)
    def issues(self) -> list[dict[str, str]]:
        """Problems in the graph, errors first: [{severity, nodeId, title, message}].

        error:   an input that can only be fed by a wire (no input field) is unconnected
        warning: a node has outputs but none of them is used
        """
        connected_inputs = {(c.target_node, c.target_port) for c in self.connections_dict.values()}
        used_nodes = {c.source_node for c in self.connections_dict.values()}
        errors, warnings = [], []

        for node in self.nodes:
            node_def = self.catalog[node.type]
            title = f"{node_def.title} ({node.id})"
            for s in node_def.inputs:
                if s.widget is None and (node.id, s.id) not in connected_inputs:
                    errors.append({"severity": "error", "nodeId": node.id, "title": title,
                                   "message": f"Input '{s.name}' ({s.type}) is not connected."})
            if node_def.outputs and node.id not in used_nodes:
                warnings.append({"severity": "warning", "nodeId": node.id, "title": title,
                                 "message": "Output is not used."})

        return errors + warnings

    # -- Lookup helpers -----------------------------------------------------

    def find_node(self, node_id: str) -> Node | None:
        return next((n for n in self.nodes if n.id == node_id), None)

    def _row_of(self, node_id: str) -> int:
        return next((i for i, n in enumerate(self.nodes) if n.id == node_id), -1)

    def find_socket(self, node: Node, socket_id: str, is_output: bool):
        node_def = self.catalog[node.type]
        sockets = node_def.outputs if is_output else node_def.inputs
        return next((s for s in sockets if s.id == socket_id), None)

    def _next_node_id(self, type_id: str, taken: set[str]) -> str:
        """Smallest free "<type>-<n>" id, so ids stay short and readable."""
        n = 0
        while f"{type_id}-{n}" in taken:
            n += 1
        return f"{type_id}-{n}"

    @Slot(str, result=bool)
    def hasNode(self, node_id: str) -> bool:
        return self.find_node(node_id) is not None

    # -- Snapshots, undo and redo -------------------------------------------

    def to_dict(self, node_ids: set[str] | None = None) -> dict[str, Any]:
        """The graph (or just the given nodes and the wires between them) as plain data."""
        nodes = [n for n in self.nodes if node_ids is None or n.id in node_ids]
        included = {n.id for n in nodes}
        return {
            "nodes": [self._node_to_dict(n) for n in nodes],
            "connections": [
                {
                    "source_node": c.source_node,
                    "source_socket": c.source_port,
                    "target_node": c.target_node,
                    "target_socket": c.target_port,
                }
                for c in self.connections_dict.values()
                if c.source_node in included and c.target_node in included
            ],
        }

    def _node_to_dict(self, node: Node) -> dict[str, Any]:
        data = {"id": node.id, "type": node.type, "x": node.x, "y": node.y,
                "values": copy.deepcopy(node.values)}
        if self.catalog[node.type].app_widget is not None:
            data["widget_visible"] = node.widget_visible
        return data

    def _build(self, data: dict) -> tuple[list[Node], dict[str, Connection], list[str]]:
        """Turn plain data into nodes and connections, skipping anything invalid.

        Returns (nodes, connections, warnings).
        """
        warnings: list[str] = []
        nodes: list[Node] = []
        by_id: dict[str, Node] = {}

        for raw in data.get("nodes", []):
            try:
                node_id, type_id = str(raw["id"]), str(raw["type"])
                x, y = float(raw.get("x", 0)), float(raw.get("y", 0))
            except (KeyError, TypeError, ValueError):
                warnings.append(f"Skipped a malformed node entry: {raw!r}")
                continue

            node_def = self.catalog.get(type_id)
            if node_def is None:
                warnings.append(f"Skipped node {node_id}: unknown node type '{type_id}'.")
                continue
            if node_id in by_id:
                warnings.append(f"Skipped node {node_id}: duplicate id.")
                continue

            values = node_def.default_values()
            raw_values = raw.get("values", {})
            for key, (data_type, widget) in node_def.value_fields().items():
                if key in raw_values:
                    try:
                        values[key] = widget.coerce(raw_values[key], data_type)
                    except (TypeError, ValueError):
                        warnings.append(f"Node {node_id}: invalid value for '{key}', using default.")

            node = Node(id=node_id, type=type_id, x=x, y=y, values=values,
                        widget_visible=raw.get("widget_visible", True) is not False)
            nodes.append(node)
            by_id[node_id] = node

        connections: dict[str, Connection] = {}
        for raw in data.get("connections", []):
            try:
                sn, sp = raw["source_node"], raw["source_socket"]
                tn, tp = raw["target_node"], raw["target_socket"]
            except (KeyError, TypeError):
                warnings.append(f"Skipped a malformed connection entry: {raw!r}")
                continue

            s_node, t_node = by_id.get(sn), by_id.get(tn)
            s_sock = self.find_socket(s_node, sp, True) if s_node else None
            t_sock = self.find_socket(t_node, tp, False) if t_node else None
            if not s_sock or not t_sock or s_sock.type != t_sock.type:
                warnings.append(f"Skipped invalid connection {sn}.{sp} -> {tn}.{tp}.")
                continue
            if any(c.target_node == tn and c.target_port == tp for c in connections.values()):
                warnings.append(f"Skipped extra connection into {tn}.{tp}.")
                continue

            cid = connection_id(sn, sp, tn, tp)
            connections[cid] = Connection(cid, sn, sp, tn, tp, s_sock.type)

        return nodes, connections, warnings

    def _replace_all(self, nodes: list[Node], connections: dict[str, Connection]):
        self.beginResetModel()
        self.nodes = nodes
        self.connections_dict = connections
        self.endResetModel()
        self.connectionsChanged.emit()
        self.graphChanged.emit()

    def _record(self):
        """Store the current state for undo. Call right before changing the graph."""
        self._undo_stack.append(self.to_dict())
        if len(self._undo_stack) > self.MAX_UNDO_STEPS:
            del self._undo_stack[0]
        self._redo_stack.clear()
        self.historyChanged.emit()

    @Slot()
    def undo(self):
        if not self._undo_stack:
            return
        self._redo_stack.append(self.to_dict())
        nodes, connections, _ = self._build(self._undo_stack.pop())
        self._replace_all(nodes, connections)
        self.historyChanged.emit()

    @Slot()
    def redo(self):
        if not self._redo_stack:
            return
        self._undo_stack.append(self.to_dict())
        nodes, connections, _ = self._build(self._redo_stack.pop())
        self._replace_all(nodes, connections)
        self.historyChanged.emit()

    def clear(self):
        """Empty graph with no undo history (new project)."""
        self.load_dict({})

    def load_dict(self, data: dict) -> list[str]:
        """Replace the graph with loaded data and reset history. Returns warnings."""
        nodes, connections, warnings = self._build(data)
        self._undo_stack.clear()
        self._redo_stack.clear()
        self._replace_all(nodes, connections)
        self.historyChanged.emit()
        return warnings

    # -- Nodes --------------------------------------------------------------

    @Slot(str, float, float, result=str)
    def addNode(self, type_id: str, x: float, y: float) -> str:
        """Create a node of a catalog type. Returns its id, or "" on failure."""
        node_def = self.catalog.get(type_id)
        if node_def is None:
            self.diagnosticsMessage.emit(f"Unknown node type: {type_id}")
            return ""

        self._record()
        node = Node(
            id=self._next_node_id(type_id, {n.id for n in self.nodes}),
            type=type_id,
            x=x,
            y=y,
            values=node_def.default_values(),
        )
        row = len(self.nodes)
        self.beginInsertRows(QModelIndex(), row, row)
        self.nodes.append(node)
        self.endInsertRows()
        self.graphChanged.emit()
        return node.id

    @Slot("QVariantList")
    def removeNodes(self, node_ids: list[str]):
        """Remove nodes together with every wire attached to them (one undo step)."""
        ids = {i for i in node_ids if self.find_node(i)}
        if not ids:
            return

        self._record()
        # Remove from the end so earlier row numbers stay valid.
        for row in sorted((self._row_of(i) for i in ids), reverse=True):
            self.beginRemoveRows(QModelIndex(), row, row)
            del self.nodes[row]
            self.endRemoveRows()

        remaining = {
            cid: c
            for cid, c in self.connections_dict.items()
            if c.source_node not in ids and c.target_node not in ids
        }
        if len(remaining) != len(self.connections_dict):
            self.connections_dict = remaining
            self.connectionsChanged.emit()
        self.graphChanged.emit()

    @Slot("QVariantList")
    def moveNodes(self, moves: list[dict]):
        """Set positions of several nodes at once: [{id, x, y}, ...] (one undo step)."""
        changes = []
        for m in moves:
            row = self._row_of(m["id"])
            if row != -1:
                node = self.nodes[row]
                if (node.x, node.y) != (m["x"], m["y"]):
                    changes.append((row, float(m["x"]), float(m["y"])))
        if not changes:
            return

        self._record()
        for row, x, y in changes:
            self.nodes[row].x = x
            self.nodes[row].y = y
            index = self.index(row, 0)
            self.dataChanged.emit(index, index, [self.XRole, self.YRole])
        self.graphChanged.emit()

    @Slot(str, str, "QVariant")
    def setNodeValue(self, node_id: str, key: str, value: Any):
        """Set a setting or widget-input value. Invalid values are rejected."""
        row = self._row_of(node_id)
        if row == -1:
            return
        node = self.nodes[row]
        field_def = self.catalog[node.type].value_fields().get(key)
        if field_def is None:
            return

        data_type, widget = field_def
        try:
            value = widget.coerce(value, data_type)
        except (TypeError, ValueError) as e:
            self.diagnosticsMessage.emit(f"Invalid value for {key}: {e}")
            # Still notify, so the widget redisplays the old value.
            index = self.index(row, 0)
            self.dataChanged.emit(index, index, [self.ValuesRole])
            return

        if node.values.get(key) == value:
            index = self.index(row, 0)
            self.dataChanged.emit(index, index, [self.ValuesRole])
            return

        self._record()
        # Assign a new dict so QML sees a changed value.
        node.values = {**node.values, key: value}
        index = self.index(row, 0)
        self.dataChanged.emit(index, index, [self.ValuesRole])
        self.graphChanged.emit()

    @Slot(str, bool)
    def setWidgetVisible(self, node_id: str, visible: bool):
        """Show or hide a node's widget in the compiled app (the header eye)."""
        row = self._row_of(node_id)
        if row == -1:
            return
        node = self.nodes[row]
        if self.catalog[node.type].app_widget is None or node.widget_visible == visible:
            return

        self._record()
        node.widget_visible = visible
        index = self.index(row, 0)
        self.dataChanged.emit(index, index, [self.WidgetVisibleRole])
        self.graphChanged.emit()

    # -- Clipboard ----------------------------------------------------------

    def _insert_fragment(self, fragment: dict, dx: float, dy: float) -> list[str]:
        """Add copies of the fragment's nodes and wires with fresh ids, offset by (dx, dy)."""
        taken = {n.id for n in self.nodes}
        id_map: dict[str, str] = {}
        new_nodes: list[Node] = []

        nodes, connections, _ = self._build(fragment)
        for node in nodes:
            new_id = self._next_node_id(node.type, taken)
            taken.add(new_id)
            id_map[node.id] = new_id
            new_nodes.append(Node(new_id, node.type, node.x + dx, node.y + dy, node.values,
                                  node.widget_visible))

        if not new_nodes:
            return []

        self._record()
        first = len(self.nodes)
        self.beginInsertRows(QModelIndex(), first, first + len(new_nodes) - 1)
        self.nodes.extend(new_nodes)
        self.endInsertRows()

        for c in connections.values():
            sn, tn = id_map[c.source_node], id_map[c.target_node]
            cid = connection_id(sn, c.source_port, tn, c.target_port)
            self.connections_dict[cid] = Connection(cid, sn, c.source_port, tn, c.target_port, c.data_type)
        if connections:
            self.connectionsChanged.emit()

        self.graphChanged.emit()
        return [n.id for n in new_nodes]

    @Slot("QVariantList")
    def copyNodes(self, node_ids: list[str]):
        """Copy nodes and the wires between them to the internal clipboard."""
        if node_ids:
            self._clipboard = self.to_dict(set(node_ids))

    @Slot(float, float, result="QVariantList")
    def pasteNodes(self, x: float, y: float) -> list[str]:
        """Paste the clipboard with its top-left corner at (x, y). Returns new ids."""
        if not self._clipboard or not self._clipboard["nodes"]:
            return []
        left = min(n["x"] for n in self._clipboard["nodes"])
        top = min(n["y"] for n in self._clipboard["nodes"])
        return self._insert_fragment(self._clipboard, x - left, y - top)

    @Slot("QVariantList", float, float, result="QVariantList")
    def duplicateNodes(self, node_ids: list[str], dx: float, dy: float) -> list[str]:
        """Copy nodes in place, offset by (dx, dy), without touching the clipboard."""
        return self._insert_fragment(self.to_dict(set(node_ids)), dx, dy)

    # -- Connections --------------------------------------------------------

    def _validate_connection(
        self,
        source_node: str,
        source_port: str,
        target_node: str,
        target_port: str,
    ) -> str | None:
        """Return an error message if the wire is not allowed, otherwise None.

        Cycles (including a node feeding itself) are allowed: they are
        feedback loops, where a node waits for its next input.
        """
        s_node = self.find_node(source_node)
        t_node = self.find_node(target_node)
        if not s_node or not t_node:
            return "Connection failed: one of the nodes was not found."

        s_title = self.catalog[s_node.type].title
        t_title = self.catalog[t_node.type].title
        s_sock = self.find_socket(s_node, source_port, is_output=True)
        t_sock = self.find_socket(t_node, target_port, is_output=False)
        if not s_sock:
            return f"Source socket {source_port} not found on {s_title}."
        if not t_sock:
            return f"Target socket {target_port} not found on {t_title}."

        # Types must match exactly; there are no implicit conversions.
        if s_sock.type != t_sock.type:
            return (
                f"Type error: Cannot connect {s_sock.type} ({s_title}.{s_sock.name}) "
                f"to {t_sock.type} ({t_title}.{t_sock.name})."
            )

        return None

    @Slot(str, str, str, str, result=bool)
    def isConnectionAllowed(
        self,
        source_node: str,
        source_port: str,
        target_node: str,
        target_port: str,
    ) -> bool:
        """Side-effect-free check, used by the canvas while dragging a wire."""
        return self._validate_connection(source_node, source_port, target_node, target_port) is None

    def _connect(self, source_node: str, source_port: str, target_node: str, target_port: str):
        """Add a (validated) wire, replacing any wire already on the target input."""
        for cid, conn in list(self.connections_dict.items()):
            if conn.target_node == target_node and conn.target_port == target_port:
                del self.connections_dict[cid]

        s_sock = self.find_socket(self.find_node(source_node), source_port, is_output=True)
        cid = connection_id(source_node, source_port, target_node, target_port)
        self.connections_dict[cid] = Connection(
            cid, source_node, source_port, target_node, target_port, s_sock.type
        )

    @Slot(str, str, str, str, result=bool)
    def addConnection(
        self,
        source_node: str,
        source_port: str,
        target_node: str,
        target_port: str,
    ) -> bool:
        """Connect an output to an input.

        An input accepts a single wire, so an existing wire on the target input
        is replaced. Outputs may fan out to any number of inputs.
        """
        error = self._validate_connection(source_node, source_port, target_node, target_port)
        if error:
            self.diagnosticsMessage.emit(error)
            return False

        if connection_id(source_node, source_port, target_node, target_port) in self.connections_dict:
            return True  # Already exists; nothing to do.

        self._record()
        self._connect(source_node, source_port, target_node, target_port)
        self.connectionsChanged.emit()
        self.graphChanged.emit()
        return True

    @Slot(str, str, str, str, str, result=bool)
    def rerouteConnection(
        self,
        old_connection_id: str,
        source_node: str,
        source_port: str,
        target_node: str,
        target_port: str,
    ) -> bool:
        """Replace one wire with another as a single undo step."""
        if old_connection_id not in self.connections_dict:
            return False
        error = self._validate_connection(source_node, source_port, target_node, target_port)
        if error:
            self.diagnosticsMessage.emit(error)
            return False

        self._record()
        del self.connections_dict[old_connection_id]
        self._connect(source_node, source_port, target_node, target_port)
        self.connectionsChanged.emit()
        self.graphChanged.emit()
        return True

    @Slot(str, result=bool)
    def removeConnection(self, connection_id: str) -> bool:
        if connection_id not in self.connections_dict:
            return False
        self._record()
        del self.connections_dict[connection_id]
        self.connectionsChanged.emit()
        self.graphChanged.emit()
        return True

    @Slot(str, str, result=bool)
    def disconnectInput(self, target_node: str, target_port: str) -> bool:
        """Remove the wire feeding the given input, if any."""
        to_delete = [
            cid
            for cid, c in self.connections_dict.items()
            if c.target_node == target_node and c.target_port == target_port
        ]
        if not to_delete:
            return False
        self._record()
        for cid in to_delete:
            del self.connections_dict[cid]
        self.connectionsChanged.emit()
        self.graphChanged.emit()
        return True
