"""Node catalog: the node types VL knows about.

Each node type is defined by a JSON file (see nodes/README.md for the
format). Built-in nodes live in the app's nodes/ directory; nodes imported
into a project are stored inside the project file as "node packages": the
JSON plus the code files it lists. This module loads and validates both into
frozen dataclasses that the rest of the app uses.
"""

import json
from dataclasses import dataclass, field, replace
from pathlib import Path, PurePosixPath
from typing import Any


class CatalogError(Exception):
    """A node definition file is missing, malformed or inconsistent."""


WIDGET_KINDS = ("number", "string", "select", "checkbox")


def is_integer_type(data_type: str) -> bool:
    return data_type.startswith("int") or data_type.startswith("uint")


@dataclass(frozen=True)
class WidgetDef:
    """An inline editor for a value: shown for unconnected inputs and settings."""
    kind: str                       # One of WIDGET_KINDS.
    default: Any = None
    min: float | None = None        # number only
    max: float | None = None        # number only
    options: tuple[str, ...] = ()   # select only

    def coerce(self, value: Any, data_type: str) -> Any:
        """Convert a value (from QML or a project file) to this widget's value.

        Numbers are clamped to min/max and rounded for integer types.
        Raises ValueError if the value can't be used.
        """
        if self.kind == "number":
            if isinstance(value, bool):
                raise ValueError("expected a number")
            number = float(value)
            if self.min is not None:
                number = max(self.min, number)
            if self.max is not None:
                number = min(self.max, number)
            return int(round(number)) if is_integer_type(data_type) else number

        if self.kind == "string":
            return str(value)

        if self.kind == "select":
            if value not in self.options:
                raise ValueError(f"{value!r} is not one of {list(self.options)}")
            return value

        if self.kind == "checkbox":
            if not isinstance(value, bool):
                raise ValueError("expected true or false")
            return value

        raise ValueError(f"unknown widget kind {self.kind!r}")

    def to_qml(self, data_type: str) -> dict[str, Any]:
        return {
            "kind": self.kind,
            "default": self.default,
            "min": self.min,
            "max": self.max,
            "options": list(self.options),
            "integer": is_integer_type(data_type),
        }


@dataclass(frozen=True)
class SocketDef:
    id: str     # Stable identifier, used by connections and saved files.
    name: str   # Display label.
    type: str   # Data type, e.g. "LidarScan", "int32", "bool".
    widget: WidgetDef | None = None  # Inputs only: editor shown while unconnected.


@dataclass(frozen=True)
class SettingDef:
    """A value set on the node itself, with no socket."""
    id: str
    name: str
    type: str
    widget: WidgetDef
    # Only relevant to the app widget (e.g. its label): hidden while the
    # node's eye is closed.
    app_widget_only: bool = False


@dataclass(frozen=True)
class AppWidgetDef:
    """A widget this node shows in the compiled app (e.g. a number display).

    The widget is implemented in the node's own C++ code; class_name names
    the class there. The exact C++ interface is designed together with the
    compiler. The compiled app lays out all visible widgets automatically.
    """
    class_name: str
    options: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class NodeDef:
    type_id: str
    title: str
    inputs: tuple[SocketDef, ...]
    outputs: tuple[SocketDef, ...]
    settings: tuple[SettingDef, ...] = ()
    description: str = ""
    group: str = "Other"      # Shift+A menu section; also gives the node its colour.
    app_widget: AppWidgetDef | None = None
    code: tuple[str, ...] = ()  # Source files, relative to the JSON file.

    def socket_types(self) -> set[str]:
        return {s.type for s in self.inputs + self.outputs}

    def value_fields(self) -> dict[str, tuple[str, WidgetDef]]:
        """Every editable value on this node: {id: (data type, widget)}."""
        fields = {s.id: (s.type, s.widget) for s in self.inputs if s.widget}
        fields.update({s.id: (s.type, s.widget) for s in self.settings})
        return fields

    def default_values(self) -> dict[str, Any]:
        return {key: widget.default for key, (_, widget) in self.value_fields().items()}


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def _require(raw: dict, key: str, where: str, kind: type = str) -> Any:
    value = raw.get(key)
    if not isinstance(value, kind) or (kind is str and not value):
        raise CatalogError(f"{where}: '{key}' must be a non-empty {kind.__name__}")
    return value


def _parse_widget(raw: Any, data_type: str, where: str) -> WidgetDef:
    # "widget": "number" is shorthand for {"kind": "number"}.
    if isinstance(raw, str):
        raw = {"kind": raw}
    if not isinstance(raw, dict):
        raise CatalogError(f"{where}: 'widget' must be an object or a kind name")

    kind = raw.get("kind")
    if kind not in WIDGET_KINDS:
        raise CatalogError(f"{where}: widget kind must be one of {list(WIDGET_KINDS)}")

    options = tuple(raw.get("options", ()))
    if kind == "select" and (not options or not all(isinstance(o, str) for o in options)):
        raise CatalogError(f"{where}: select widget needs a non-empty list of string 'options'")

    fallback_default = {"number": 0, "string": "", "select": options[0] if options else None,
                        "checkbox": False}[kind]
    widget = WidgetDef(kind=kind, min=raw.get("min"), max=raw.get("max"), options=options)

    try:
        default = widget.coerce(raw.get("default", fallback_default), data_type)
    except (TypeError, ValueError) as e:
        raise CatalogError(f"{where}: invalid default: {e}") from None
    return replace(widget, default=default)


def _parse_socket(raw: Any, where: str, allow_widget: bool) -> SocketDef:
    if not isinstance(raw, dict):
        raise CatalogError(f"{where}: socket must be an object")
    sid = _require(raw, "id", where)
    where = f"{where} '{sid}'"
    data_type = _require(raw, "type", where)

    widget = None
    if "widget" in raw:
        if not allow_widget:
            raise CatalogError(f"{where}: outputs can't have widgets")
        widget = _parse_widget(raw["widget"], data_type, where)

    return SocketDef(id=sid, name=raw.get("name", sid), type=data_type, widget=widget)


def _parse_setting(raw: Any, where: str) -> SettingDef:
    if not isinstance(raw, dict):
        raise CatalogError(f"{where}: setting must be an object")
    sid = _require(raw, "id", where)
    where = f"{where} '{sid}'"
    data_type = _require(raw, "type", where)
    if "widget" not in raw:
        raise CatalogError(f"{where}: settings need a 'widget'")
    return SettingDef(id=sid, name=raw.get("name", sid), type=data_type,
                      widget=_parse_widget(raw["widget"], data_type, where),
                      app_widget_only=raw.get("app_widget_only", False) is True)


def _parse_app_widget(raw: Any, where: str) -> AppWidgetDef:
    if not isinstance(raw, dict):
        raise CatalogError(f"{where}: 'app_widget' must be an object")
    class_name = _require(raw, "class", f"{where} app_widget")
    return AppWidgetDef(class_name=class_name, options={k: v for k, v in raw.items() if k != "class"})


def _parse_code(raw: Any, where: str) -> tuple[str, ...]:
    """'code' is a path or a list of paths relative to the JSON file.

    Paths must stay inside the JSON's folder, so a node package can be
    copied into a project with its folder structure intact.
    """
    paths = [raw] if isinstance(raw, str) else raw
    if not isinstance(paths, list) or not all(isinstance(p, str) and p for p in paths):
        raise CatalogError(f"{where}: 'code' must be a path or a list of paths")

    result = []
    for p in paths:
        pure = PurePosixPath(p.replace("\\", "/"))
        if pure.is_absolute() or ".." in pure.parts:
            raise CatalogError(f"{where}: code path '{p}' must be relative and inside the node's folder")
        result.append(str(pure))
    _unique(result, f"{where} code")
    return tuple(result)


def _unique(ids: list[str], where: str):
    seen = set()
    for i in ids:
        if i in seen:
            raise CatalogError(f"{where}: duplicate id '{i}'")
        seen.add(i)


def parse_node_definition(raw: Any, where: str) -> NodeDef:
    if not isinstance(raw, dict):
        raise CatalogError(f"{where}: top level must be an object")

    type_id = _require(raw, "id", where)
    inputs = tuple(_parse_socket(s, f"{where} input", True) for s in raw.get("inputs", []))
    outputs = tuple(_parse_socket(s, f"{where} output", False) for s in raw.get("outputs", []))
    settings = tuple(_parse_setting(s, f"{where} setting") for s in raw.get("settings", []))

    if "app_widget" not in raw and any(s.app_widget_only for s in settings):
        raise CatalogError(f"{where}: 'app_widget_only' settings need the node to have an 'app_widget'")

    _unique([s.id for s in inputs], f"{where} inputs")
    _unique([s.id for s in outputs], f"{where} outputs")
    # Inputs and settings share the node's value storage, so their ids must not clash.
    _unique([s.id for s in inputs] + [s.id for s in settings], f"{where} inputs/settings")

    return NodeDef(
        type_id=type_id,
        title=raw.get("title", type_id),
        inputs=inputs,
        outputs=outputs,
        settings=settings,
        description=raw.get("description", ""),
        group=raw.get("group", "Other"),
        app_widget=_parse_app_widget(raw["app_widget"], where) if "app_widget" in raw else None,
        code=_parse_code(raw["code"], where) if "code" in raw else (),
    )


def load_node_definitions(directory: Path) -> dict[str, NodeDef]:
    """Load every *.json file in directory. Raises CatalogError on any problem."""
    if not directory.is_dir():
        raise CatalogError(f"node directory not found: {directory}")

    catalog: dict[str, NodeDef] = {}
    for path in sorted(directory.glob("*.json")):
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            raise CatalogError(f"{path.name}: invalid JSON: {e}") from None

        node_def = parse_node_definition(raw, path.name)
        if node_def.type_id in catalog:
            raise CatalogError(f"{path.name}: node id '{node_def.type_id}' is defined twice")
        catalog[node_def.type_id] = node_def

    return catalog


# ---------------------------------------------------------------------------
# Node packages (imported nodes)
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class NodePackage:
    """An imported node: its definition plus the files it was made from."""
    definition: NodeDef
    json_text: str
    files: dict[str, bytes]   # code path as written in the JSON -> file content


def node_package_from_files(json_text: str, files: dict[str, bytes], where: str) -> NodePackage:
    """Build a package from already-read content (e.g. from a project file)."""
    try:
        raw = json.loads(json_text)
    except json.JSONDecodeError as e:
        raise CatalogError(f"{where}: invalid JSON: {e}") from None
    node_def = parse_node_definition(raw, where)
    missing = [p for p in node_def.code if p not in files]
    if missing:
        raise CatalogError(f"{where}: missing code file(s): {', '.join(missing)}")
    return NodePackage(node_def, json_text, {p: files[p] for p in node_def.code})


def load_node_package(json_path: Path) -> NodePackage:
    """Read a node's JSON and every code file it lists (relative to the JSON)."""
    try:
        json_text = json_path.read_text(encoding="utf-8")
    except OSError as e:
        raise CatalogError(f"{json_path.name}: {e.strerror}") from None

    try:
        code = parse_node_definition(json.loads(json_text), json_path.name).code
    except json.JSONDecodeError as e:
        raise CatalogError(f"{json_path.name}: invalid JSON: {e}") from None

    files = {}
    for rel in code:
        try:
            files[rel] = (json_path.parent / rel).read_bytes()
        except OSError:
            raise CatalogError(f"{json_path.name}: code file not found: {json_path.parent / rel}") from None
    return node_package_from_files(json_text, files, json_path.name)
