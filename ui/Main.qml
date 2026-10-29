import QtQuick
import "components"
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
	id: window
	width: 1440
	height: 900
	minimumWidth: 1000
	minimumHeight: 650
	visible: true
	title: "VL — Visual Programming"

	color: theme.background

	// Design tokens: keep colours here rather than scattered through the UI.
	QtObject {
		id: theme
		readonly property color background: "#17191d"
		readonly property color panel: "#202329"
		readonly property color panelRaised: "#282c33"
		readonly property color border: "#383d46"
		readonly property color text: "#e3e7ed"
		readonly property color muted: "#929ba8"
		readonly property color accent: "#72a7ff"
		readonly property color grid: "#292e36"
	}

	Rectangle {
		anchors.fill: parent
		color: theme.background
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		// Main application toolbar
		Rectangle {
			Layout.fillWidth: true
			Layout.preferredHeight: 48
			color: "#1d2025"
			border.color: theme.border
			border.width: 1

			RowLayout {
				anchors.fill: parent
				anchors.leftMargin: 16
				anchors.rightMargin: 14
				spacing: 14

				Rectangle {
					Layout.preferredWidth: 28
					Layout.preferredHeight: 28
					radius: 6
					color: theme.accent

					Text {
						anchors.centerIn: parent
						text: "V"
						color: "#101722"
						font.pixelSize: 17
						font.weight: Font.Black
					}
				}

				Text {
					text: "VL"
					color: theme.text
					font.pixelSize: 15
					font.weight: Font.DemiBold
				}

				Rectangle {
					Layout.preferredWidth: 1
					Layout.preferredHeight: 22
					color: theme.border
				}

				Text {
					text: "UNTITLED PROJECT"
					color: theme.muted
					font.pixelSize: 11
					font.letterSpacing: 1.1
				}

				Item { Layout.fillWidth: true }

				ToolButton {
					text: "Undo"
					enabled: false
					display: AbstractButton.TextOnly
				}
				ToolButton {
					text: "Redo"
					enabled: false
					display: AbstractButton.TextOnly
				}

				Rectangle {
					Layout.preferredWidth: 1
					Layout.preferredHeight: 22
					color: theme.border
				}

				Button {
					text: "Compile"
					enabled: false
				}
			}
		}

		// Main work area: graph canvas + inspector
		RowLayout {
			Layout.fillWidth: true
			Layout.fillHeight: true
			spacing: 0

			// Canvas
			Rectangle {
				Layout.fillWidth: true
				Layout.fillHeight: true
				color: "#171a1f"
				clip: true

				NodeCanvas {
					id: nodeCanvasArea
					anchors.fill: parent
				}

				// Status pill (bottom-left of the canvas)
				Rectangle {
					anchors.left: parent.left
					anchors.bottom: parent.bottom
					anchors.margins: 12
					width: statusText.implicitWidth + 24
					height: 28
					radius: 4
					color: "#20252c"
					border.color: theme.border

					Text {
						id: statusText
						anchors.centerIn: parent
						text: "ZOOM " + Math.round(nodeCanvasArea.zoomFactor * 100) + "%"
							+ "  ∙  " + nodeCanvasArea.nodeCount + " NODES"
							+ "  ∙  " + graphModel.connectionCount + " WIRES"
							+ (nodeCanvasArea.selectedNodeIds.length > 0
								? "  ∙  " + nodeCanvasArea.selectedNodeIds.length + " SELECTED" : "")
						color: theme.muted
						font.pixelSize: 10
						font.family: "monospace"
					}
				}
			}

			// Inspector
			Rectangle {
				Layout.preferredWidth: 260
				Layout.fillHeight: true
				color: theme.panel
				border.color: theme.border
				border.width: 1

				ColumnLayout {
					anchors.fill: parent
					anchors.margins: 14
					spacing: 12

					Text {
						text: "INSPECTOR"
						color: theme.muted
						font.pixelSize: 10
						font.weight: Font.Bold
						font.letterSpacing: 1.4
					}

					Rectangle {
						Layout.fillWidth: true
						Layout.preferredHeight: 1
						color: theme.border
					}

					Text {
						text: "Nothing selected"
						color: theme.text
						font.pixelSize: 13
						font.weight: Font.DemiBold
					}

					Text {
						text: "Select a node to inspect its properties and parameters."
						color: theme.muted
						wrapMode: Text.WordWrap
						Layout.fillWidth: true
						font.pixelSize: 12
					}

					Item { Layout.fillHeight: true }

					Text {
						text: "VL  •  DEVELOPMENT BUILD"
						color: "#687280"
						font.pixelSize: 9
						font.letterSpacing: 0.8
					}
				}
			}
		}
	}
}
