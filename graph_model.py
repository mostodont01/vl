"""Graph model for the VL node editor.

The model owns the node catalog (which node types exist and what sockets
they have), the node instances placed on the canvas, and the typed
connections between them. QML only displays this state and asks the model
to change it; all validation happens here.
"""

from dataclasses import dataclass, field
from typing import Any

from PySide6.QtCore import QAbstractListModel, QModelIndex, Qt, Slot, Signal, Property


# ---------------------------------------------------------------------------
# Node catalog
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class SocketDef:
    id: str    # Stable identifier, used by connections. Never shown to the user.
    name: str  # Display label.
    type: str  # Data type, e.g. "LidarScan", "int32", "bool".


@dataclass(frozen=True)
class NodeDef:
    type_id: str
    title: str
    inputs: tuple[SocketDef, ...]
    outputs: tuple[SocketDef, ...]
    description: str = ""


NODE_DEFINITIONS: dict[str, NodeDef] = {
    "read_lidar": NodeDef(
        type_id="read_lidar",
        title="Read LiDAR",
        inputs=(),
        outputs=(
            SocketDef(id="scan", name="Scan", type="LidarScan"),
        ),
        description="Produces raw LiDAR range scan frames",
    ),
    "lidar_distance": NodeDef(
        type_id="lidar_distance",
        title="LiDAR Distance",
        inputs=(
            SocketDef(id="scan", name="Scan", type="LidarScan"),
            SocketDef(id="angle", name="Angle", type="int32"),
        ),
        outputs=(
            SocketDef(id="distance", name="Distance", type="int32"),
        ),
        description="Extracts radial distance at a specific bearing angle",
    ),
    "set_motor_speed": NodeDef(
        type_id="set_motor_speed",
        title="Set Motor Speed",
        inputs=(
            SocketDef(id="speed", name="Speed", type="int32"),
        ),
        outputs=(),
        description="Commands velocity setpoint to the drive controller",
    ),
    "constant_int": NodeDef(
        type_id="constant_int",
        title="Constant Int",
        inputs=(),
        outputs=(
            SocketDef(id="value", name="Value", type="int32"),
        ),
        description="Emits an integer literal value",
    ),
    "threshold": NodeDef(
        type_id="threshold",
        title="Threshold",
        inputs=(
            SocketDef(id="value", name="Value", type="int32"),
            SocketDef(id="threshold", name="Threshold", type="int32"),
        ),
        outputs=(
            SocketDef(id="result", name="Result", type="bool"),
        ),
        description="Compares value against threshold (value >= threshold)",
    ),
    "safety_gate": NodeDef(
        type_id="safety_gate",
        title="Safety Gate",
        inputs=(
            SocketDef(id="active", name="Active", type="bool"),
            SocketDef(id="speed_in", name="Speed In", type="int32"),
        ),
        outputs=(
            SocketDef(id="speed_out", name="Speed Out", type="int32"),
        ),
        description="Passes velocity when active is true; stops when false",
    ),
}


# ---------------------------------------------------------------------------
# Graph state
# ---------------------------------------------------------------------------

@dataclass
class Node:
    id: str     # Instance id, e.g. "read_lidar-0".
    type: str   # Key into NODE_DEFINITIONS.
    title: str
    x: float    # Position in canvas world coordinates.
    y: float
    # Sockets are stored as plain dicts ({id, name, type}) so they can be
    # handed to QML directly.
    inputs: list[dict[str, str]] = field(default_factory=list)
    outputs: list[dict[str, str]] = field(default_factory=list)
    parameters: dict[str, Any] = field(default_factory=dict)


@dataclass
class Connection:
    """A wire from an output socket to an input socket."""
    id: str
    source_node: str
    source_port: str
    target_node: str
    target_port: str
    data_type: str = ""


class GraphModel(QAbstractListModel):
    """Exposes nodes as list rows and connections as a QML property."""

    IdRole = int(Qt.ItemDataRole.UserRole) + 1
    TypeRole = IdRole + 1
    TitleRole = IdRole + 2
    XRole = IdRole + 3
    YRole = IdRole + 4
    InputsRole = IdRole + 5
    OutputsRole = IdRole + 6

    connectionsChanged = Signal()
    # Human-readable errors and status (e.g. a rejected connection).
    diagnosticsMessage = Signal(str)

    def __init__(self):
        super().__init__()
        self.nodes: list[Node] = []
        self.connections_dict: dict[str, Connection] = {}

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
            return node.title
        if role == self.XRole:
            return node.x
        if role == self.YRole:
            return node.y
        if role == self.InputsRole:
            return node.inputs
        if role == self.OutputsRole:
            return node.outputs

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
        """Catalog entries for the add-node popup."""
        return [
            {"typeId": d.type_id, "title": d.title, "description": d.description}
            for d in NODE_DEFINITIONS.values()
        ]

    # -- Lookup helpers -----------------------------------------------------

    def find_node(self, node_id: str) -> Node | None:
        return next((n for n in self.nodes if n.id == node_id), None)

    @staticmethod
    def find_socket(node: Node, socket_id: str, is_output: bool) -> dict[str, str] | None:
        sockets = node.outputs if is_output else node.inputs
        return next((s for s in sockets if s["id"] == socket_id), None)

    # -- Nodes --------------------------------------------------------------

    @Slot(str, float, float, result=str)
    def addNode(self, type_id: str, x: float, y: float) -> str:
        """Create a node of a catalog type. Returns its id, or "" on failure."""
        node_def = NODE_DEFINITIONS.get(type_id)
        if node_def is None:
            self.diagnosticsMessage.emit(f"Unknown node type: {type_id}")
            return ""

        # Use the smallest free instance number, so ids stay short and stable.
        used_numbers = set()
        for node in self.nodes:
            prefix, separator, suffix = node.id.rpartition("-")
            if prefix == type_id and separator and suffix.isdigit():
                used_numbers.add(int(suffix))

        instance_number = 0
        while instance_number in used_numbers:
            instance_number += 1

        row = len(self.nodes)
        self.beginInsertRows(QModelIndex(), row, row)
        self.nodes.append(
            Node(
                id=f"{type_id}-{instance_number}",
                type=type_id,
                title=node_def.title,
                x=x,
                y=y,
                inputs=[{"id": s.id, "name": s.name, "type": s.type} for s in node_def.inputs],
                outputs=[{"id": s.id, "name": s.name, "type": s.type} for s in node_def.outputs],
            )
        )
        self.endInsertRows()
        return self.nodes[row].id

    @Slot(str)
    def removeNode(self, node_id: str):
        """Remove a node together with every wire attached to it."""
        row = next((i for i, n in enumerate(self.nodes) if n.id == node_id), -1)
        if row == -1:
            return

        self.beginRemoveRows(QModelIndex(), row, row)
        del self.nodes[row]
        self.endRemoveRows()

        remaining = {
            cid: c
            for cid, c in self.connections_dict.items()
            if c.source_node != node_id and c.target_node != node_id
        }
        if len(remaining) != len(self.connections_dict):
            self.connections_dict = remaining
            self.connectionsChanged.emit()

    @Slot(str, float, float)
    def setNodePosition(self, node_id: str, x: float, y: float):
        for row, node in enumerate(self.nodes):
            if node.id == node_id:
                node.x = x
                node.y = y
                index = self.index(row, 0)
                self.dataChanged.emit(index, index, [self.XRole, self.YRole])
                return

    # -- Connections --------------------------------------------------------

    def _validate_connection(
        self,
        source_node: str,
        source_port: str,
        target_node: str,
        target_port: str,
    ) -> str | None:
        """Return an error message if the wire is not allowed, otherwise None."""
        if source_node == target_node:
            return f"Cannot connect node {source_node} to itself."

        s_node = self.find_node(source_node)
        t_node = self.find_node(target_node)
        if not s_node or not t_node:
            return "Connection failed: one of the nodes was not found."

        s_sock = self.find_socket(s_node, source_port, is_output=True)
        t_sock = self.find_socket(t_node, target_port, is_output=False)
        if not s_sock:
            return f"Source socket {source_port} not found on {s_node.title}."
        if not t_sock:
            return f"Target socket {target_port} not found on {t_node.title}."

        # Types must match exactly; there are no implicit conversions.
        if s_sock["type"] != t_sock["type"]:
            return (
                f"Type error: Cannot connect {s_sock['type']} ({s_node.title}.{s_sock['name']}) "
                f"to {t_sock['type']} ({t_node.title}.{t_sock['name']})."
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

        for cid, conn in list(self.connections_dict.items()):
            if conn.target_node == target_node and conn.target_port == target_port:
                del self.connections_dict[cid]

        s_node = self.find_node(source_node)
        t_node = self.find_node(target_node)
        s_sock = self.find_socket(s_node, source_port, is_output=True)
        t_sock = self.find_socket(t_node, target_port, is_output=False)

        conn_id = f"{source_node}:{source_port}->{target_node}:{target_port}"
        self.connections_dict[conn_id] = Connection(
            id=conn_id,
            source_node=source_node,
            source_port=source_port,
            target_node=target_node,
            target_port=target_port,
            data_type=s_sock["type"],
        )
        self.connectionsChanged.emit()
        self.diagnosticsMessage.emit(
            f"Connected: {s_node.title}.{s_sock['name']} → {t_node.title}.{t_sock['name']} [{s_sock['type']}]"
        )
        return True

    @Slot(str, result=bool)
    def removeConnection(self, connection_id: str) -> bool:
        if connection_id in self.connections_dict:
            del self.connections_dict[connection_id]
            self.connectionsChanged.emit()
            return True
        return False

    @Slot(str, str, result=bool)
    def disconnectInput(self, target_node: str, target_port: str) -> bool:
        """Remove the wire feeding the given input, if any."""
        to_delete = [
            cid
            for cid, c in self.connections_dict.items()
            if c.target_node == target_node and c.target_port == target_port
        ]
        for cid in to_delete:
            del self.connections_dict[cid]
        if to_delete:
            self.connectionsChanged.emit()
        return bool(to_delete)
