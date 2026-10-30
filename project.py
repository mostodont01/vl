"""Project files: new / open / save, unsaved-changes tracking and recent projects.

A project file (*.vl) is JSON:

    {
        "format": "vl-project",
        "version": 1,
        "nodes": [{"id", "type", "x", "y", "values"}, ...],
        "connections": [{"source_node", "source_socket", "target_node", "target_socket"}, ...]
    }
"""

import json
import os
from pathlib import Path
from typing import Any

from PySide6.QtCore import QObject, QSettings, QUrl, Property, Signal, Slot

from graph_model import GraphModel

FILE_FORMAT = "vl-project"
FILE_VERSION = 1
FILE_SUFFIX = ".vl"
MAX_RECENT = 10


def _to_path(location: str) -> Path:
    """Accept both plain paths and file:// URLs (what QML file dialogs return)."""
    if location.startswith("file:"):
        location = QUrl(location).toLocalFile()
    return Path(location)


class Project(QObject):
    stateChanged = Signal()     # file path or dirty flag changed
    recentChanged = Signal()
    # Something the user should be told about: (title, text).
    messageRaised = Signal(str, str)

    def __init__(self, graph: GraphModel):
        super().__init__()
        self._graph = graph
        self._path: Path | None = None
        self._settings = QSettings("VL", "VL")
        self._recent: list[str] = self._load_recent()
        self._dirty = False
        self._saved_key = self._state_key()
        graph.graphChanged.connect(self._update_dirty)

    # -- Unsaved-changes tracking -------------------------------------------

    def _state_key(self) -> str:
        return json.dumps(self._graph.to_dict(), sort_keys=True)

    def _mark_saved(self):
        self._saved_key = self._state_key()
        self._update_dirty()

    def _update_dirty(self):
        # Compare content rather than counting edits, so undoing back to the
        # saved state counts as "no unsaved changes".
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

    @Property("QVariantList", notify=recentChanged)
    def recentProjects(self) -> list[dict[str, Any]]:
        return [
            {"path": p, "name": Path(p).stem, "folder": str(Path(p).parent), "exists": Path(p).is_file()}
            for p in self._recent
        ]

    # -- Actions ------------------------------------------------------------

    @Slot()
    def newProject(self):
        self._graph.clear()
        self._set_path(None)
        self._mark_saved()

    @Slot(str, result=bool)
    def openProject(self, location: str) -> bool:
        path = _to_path(location)
        # Only .vl for now (a compressed container format may replace it later).
        if path.suffix != FILE_SUFFIX:
            self.messageRaised.emit("Could not open project", f"{path.name} is not a {FILE_SUFFIX} file.")
            return False
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except OSError as e:
            self.messageRaised.emit("Could not open project", f"{path}\n\n{e.strerror}")
            return False
        except json.JSONDecodeError as e:
            self.messageRaised.emit("Could not open project", f"{path.name} is not valid JSON:\n{e}")
            return False

        if not isinstance(data, dict) or data.get("format") != FILE_FORMAT:
            self.messageRaised.emit("Could not open project", f"{path.name} is not a VL project file.")
            return False
        if data.get("version", 0) > FILE_VERSION:
            self.messageRaised.emit(
                "Could not open project",
                f"{path.name} was saved by a newer version of VL (file version {data['version']}).",
            )
            return False

        warnings = self._graph.load_dict(data)
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

    @Slot(str)
    def removeRecent(self, location: str):
        if location in self._recent:
            self._recent.remove(location)
            self._store_recent()

    # -- Internals ----------------------------------------------------------

    def _write(self, path: Path) -> bool:
        data = {"format": FILE_FORMAT, "version": FILE_VERSION, **self._graph.to_dict()}
        # Write to a temporary file first, so a failed save never leaves a
        # half-written project behind.
        tmp = path.with_name(path.name + ".tmp")
        try:
            tmp.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
            os.replace(tmp, path)
        except OSError as e:
            tmp.unlink(missing_ok=True)
            self.messageRaised.emit("Could not save project", f"{path}\n\n{e.strerror}")
            return False
        self._mark_saved()
        return True

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

    def _store_recent(self):
        self._settings.setValue("recentProjects", json.dumps(self._recent))
        self.recentChanged.emit()

    def _add_recent(self, path: Path):
        entry = str(path.resolve())
        self._recent = [entry] + [p for p in self._recent if p != entry][: MAX_RECENT - 1]
        self._store_recent()
