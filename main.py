import sys
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from graph_model import GraphModel
from node_catalog import CatalogError, load_node_definitions
from project import Project

APP_DIR = Path(__file__).parent


def main() -> int:
    app = QGuiApplication(sys.argv)
    app.setApplicationName("VL")
    app.setOrganizationName("VL")

    try:
        catalog = load_node_definitions(APP_DIR / "nodes")
    except CatalogError as e:
        print(f"Failed to load node definitions: {e}", file=sys.stderr)
        return 1

    graph_model = GraphModel(catalog)
    project = Project(graph_model)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("graphModel", graph_model)
    engine.rootContext().setContextProperty("project", project)
    engine.load(QUrl.fromLocalFile(str((APP_DIR / "ui" / "Main.qml").resolve())))

    if not engine.rootObjects():
        return 1

    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
