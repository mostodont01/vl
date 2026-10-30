"""Projects: new / open / save, unsaved-changes tracking, recent projects,
compile settings, the colour palette and imported nodes.

A project file (*.vl) is a zip archive, like Blender's .blend:

    project.json            graph, compile settings, palette, imported node ids
    nodes/<id>/node.json    one folder per imported node: its JSON ...
    nodes/<id>/<code path>  ... and the code files it lists, at the same relative paths

project.json:

    {
        "format": "vl-project",
        "version": 2,
        "nodes": [{"id", "type", "x", "y", "values", "widget_visible"?}, ...],
        "connections": [{"source_node", "source_socket", "target_node", "target_socket"}, ...],
        "compile": {"language", "target", "build_type", "output_dir", "executable_name", "fullscreen"},
        "palette": {"groups": {name: "#rrggbb"}, "types": {name: "#rrggbb"}},
        "imported_nodes": {id: {"source": original JSON path}}
    }

Version 1 files (plain JSON, no zip) still open.
"""

import hashlib
import json
import os
import zipfile
from pathlib import Path
from typing import Any

from PySide6.QtCore import QObject, QSettings, QUrl, Property, Signal, Slot

import compiler
from builder import Builder
from graph_model import GraphModel
from node_catalog import CatalogError, NodeDef, NodePackage, load_node_package, node_package_from_files

FILE_FORMAT = "vl-project"
FILE_VERSION = 2
FILE_SUFFIX = ".vl"
PROJECT_ENTRY = "project.json"
MAX_RECENT = 5

# Offered in colour pickers, and used (in order) to suggest colours for new
# groups and socket types.
PRESET_COLORS = [
    "#72a7ff", "#4ade80", "#f59e0b", "#f472b6", "#c084fc", "#2dd4bf",
    "#f87171", "#facc15", "#60a5fa", "#a3e635", "#fb923c", "#94a3b8",
]


def _to_path(location: str) -> Path:
    """Accept both plain paths and file:// URLs (what QML file dialogs return)."""
    if location.startswith("file:"):
        location = QUrl(location).toLocalFile()
    return Path(location)


def _valid_color(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 7 and value.startswith("#") \
        and all(c in "0123456789abcdefABCDEF" for c in value[1:])


def load_palette(raw: Any) -> dict[str, dict[str, str]]:
    """{"groups": {...}, "types": {...}} with invalid entries dropped."""
    palette: dict[str, dict[str, str]] = {"groups": {}, "types": {}}
    if isinstance(raw, dict):
        for section in palette:
            entries = raw.get(section)
            if isinstance(entries, dict):
                palette[section] = {str(k): v.lower() for k, v in entries.items() if _valid_color(v)}
    return palette


class Project(QObject):
    stateChanged = Signal()         # file path or dirty flag changed
    recentChanged = Signal()
    compileSettingsChanged = Signal()
    paletteChanged = Signal()
    importedNodesChanged = Signal()
    # Something the user should be told about in a dialog: (title, text).
    messageRaised = Signal(str, str)
    # A short message for a toast that fades by itself.
    notice = Signal(str)
    # An import added groups/socket types that got suggested colours:
    # (group names, type names). The UI lets the user adjust them.
    colorsSuggested = Signal("QVariantList", "QVariantList")

    def __init__(self, graph: GraphModel, builtin_catalog: dict[str, NodeDef], builtin_dir: Path,
                 default_palette: dict, builder: Builder):
        super().__init__()
        self._graph = graph
        self._builtin = dict(builtin_catalog)
        # Built-in node id -> its JSON file (for loading its code when compiling).
        self._builtin_files: dict[str, Path] = {}
        for path in builtin_dir.glob("*.json"):
            node_id = json.loads(path.read_text(encoding="utf-8")).get("id")
            if node_id in builtin_catalog:
                self._builtin_files[node_id] = path
        self._builder = builder
        self._default_palette = load_palette(default_palette)
        self._path: Path | None = None
        self._settings = QSettings("VL", "VL")
        self._recent: list[str] = self._load_recent()
        self._compile_settings = dict(compiler.DEFAULT_SETTINGS)
        self._palette = load_palette(self._default_palette)
        self._imported: dict[str, NodePackage] = {}
        self._import_sources: dict[str, str] = {}
        self._dirty = False

        self._apply_catalog()
        self._fill_missing_colors()
        self._saved_key = self._state_key()
        graph.graphChanged.connect(self._update_dirty)
        graph.graphChanged.connect(self.importedNodesChanged)  # usage counts

    # -- Unsaved-changes tracking -------------------------------------------

    def _project_dict(self) -> dict[str, Any]:
        """Everything that goes into project.json."""
        return {
            "format": FILE_FORMAT,
            "version": FILE_VERSION,
            **self._graph.to_dict(),
            "compile": self._compile_settings,
            "palette": self._palette,
            "imported_nodes": {nid: {"source": self._import_sources.get(nid, "")} for nid in self._imported},
        }

    def _state_key(self) -> str:
        # Include imported node content, so re-importing changed files counts as a change.
        packages = {
            nid: [pkg.json_text, {p: hashlib.sha1(b).hexdigest() for p, b in pkg.files.items()}]
            for nid, pkg in self._imported.items()
        }
        return json.dumps([self._project_dict(), packages], sort_keys=True)

    def _mark_saved(self):
        self._saved_key = self._state_key()
        self._update_dirty()

    def _update_dirty(self):
        # Compare content rather than counting edits, so undoing back to the
        # saved state counts as "no unsaved changes".
        if not hasattr(self, "_saved_key"):
            return  # Still initialising.
        dirty = self._state_key() != self._saved_key
        if dirty != self._dirty:
            self._dirty = dirty
            self.stateChanged.emit()

    # -- Properties ---------------------------------------------------------

    @Property(bool, notify=stateChanged)
    def isDirty(self) -> bool:
        return self._dirty

    @Property(bool, notify=stateChanged)
    def hasFilePath(self) -> bool:
        return self._path is not None

    @Property(str, notify=stateChanged)
    def filePath(self) -> str:
        return str(self._path) if self._path else ""

    @Property(str, notify=stateChanged)
    def displayName(self) -> str:
        return self._path.stem if self._path else "Untitled"

    @Property("QVariantMap", notify=compileSettingsChanged)
    def compileSettings(self) -> dict[str, Any]:
        return dict(self._compile_settings)

    @Property("QVariantMap", constant=True)
    def compileChoices(self) -> dict[str, list[dict[str, str]]]:
        """Options for the Compile popup's drop-downs: {setting: [{value, label}]}."""
        def entries(pairs):
            return [{"value": v, "label": label} for v, label in pairs]
        return {
            "language": entries(compiler.LANGUAGES),
            "target": entries(compiler.TARGETS),
            "build_type": entries(compiler.BUILD_TYPES),
        }

    @Property(str, notify=stateChanged)
    def defaultOutputDir(self) -> str:
        """Where builds go when no output folder is chosen ("" if the project isn't saved)."""
        return str(self._path.parent / "build") if self._path else ""

    @Property("QVariantList", notify=recentChanged)
    def recentProjects(self) -> list[dict[str, Any]]:
        return [
            {"path": p, "name": Path(p).stem, "folder": str(Path(p).parent), "exists": Path(p).is_file()}
            for p in self._recent
        ]

    @Property("QVariantMap", notify=paletteChanged)
    def groupColors(self) -> dict[str, str]:
        return dict(self._palette["groups"])

    @Property("QVariantMap", notify=paletteChanged)
    def typeColors(self) -> dict[str, str]:
        return dict(self._palette["types"])

    @Property("QVariantList", constant=True)
    def presetColors(self) -> list[str]:
        return PRESET_COLORS

    @Property("QVariantList", notify=importedNodesChanged)
    def importedNodes(self) -> list[dict[str, Any]]:
        used: dict[str, int] = {}
        for n in self._graph.nodes:
            used[n.type] = used.get(n.type, 0) + 1
        return [
            {
                "id": nid,
                "title": pkg.definition.title,
                "group": pkg.definition.group,
                "files": ["node.json", *pkg.files],
                "source": self._import_sources.get(nid, ""),
                "useCount": used.get(nid, 0),
            }
            for nid, pkg in sorted(self._imported.items(), key=lambda item: item[1].definition.title.lower())
        ]

    @Property(str, notify=recentChanged)
    def lastImportFolder(self) -> str:
        """file:// URL of the folder the last node was imported from ("" if none)."""
        folder = self._settings.value("lastImportFolder", "")
        return QUrl.fromLocalFile(folder).toString() if folder else ""

    # -- Project actions ----------------------------------------------------

    @Slot()
    def newProject(self):
        self._imported = {}
        self._import_sources = {}
        self._apply_catalog()
        self._graph.clear()
        self._set_compile_settings(dict(compiler.DEFAULT_SETTINGS))
        self._set_palette(load_palette(self._default_palette))
        self._fill_missing_colors()
        self._set_path(None)
        self._mark_saved()

    @Slot(str, result=bool)
    def openProject(self, location: str) -> bool:
        path = _to_path(location)
        if path.suffix != FILE_SUFFIX:
            self.messageRaised.emit("Could not open project", f"{path.name} is not a {FILE_SUFFIX} file.")
            return False

        try:
            data, packages, warnings = self._read_file(path)
        except OSError as e:
            self.messageRaised.emit("Could not open project", f"{path}\n\n{e.strerror}")
            return False
        except (ValueError, zipfile.BadZipFile) as e:
            self.messageRaised.emit("Could not open project", f"{path.name}: {e}")
            return False

        self._imported = packages
        self._import_sources = {
            nid: str(info.get("source", ""))
            for nid, info in (data.get("imported_nodes") or {}).items()
            if nid in packages and isinstance(info, dict)
        }
        warnings += self._apply_catalog()
        warnings += self._graph.load_dict(data)
        self._set_compile_settings(compiler.load_settings(data.get("compile")))
        # Version 1 files have no palette: start from the defaults.
        self._set_palette(load_palette(data["palette"]) if "palette" in data
                          else load_palette(self._default_palette))
        self._fill_missing_colors()
        self._set_path(path)
        self._mark_saved()
        self._add_recent(path)

        if warnings:
            shown = warnings[:20]
            if len(warnings) > len(shown):
                shown.append(f"... and {len(warnings) - len(shown)} more.")
            self.messageRaised.emit("Project opened with problems", "\n".join(shown))
        return True

    @Slot(result=bool)
    def save(self) -> bool:
        """Save to the current file. Returns False if there is none (use saveAs)."""
        if self._path is None:
            return False
        return self._write(self._path)

    @Slot(str, result=bool)
    def saveAs(self, location: str) -> bool:
        path = _to_path(location)
        if path.suffix != FILE_SUFFIX:
            path = path.with_name(path.name + FILE_SUFFIX)
        if not self._write(path):
            return False
        self._set_path(path)
        self._add_recent(path)
        return True

    # -- Compile ------------------------------------------------------------

    @Slot(str, "QVariant")
    def setCompileSetting(self, key: str, value: Any):
        if key == "output_dir" and value:
            value = str(_to_path(str(value)))  # Folder dialogs return file:// URLs.
        try:
            value = compiler.coerce_setting(key, value)
        except ValueError as e:
            self.messageRaised.emit("Invalid compile setting", str(e))
            return
        if self._compile_settings.get(key) != value:
            self._set_compile_settings({**self._compile_settings, key: value})

    @Slot(result=bool)
    def compileProject(self) -> bool:
        """Generate the C++ project and start building it. Progress goes to the builder's log."""
        builder = self._builder
        builder.begin()
        settings = self._compile_settings

        name = settings["executable_name"] or (self._path.stem if self._path else "app")
        graph = self._graph.to_dict()
        problems = [f"{i['title']}: {i['message']}" for i in self._graph.issues if i["severity"] == "error"]

        output_dir = settings["output_dir"] or self.defaultOutputDir
        if not output_dir:
            problems.insert(0, "The project isn't saved yet, so there's no default build folder. "
                               "Save the project or choose an output folder.")
        packages: dict[str, NodePackage] = {}
        for type_id in sorted({n["type"] for n in graph["nodes"]}):
            if type_id in self._imported:
                packages[type_id] = self._imported[type_id]
            elif type_id in self._builtin_files:
                try:
                    packages[type_id] = load_node_package(self._builtin_files[type_id])
                except CatalogError as e:
                    problems.append(str(e))

        builder.append(f"Compiling {name} for {settings['target']} ({settings['build_type']})")
        if output_dir:
            output_path = _to_path(output_dir)
            if not output_path.is_absolute() and self._path:
                output_path = self._path.parent / output_path
            output_path = output_path.resolve()
            result = compiler.generate_project(graph, self._graph.catalog, packages, problems,
                                               settings, output_path, name)
        else:
            result = compiler.GenerateResult(False, problems)

        if not result.ok:
            for message in result.messages:
                builder.append(f"  • {message}")
            count = len(result.messages)
            builder.fail(f"{count} problem{'s' if count != 1 else ''} to fix first; nothing was built.")
            return False

        for message in result.messages:
            builder.append(message)
        builder.build(output_path, settings, name, result.gui)
        return True

    # -- Palette ------------------------------------------------------------

    @Slot(str, str)
    def setGroupColor(self, name: str, color: str):
        self._set_color("groups", name, color)

    @Slot(str, str)
    def setTypeColor(self, name: str, color: str):
        self._set_color("types", name, color)

    def _set_color(self, section: str, name: str, color: str):
        color = color.lower()
        if not _valid_color(color) or self._palette[section].get(name) == color:
            return
        palette = {k: dict(v) for k, v in self._palette.items()}
        palette[section][name] = color
        self._set_palette(palette)

    def _fill_missing_colors(self) -> tuple[list[str], list[str]]:
        """Give every group and socket type in the catalog a colour.

        Missing ones get the default palette's colour if it has one, otherwise
        the next preset colour not used yet. Returns the names that were added.
        """
        catalog = self._graph.catalog.values()
        groups = {d.group for d in catalog}
        types = set().union(*(d.socket_types() for d in catalog))
        palette = {k: dict(v) for k, v in self._palette.items()}
        added: dict[str, list[str]] = {"groups": [], "types": []}

        for section, names in (("groups", groups), ("types", types)):
            for name in sorted(names - palette[section].keys()):
                color = self._default_palette[section].get(name)
                if color is None:
                    used = set(palette[section].values())
                    color = next((c for c in PRESET_COLORS if c not in used),
                                 PRESET_COLORS[len(palette[section]) % len(PRESET_COLORS)])
                palette[section][name] = color
                added[section].append(name)

        if added["groups"] or added["types"]:
            self._set_palette(palette)
        return added["groups"], added["types"]

    # -- Imported nodes -----------------------------------------------------

    @Slot(str, bool, str, result=str)
    def importNode(self, location: str, allow_replace: bool, expected_id: str) -> str:
        """Import a node from its JSON file (plus the code files it lists).

        Returns "ok", "error" (already reported), or "exists" when a node with
        the same id is already imported and allow_replace is false, so the UI
        can ask before replacing. expected_id (for re-import) must match the
        file's id if given.
        """
        path = _to_path(location)
        try:
            package = load_node_package(path)
        except CatalogError as e:
            self.messageRaised.emit("Could not import node", str(e))
            return "error"

        node_def = package.definition
        nid = node_def.type_id
        if expected_id and nid != expected_id:
            self.messageRaised.emit(
                "Could not re-import node",
                f"{path.name} defines the node '{nid}', not '{expected_id}'.",
            )
            return "error"
        if nid in self._builtin:
            self.messageRaised.emit(
                "Could not import node",
                f"'{nid}' is the id of a built-in node. Give the node a different \"id\" in {path.name}.",
            )
            return "error"
        if nid in self._imported and not allow_replace:
            return "exists"

        replaced = nid in self._imported
        self._imported = {**self._imported, nid: package}
        self._import_sources[nid] = str(path.resolve())
        self._settings.setValue("lastImportFolder", str(path.resolve().parent))
        self.recentChanged.emit()  # lastImportFolder

        warnings = self._apply_catalog()
        new_groups, new_types = self._fill_missing_colors()
        self._update_dirty()

        self.notice.emit(f"{'Updated' if replaced else 'Imported'} node “{node_def.title}”")
        if warnings:
            self.messageRaised.emit("Node imported with problems", "\n".join(warnings[:20]))
        if new_groups or new_types:
            self.colorsSuggested.emit(new_groups, new_types)
        return "ok"

    @Slot(str)
    def removeImportedNode(self, node_id: str):
        """Remove an imported node type, and every node of that type in the graph."""
        if node_id not in self._imported:
            return
        title = self._imported[node_id].definition.title
        self._imported = {k: v for k, v in self._imported.items() if k != node_id}
        self._import_sources.pop(node_id, None)
        self._apply_catalog()
        self._update_dirty()
        self.notice.emit(f"Removed node “{title}”")

    @Slot(str, result=str)
    def importSourceFolder(self, node_id: str) -> str:
        """file:// URL of the folder a node was imported from (for re-import)."""
        source = self._import_sources.get(node_id, "")
        return QUrl.fromLocalFile(str(Path(source).parent)).toString() if source else self.lastImportFolder

    # -- Internals ----------------------------------------------------------

    def _apply_catalog(self) -> list[str]:
        """Give the graph the built-in nodes plus this project's imported ones."""
        catalog = dict(self._builtin)
        catalog.update({nid: pkg.definition for nid, pkg in self._imported.items()})
        warnings = self._graph.set_catalog(catalog)
        self.importedNodesChanged.emit()
        return warnings

    def _read_file(self, path: Path) -> tuple[dict, dict[str, NodePackage], list[str]]:
        """Read a project file. Raises OSError, or ValueError for bad content."""
        packages: dict[str, NodePackage] = {}
        warnings: list[str] = []

        if zipfile.is_zipfile(path):
            with zipfile.ZipFile(path) as archive:
                try:
                    data = json.loads(archive.read(PROJECT_ENTRY).decode("utf-8"))
                except KeyError:
                    raise ValueError(f"missing {PROJECT_ENTRY}") from None
                except (UnicodeDecodeError, json.JSONDecodeError) as e:
                    raise ValueError(f"{PROJECT_ENTRY} is not valid JSON: {e}") from None
                self._check_header(data)

                for nid in data.get("imported_nodes") or {}:
                    prefix = f"nodes/{nid}/"
                    try:
                        json_text = archive.read(prefix + "node.json").decode("utf-8")
                        files = {
                            name[len(prefix):]: archive.read(name)
                            for name in archive.namelist()
                            if name.startswith(prefix) and name != prefix + "node.json" and not name.endswith("/")
                        }
                        package = node_package_from_files(json_text, files, f"imported node '{nid}'")
                    except (KeyError, UnicodeDecodeError, CatalogError) as e:
                        warnings.append(f"Skipped imported node '{nid}': {e}")
                        continue
                    if package.definition.type_id != nid or nid in self._builtin:
                        warnings.append(f"Skipped imported node '{nid}': its id doesn't match or clashes.")
                        continue
                    packages[nid] = package
        else:
            # Version 1: plain JSON.
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as e:
                raise ValueError(f"not valid JSON: {e}") from None
            self._check_header(data)

        return data, packages, warnings

    @staticmethod
    def _check_header(data: Any):
        if not isinstance(data, dict) or data.get("format") != FILE_FORMAT:
            raise ValueError("not a VL project file.")
        if data.get("version", 0) > FILE_VERSION:
            raise ValueError(f"saved by a newer version of VL (file version {data['version']}).")

    def _write(self, path: Path) -> bool:
        # Write to a temporary file first, so a failed save never leaves a
        # half-written project behind.
        tmp = path.with_name(path.name + ".tmp")
        try:
            with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr(PROJECT_ENTRY, json.dumps(self._project_dict(), indent=4) + "\n")
                for nid, pkg in self._imported.items():
                    archive.writestr(f"nodes/{nid}/node.json", pkg.json_text)
                    for rel, content in pkg.files.items():
                        archive.writestr(f"nodes/{nid}/{rel}", content)
            os.replace(tmp, path)
        except OSError as e:
            tmp.unlink(missing_ok=True)
            self.messageRaised.emit("Could not save project", f"{path}\n\n{e.strerror}")
            return False
        self._mark_saved()
        return True

    def _set_compile_settings(self, settings: dict[str, Any]):
        self._compile_settings = settings
        self.compileSettingsChanged.emit()
        self._update_dirty()

    def _set_palette(self, palette: dict[str, dict[str, str]]):
        self._palette = palette
        self.paletteChanged.emit()
        self._update_dirty()

    def _set_path(self, path: Path | None):
        if path != self._path:
            self._path = path
            self.stateChanged.emit()

    def _load_recent(self) -> list[str]:
        try:
            recent = json.loads(self._settings.value("recentProjects", "[]"))
        except (TypeError, ValueError):
            return []
        return [p for p in recent if isinstance(p, str)][:MAX_RECENT]

    def _add_recent(self, path: Path):
        # Newest first; the oldest drops off once there are more than MAX_RECENT.
        entry = str(path.resolve())
        self._recent = ([entry] + [p for p in self._recent if p != entry])[:MAX_RECENT]
        self._settings.setValue("recentProjects", json.dumps(self._recent))
        self.recentChanged.emit()
