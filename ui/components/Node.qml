pragma ComponentBehavior: Bound
import QtQuick
import "SocketTypes.js" as SocketTypes

// Visual representation of one node: a header (drag handle) plus input
// sockets on the left and output sockets on the right. The node does not
// create wires itself; it reports socket presses to NodeCanvas.
Rectangle {
	id: root

	// -- Data (set by NodeCanvas) -----------------------------------------
	property string nodeId: ""
	property string nodeType: ""
	property string title: "Node"
	property var nodeInputs: []
	property var nodeOutputs: []
	property var connectedInputIds: []
	property bool selected: false
	property color accentColor: "#65a9ff"

	// -- Layout constants -------------------------------------------------
	// Socket positions are computed from these, both for layout and for
	// getSocketCenter(), so wires always end exactly on the socket dots.
	readonly property int headerHeight: 34
	readonly property int socketsTopPadding: 8
	readonly property int socketPitch: 26      // Height of one socket row.
	readonly property int socketsBottomPadding: 16
	readonly property int socketDotSize: 12
	readonly property int socketHitWidth: 28   // Clickable area is larger than the dot.

	signal selectionRequested(string nodeId, bool additive)
	signal wireDragStarted(string nodeId, string socketId, bool isOutput, var mouseArea, var mouse)
	signal wireDragMoved(var mouseArea, var mouse)
	signal wireDragEnded(var mouseArea, var mouse)
	signal disconnectSocketRequested(string nodeId, string socketId)

	implicitWidth: 230
	implicitHeight: Math.max(90, headerHeight + socketsTopPadding
		+ Math.max(nodeInputs.length, nodeOutputs.length) * socketPitch
		+ socketsBottomPadding)
	width: implicitWidth
	height: implicitHeight

	radius: 8
	color: "#292c32"
	border.color: selected ? root.accentColor : "#454a54"
	border.width: 1

	// Center of a socket dot in this node's local coordinates, or null.
	function getSocketCenter(socketId, isOutput) {
		var sockets = isOutput ? root.nodeOutputs : root.nodeInputs
		for (var i = 0; i < sockets.length; i++) {
			if (sockets[i].id === socketId) {
				return {
					x: isOutput ? root.width : 0,
					y: headerHeight + socketsTopPadding + i * socketPitch + socketPitch / 2
				}
			}
		}
		return null
	}

	// One socket row. Used for both inputs and outputs; outputs are mirrored.
	component SocketRow: Item {
		id: row

		required property var modelData
		required property int index
		property bool isOutput: false
		property bool connected: false
		property int dotSize: 12
		property int hitWidth: 28

		signal pressed(var mouseArea, var mouse)
		signal moved(var mouseArea, var mouse)
		signal released(var mouseArea, var mouse)
		signal rightClicked()

		readonly property color typeColor: SocketTypes.color(modelData.type)
		readonly property real dotCenterX: isOutput ? width : 0

		Rectangle {
			id: dot
			x: row.dotCenterX - width / 2
			anchors.verticalCenter: parent.verticalCenter
			width: row.dotSize
			height: row.dotSize
			radius: width / 2
			scale: hitArea.containsMouse || hitArea.pressed ? 1.3 : 1.0
			// Outputs are always filled; inputs are hollow until connected.
			color: row.isOutput || row.connected ? row.typeColor : "#1d2025"
			border.color: row.isOutput
				? (hitArea.containsMouse ? "#ffffff" : "#17191d")
				: row.typeColor
			border.width: row.isOutput ? 1.5 : 2

			Behavior on scale { NumberAnimation { duration: 80 } }
		}

		Row {
			anchors.verticalCenter: parent.verticalCenter
			anchors.left: row.isOutput ? undefined : parent.left
			anchors.right: row.isOutput ? parent.right : undefined
			anchors.leftMargin: 12
			anchors.rightMargin: 12
			layoutDirection: row.isOutput ? Qt.RightToLeft : Qt.LeftToRight
			spacing: 5

			Text {
				text: row.modelData.name
				color: "#e2e7ef"
				font.pixelSize: 11
				font.weight: Font.Medium
			}

			Text {
				text: row.modelData.type
				color: row.typeColor
				font.pixelSize: 9
				opacity: 0.85
				font.family: "monospace"
			}
		}

		// Clickable area around the dot: the full row height and wider than
		// the dot, so sockets are easy to grab.
		MouseArea {
			id: hitArea
			x: row.dotCenterX - width / 2
			width: row.hitWidth
			height: row.height
			hoverEnabled: true
			cursorShape: Qt.PointingHandCursor
			// Outputs leave the right button alone so right-drag still pans.
			acceptedButtons: row.isOutput ? Qt.LeftButton : (Qt.LeftButton | Qt.RightButton)

			onPressed: function(mouse) {
				if (mouse.button === Qt.LeftButton)
					row.pressed(hitArea, mouse)
			}
			onPositionChanged: function(mouse) {
				if (mouse.buttons & Qt.LeftButton)
					row.moved(hitArea, mouse)
			}
			onReleased: function(mouse) {
				if (mouse.button === Qt.LeftButton)
					row.released(hitArea, mouse)
			}
			onClicked: function(mouse) {
				if (mouse.button === Qt.RightButton)
					row.rightClicked()
			}
		}
	}

	// -- Header (title + drag handle) -------------------------------------
	Rectangle {
		id: header

		width: parent.width
		height: root.headerHeight
		radius: 8
		color: "#343943"

		// Squares off the header's bottom corners.
		Rectangle {
			width: parent.width
			height: 8
			anchors.bottom: parent.bottom
			color: header.color
		}

		// Accent stripe.
		Rectangle {
			width: 3
			height: parent.height
			color: root.accentColor
			radius: 2
		}

		Text {
			anchors.left: parent.left
			anchors.leftMargin: 12
			anchors.verticalCenter: parent.verticalCenter
			text: root.title
			color: "#e8ebf0"
			font.pixelSize: 13
			font.bold: true
		}

		// Dragging moves the canvas delegate (root.parent) directly for smooth
		// feedback; the final position is written to the model on release.
		MouseArea {
			anchors.fill: parent
			acceptedButtons: Qt.LeftButton
			cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
			drag.target: root.parent
			drag.axis: Drag.XAndYAxis

			onClicked: function(mouse) {
				root.selectionRequested(root.nodeId, mouse.modifiers & Qt.ControlModifier)
			}

			onReleased: {
				graphModel.setNodePosition(root.nodeId, root.parent.x, root.parent.y)
			}
		}
	}

	// -- Sockets ----------------------------------------------------------
	Column {
		id: inputsColumn
		anchors.left: parent.left
		anchors.top: header.bottom
		anchors.topMargin: root.socketsTopPadding
		width: parent.width / 2 - 4

		Repeater {
			model: root.nodeInputs

			delegate: SocketRow {
				width: inputsColumn.width
				height: root.socketPitch
				dotSize: root.socketDotSize
				hitWidth: root.socketHitWidth
				isOutput: false
				connected: root.connectedInputIds.indexOf(modelData.id) !== -1

				onPressed: (mouseArea, mouse) => root.wireDragStarted(root.nodeId, modelData.id, false, mouseArea, mouse)
				onMoved: (mouseArea, mouse) => root.wireDragMoved(mouseArea, mouse)
				onReleased: (mouseArea, mouse) => root.wireDragEnded(mouseArea, mouse)
				onRightClicked: root.disconnectSocketRequested(root.nodeId, modelData.id)
			}
		}
	}

	Column {
		id: outputsColumn
		anchors.right: parent.right
		anchors.top: header.bottom
		anchors.topMargin: root.socketsTopPadding
		width: parent.width / 2 - 4

		Repeater {
			model: root.nodeOutputs

			delegate: SocketRow {
				width: outputsColumn.width
				height: root.socketPitch
				dotSize: root.socketDotSize
				hitWidth: root.socketHitWidth
				isOutput: true

				onPressed: (mouseArea, mouse) => root.wireDragStarted(root.nodeId, modelData.id, true, mouseArea, mouse)
				onMoved: (mouseArea, mouse) => root.wireDragMoved(mouseArea, mouse)
				onReleased: (mouseArea, mouse) => root.wireDragEnded(mouseArea, mouse)
			}
		}
	}
}
