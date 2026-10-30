pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Settings tab: the project's group colours, socket type colours and
// imported nodes. Dialogs (file pickers, confirmations, colour picker) live
// in Main.qml; this page only asks for them through signals.
Rectangle {
	id: root

	signal colorEditRequested(string section, string name, string color)
	signal importRequested()
	signal reimportRequested(string nodeId)
	signal removeRequested(string nodeId, string title, int useCount)

	color: "#17191d"

	component SectionTitle: Text {
		color: "#929ba8"
		font.pixelSize: 10
		font.weight: Font.Bold
		font.letterSpacing: 1.4
	}

	component Hint: Text {
		color: "#687280"
		font.pixelSize: 11
		wrapMode: Text.WordWrap
	}

	// A list of name + colour swatch rows; clicking a row edits its colour.
	component ColorList: Flow {
		id: list
		property string section: ""
		property var colors: ({})

		spacing: 8

		Repeater {
			model: Object.keys(list.colors).sort(function(a, b) {
				return a.toLowerCase() < b.toLowerCase() ? -1 : 1
			})

			delegate: Rectangle {
				id: entry
				required property string modelData
				readonly property string colorValue: list.colors[modelData]

				width: 200
				height: 34
				radius: 5
				color: entryMouse.containsMouse ? "#262b33" : "#20242b"
				border.color: "#383d46"

				Rectangle {
					id: swatch
					x: 10
					anchors.verticalCenter: parent.verticalCenter
					width: 18
					height: 18
					radius: 4
					color: entry.colorValue
				}

				Text {
					anchors.left: swatch.right
					anchors.leftMargin: 10
					anchors.right: hexText.left
					anchors.rightMargin: 6
					anchors.verticalCenter: parent.verticalCenter
					text: entry.modelData
					color: "#e3e7ed"
					font.pixelSize: 12
					elide: Text.ElideRight
				}

				Text {
					id: hexText
					anchors.right: parent.right
					anchors.rightMargin: 10
					anchors.verticalCenter: parent.verticalCenter
					text: entry.colorValue
					color: "#687280"
					font.pixelSize: 10
					font.family: "monospace"
				}

				MouseArea {
					id: entryMouse
					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onClicked: root.colorEditRequested(list.section, entry.modelData, entry.colorValue)
				}
			}
		}
	}

	ScrollView {
		anchors.fill: parent
		contentWidth: availableWidth
		clip: true

		ColumnLayout {
			width: Math.min(parent.width - 64, 900)
			x: 32
			spacing: 14

			Item { Layout.preferredHeight: 18 }

			Text {
				text: "Project Settings"
				color: "#e3e7ed"
				font.pixelSize: 18
				font.weight: Font.DemiBold
			}
			Hint {
				Layout.fillWidth: true
				text: "Saved with the project. Click a colour to change it."
			}

			// -- Groups
			Item { Layout.preferredHeight: 6 }
			SectionTitle { text: "GROUPS" }
			Hint {
				Layout.fillWidth: true
				text: "Every node belongs to a group (its \"group\" in the node JSON). Nodes take their header colour from their group."
			}
			ColorList {
				Layout.fillWidth: true
				section: "groups"
				colors: project.groupColors
			}

			// -- Socket types
			Item { Layout.preferredHeight: 6 }
			SectionTitle { text: "SOCKET TYPES" }
			Hint {
				Layout.fillWidth: true
				text: "Colours of sockets and wires for each data type."
			}
			ColorList {
				Layout.fillWidth: true
				section: "types"
				colors: project.typeColors
			}

			// -- Imported nodes
			Item { Layout.preferredHeight: 6 }
			RowLayout {
				Layout.fillWidth: true
				SectionTitle { text: "IMPORTED NODES" }
				Item { Layout.fillWidth: true }
				VButton {
					text: "Import Node…"
					kind: "primary"
					onClicked: root.importRequested()
				}
			}
			Hint {
				Layout.fillWidth: true
				text: "Nodes imported from a JSON file and the code files it lists. They are stored inside the project file."
			}

			Hint {
				visible: project.importedNodes.length === 0
				text: "No imported nodes."
				color: "#929ba8"
			}

			Repeater {
				model: project.importedNodes

				delegate: Rectangle {
					id: nodeEntry
					required property var modelData

					Layout.fillWidth: true
					implicitHeight: nodeInfo.implicitHeight + 20
					radius: 5
					color: "#20242b"
					border.color: "#383d46"

					ColumnLayout {
						id: nodeInfo
						anchors.left: parent.left
						anchors.right: buttons.left
						anchors.leftMargin: 14
						anchors.rightMargin: 14
						anchors.verticalCenter: parent.verticalCenter
						spacing: 3

						RowLayout {
							spacing: 8
							Rectangle {
								width: 10
								height: 10
								radius: 2
								color: project.groupColors[nodeEntry.modelData.group] || "#72a7ff"
							}
							Text {
								text: nodeEntry.modelData.title
								color: "#e3e7ed"
								font.pixelSize: 13
								font.weight: Font.DemiBold
							}
							Text {
								text: nodeEntry.modelData.id + "  ·  " + nodeEntry.modelData.group
									+ "  ·  used " + nodeEntry.modelData.useCount + "×"
								color: "#929ba8"
								font.pixelSize: 11
							}
						}
						Text {
							Layout.fillWidth: true
							text: nodeEntry.modelData.files.join("   ")
							color: "#687280"
							font.pixelSize: 10
							font.family: "monospace"
							elide: Text.ElideRight
						}
						Text {
							Layout.fillWidth: true
							visible: nodeEntry.modelData.source !== ""
							text: "from " + nodeEntry.modelData.source
							color: "#687280"
							font.pixelSize: 10
							elide: Text.ElideMiddle
						}
					}

					Row {
						id: buttons
						anchors.right: parent.right
						anchors.rightMargin: 12
						anchors.verticalCenter: parent.verticalCenter
						spacing: 6

						VButton {
							text: "Re-import…"
							onClicked: root.reimportRequested(nodeEntry.modelData.id)
						}
						VButton {
							text: "Remove"
							kind: "danger"
							onClicked: root.removeRequested(nodeEntry.modelData.id, nodeEntry.modelData.title,
								nodeEntry.modelData.useCount)
						}
					}
				}
			}

			Item { Layout.preferredHeight: 32 }
		}
	}
}
