import sys
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from graph_model import GraphModel


def main() -> int:
    app = QGuiApplication(sys.argv)
    app.setApplicationName("VL")
    app.setOrganizationName("VL")

    engine = QQmlApplicationEngine()

    graph_model = GraphModel()

    # Demo graph so the canvas isn't empty on startup.
    lidar_id = graph_model.addNode("read_lidar", 80, 100)
    dist_id = graph_model.addNode("lidar_distance", 380, 100)
    graph_model.addNode("set_motor_speed", 680, 160)
    graph_model.addNode("constant_int", 380, 260)

    graph_model.addConnection(lidar_id, "scan", dist_id, "scan")

    engine.rootContext().setContextProperty("graphModel", graph_model)

    qml_file = Path(__file__).parent / "ui" / "Main.qml"
    engine.load(QUrl.fromLocalFile(str(qml_file.resolve())))

    if not engine.rootObjects():
        return 1

    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
