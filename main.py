import json
import sys
from pathlib import Path

from PySide6.QtCore import QLoggingCategory, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from graph_model import GraphModel
from node_catalog import CatalogError, load_node_definitions
from project import Project

APP_DIR = Path(__file__).parent


def main() -> int:
    # Qt's Wayland text-input plugin logs a harmless warning every time a text
    # field loses focus. Silence just that category so real output stays readable.
    # (QT_LOGGING_RULES in the environment still overrides this.)
    QLoggingCategory.setFilterRules("qt.qpa.wayland.textinput=false")

    app = QGuiApplication(sys.argv)
    app.setApplicationName("VL")
    app.setOrganizationName("VL")

    try:
        builtin_nodes = load_node_definitions(APP_DIR / "nodes")
    except CatalogError as e:
        print(f"Failed to load node definitions: {e}", file=sys.stderr)
        return 1

    try:
        default_palette = json.loads((APP_DIR / "palette.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        print(f"Failed to load palette.json: {e}", file=sys.stderr)
        return 1

    graph_model = GraphModel(builtin_nodes)
    project = Project(graph_model, builtin_nodes, default_palette)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("graphModel", graph_model)
    engine.rootContext().setContextProperty("project", project)
    engine.load(QUrl.fromLocalFile(str((APP_DIR / "ui" / "Main.qml").resolve())))

    if not engine.rootObjects():
        return 1

    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
