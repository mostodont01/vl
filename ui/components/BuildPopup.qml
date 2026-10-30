import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Shows the compile/build log while it runs and its result afterwards.
// Closing it doesn't stop the build.
Popup {
	id: root

	parent: Overlay.overlay
	anchors.centerIn: parent
	width: Math.min(parent.width - 80, 860)
	height: Math.min(parent.height - 80, 540)
	modal: true
	dim: true
	padding: 18
	closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

	readonly property var statusInfo: ({
		"idle": { text: "Compile", color: "#929ba8" },
		"running": { text: "Compiling…", color: "#72a7ff" },
		"succeeded": { text: "Build succeeded", color: "#4ade80" },
		"failed": { text: "Compile failed", color: "#f87171" },
		"generated": { text: "Project generated, not built", color: "#fbbf24" }
	})[builder.status]

	background: Rectangle {
		color: "#202329"
		radius: 8
		border.color: "#383d46"
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 12

		RowLayout {
			spacing: 10

			Rectangle {
				width: 10
				height: 10
				radius: 5
				color: root.statusInfo.color

				SequentialAnimation on opacity {
					running: builder.running
					loops: Animation.Infinite
					alwaysRunToEnd: true
					NumberAnimation { to: 0.3; duration: 500 }
					NumberAnimation { to: 1.0; duration: 500 }
				}
			}

			Text {
				text: root.statusInfo.text
				color: "#e3e7ed"
				font.pixelSize: 15
				font.weight: Font.DemiBold
			}
		}

		Rectangle {
			Layout.fillWidth: true
			Layout.fillHeight: true
			radius: 5
			color: "#15171b"
			border.color: "#2e333b"

			ScrollView {
				id: logScroll
				anchors.fill: parent
				anchors.margins: 1
				clip: true

				TextArea {
					id: logText
					readOnly: true
					selectByMouse: true
					wrapMode: TextEdit.Wrap
					text: builder.log
					color: "#c9cfd8"
					selectionColor: "#3b6fd4"
					font.family: "monospace"
					font.pixelSize: 11
					padding: 10
					background: null

					// Follow the end of the log as it grows.
					onTextChanged: cursorPosition = length
				}
			}
		}

		RowLayout {
			Layout.fillWidth: true
			spacing: 8

			Text {
				Layout.fillWidth: true
				visible: builder.status === "succeeded"
				text: builder.executable
				color: "#929ba8"
				font.pixelSize: 11
				font.family: "monospace"
				elide: Text.ElideMiddle
			}
			Item {
				Layout.fillWidth: true
				visible: builder.status !== "succeeded"
			}

			VButton {
				text: "Open Folder"
				visible: builder.outputFolderUrl !== "" && !builder.running
				onClicked: Qt.openUrlExternally(builder.outputFolderUrl)
			}
			VButton {
				text: "Cancel Build"
				kind: "danger"
				visible: builder.running
				onClicked: builder.cancel()
			}
			VButton {
				text: "Close"
				kind: "primary"
				onClicked: root.close()
			}
		}
	}
}
