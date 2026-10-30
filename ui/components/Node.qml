pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// Visual representation of one node. Rows, top to bottom (like Blender):
// outputs (right edge), settings (no socket), inputs (left edge).
//
// The node changes nothing itself: presses, drags, wire drags and value edits
// are reported to NodeCanvas, which talks to the model.
Rectangle {
	id: root

	// -- Data (set by NodeCanvas) -----------------------------------------
	property string nodeId: ""
	property string title: "Node"
	property var nodeInputs: []
	property var nodeOutputs: []
	property var nodeSettings: []
	property var nodeValues: ({})
	property var connectedInputIds: []
	property bool hasAppWidget: false     // Shows the eye toggle in the header.
	property bool widgetVisible: true
	property bool selected: false
	property color accentColor: "#65a9ff"   // The node's group colour.
	property var typeColors: ({})           // Socket type -> colour (project palette).
	// Set briefly when an issue for this node is clicked.
	property bool highlighted: false
	property color highlightColor: "#f87171"

	// -- Layout constants -------------------------------------------------
	// Socket positions are computed from these, both for layout and for
	// getSocketCenter(), so wires always end exactly on the socket dots.
	readonly property int headerHeight: 34
	readonly property int rowsTopPadding: 8
	readonly property int rowPitch: 26          // Height of one row.
	readonly property int rowsBottomPadding: 10
	readonly property int socketDotSize: 12
	readonly property int socketHitWidth: 28    // Clickable area is larger than the dot.

	// Body presses select and move the node (handled by the canvas).
	signal bodyPressed(string nodeId, bool ctrl, var mouseArea, var mouse)
	signal bodyMoved(var mouseArea, var mouse)
	signal bodyReleased()
	signal wireDragStarted(string nodeId, string socketId, bool isOutput, var mouseArea, var mouse)
	signal wireDragMoved(var mouseArea, var mouse)
	signal wireDragEnded(var mouseArea, var mouse)
	signal disconnectSocketRequested(string nodeId, string socketId)
	signal valueEdited(string nodeId, string key, var value)
	signal widgetVisibilityToggled(string nodeId)
	signal editingDone()

	// Settings currently shown: app-widget-only ones hide while the eye is closed.
	readonly property var shownSettings: nodeSettings.filter(function(s) {
		return !s.appWidgetOnly || widgetVisible
	})

	implicitWidth: 230
	implicitHeight: headerHeight + rowsTopPadding
		+ (nodeOutputs.length + shownSettings.length + nodeInputs.length) * rowPitch
		+ rowsBottomPadding
	width: implicitWidth
	height: implicitHeight

	radius: 8
	color: "#292c32"
	border.color: highlighted ? highlightColor : selected ? root.accentColor : "#454a54"
	border.width: highlighted ? 2 : 1

	function typeColor(typeName) {
		return typeColors[typeName] || "#94a3b8"
	}

	// Glow around the node while highlighted.
	Rectangle {
		visible: root.highlighted
		anchors.fill: parent
		anchors.margins: -5
		radius: root.radius + 5
		color: "transparent"
		border.color: root.highlightColor
		border.width: 2
		opacity: 0.45
	}

	// Center of a socket dot in this node's local coordinates, or null.
	function getSocketCenter(socketId, isOutput) {
		var sockets = isOutput ? root.nodeOutputs : root.nodeInputs
		var firstRow = isOutput ? 0 : root.nodeOutputs.length + root.shownSettings.length
		for (var i = 0; i < sockets.length; i++) {
			if (sockets[i].id === socketId) {
				return {
					x: isOutput ? root.width : 0,
					y: headerHeight + rowsTopPadding + (firstRow + i) * rowPitch + rowPitch / 2
				}
			}
		}
		return null
	}

	function valueOf(key) {
		return root.nodeValues ? root.nodeValues[key] : undefined
	}

	// Catches presses on the node that no socket or widget took. Declared
	// first so everything else sits on top of it.
	MouseArea {
		id: bodyMouse
		anchors.fill: parent
		acceptedButtons: Qt.LeftButton
		cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor

		onPressed: function(mouse) {
			root.bodyPressed(root.nodeId, mouse.modifiers & Qt.ControlModifier, bodyMouse, mouse)
		}
		onPositionChanged: function(mouse) { root.bodyMoved(bodyMouse, mouse) }
		onReleased: root.bodyReleased()
	}

	// One row: an optional socket dot, a label, and either the type name or
	// a value widget. Used for outputs, settings and inputs.
	component NodeRow: Item {
		id: row

		required property var modelData
		property string kind: "input"   // "input", "output" or "setting"
		property bool connected: false
		property var value
		property int dotSize: 12
		property int hitWidth: 28

		signal socketPressed(var mouseArea, var mouse)
		signal socketMoved(var mouseArea, var mouse)
		signal socketReleased(var mouseArea, var mouse)
		signal socketRightClicked()
		signal valueEdited(var value)
		signal editingDone()

		readonly property bool isOutput: kind === "output"
		readonly property bool hasSocket: kind !== "setting"
		readonly property bool showsWidget: modelData.widget !== null && modelData.widget !== undefined
			&& (kind === "setting" || (kind === "input" && !connected))
		property color typeColor: "#94a3b8"
		readonly property real dotCenterX: isOutput ? width : 0
		readonly property real labelWidth: showsWidget ? Math.round((width - 24) * 0.42) : width - 24

		Rectangle {
			id: dot
			visible: row.hasSocket
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

		// Label (+ type name when there's no widget)
		Row {
			anchors.verticalCenter: parent.verticalCenter
			anchors.left: row.isOutput ? undefined : parent.left
			anchors.right: row.isOutput ? parent.right : undefined
			anchors.leftMargin: 12
			anchors.rightMargin: 12
			width: row.labelWidth
			layoutDirection: row.isOutput ? Qt.RightToLeft : Qt.LeftToRight
			spacing: 5
			clip: true

			Text {
				text: row.modelData.name
				color: row.kind === "setting" ? "#b9c0cb" : "#e2e7ef"
				font.pixelSize: 11
				font.weight: Font.Medium
			}

			Text {
				visible: !row.showsWidget
				text: row.modelData.type
				color: row.typeColor
				font.pixelSize: 9
				opacity: 0.85
				font.family: "monospace"
			}
		}

		ValueWidget {
			visible: row.showsWidget
			enabled: visible
			anchors.right: parent.right
			anchors.rightMargin: 10
			anchors.verticalCenter: parent.verticalCenter
			width: parent.width - 12 - row.labelWidth - 6 - 10
			height: 20
			widget: row.modelData.widget || ({})
			value: row.value
			accentColor: row.typeColor

			onEdited: (value) => row.valueEdited(value)
			onEditingDone: row.editingDone()
		}

		// Clickable area around the dot: the full row height and wider than
		// the dot, so sockets are easy to grab.
		MouseArea {
			id: hitArea
			visible: row.hasSocket
			x: row.dotCenterX - width / 2
			width: row.hitWidth
			height: row.height
			hoverEnabled: true
			cursorShape: Qt.PointingHandCursor
			// Outputs leave the right button alone so right-drag still pans.
			acceptedButtons: row.isOutput ? Qt.LeftButton : (Qt.LeftButton | Qt.RightButton)

			onPressed: function(mouse) {
				if (mouse.button === Qt.LeftButton)
					row.socketPressed(hitArea, mouse)
			}
			onPositionChanged: function(mouse) {
				if (mouse.buttons & Qt.LeftButton)
					row.socketMoved(hitArea, mouse)
			}
			onReleased: function(mouse) {
				if (mouse.button === Qt.LeftButton)
					row.socketReleased(hitArea, mouse)
			}
			onClicked: function(mouse) {
				if (mouse.button === Qt.RightButton)
					row.socketRightClicked()
			}
		}
	}

	// -- Header -----------------------------------------------------------
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
			anchors.right: root.hasAppWidget ? eyeButton.left : parent.right
			anchors.leftMargin: 12
			anchors.rightMargin: 8
			anchors.verticalCenter: parent.verticalCenter
			text: root.title
			color: "#e8ebf0"
			font.pixelSize: 13
			font.bold: true
			elide: Text.ElideRight
		}

		// Eye: whether this node's widget is shown in the compiled app.
		Item {
			id: eyeButton
			visible: root.hasAppWidget
			anchors.right: parent.right
			anchors.rightMargin: 6
			anchors.verticalCenter: parent.verticalCenter
			width: 26
			height: 22

			Rectangle {
				anchors.fill: parent
				radius: 4
				color: eyeMouse.containsMouse ? "#40465180" : "transparent"
			}

			Canvas {
				id: eyeIcon
				anchors.centerIn: parent
				width: 18
				height: 12

				property bool open: root.widgetVisible
				onOpenChanged: requestPaint()

				onPaint: {
					var ctx = getContext("2d")
					ctx.clearRect(0, 0, width, height)
					ctx.lineWidth = 1.5
					ctx.lineCap = "round"

					if (open) {
						ctx.strokeStyle = "#e8ebf0"
						ctx.fillStyle = "#e8ebf0"
						// Almond outline
						ctx.beginPath()
						ctx.moveTo(1, 6)
						ctx.quadraticCurveTo(9, -2, 17, 6)
						ctx.quadraticCurveTo(9, 14, 1, 6)
						ctx.stroke()
						// Pupil
						ctx.beginPath()
						ctx.arc(9, 6, 2.5, 0, 2 * Math.PI)
						ctx.fill()
					} else {
						ctx.strokeStyle = "#7f8996"
						// Closed lid with lashes
						ctx.beginPath()
						ctx.moveTo(1, 4)
						ctx.quadraticCurveTo(9, 11, 17, 4)
						ctx.stroke()
						ctx.beginPath()
						ctx.moveTo(4.5, 7); ctx.lineTo(3, 10)
						ctx.moveTo(9, 8.5); ctx.lineTo(9, 11.5)
						ctx.moveTo(13.5, 7); ctx.lineTo(15, 10)
						ctx.stroke()
					}
				}
			}

			MouseArea {
				id: eyeMouse
				anchors.fill: parent
				hoverEnabled: true
				cursorShape: Qt.PointingHandCursor
				onClicked: root.widgetVisibilityToggled(root.nodeId)
			}

			ToolTip.visible: eyeMouse.containsMouse
			ToolTip.delay: 500
			ToolTip.text: root.widgetVisible ? "Shown in the compiled app" : "Hidden in the compiled app"
		}
	}

	// -- Rows -------------------------------------------------------------
	Column {
		id: rows
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: header.bottom
		anchors.topMargin: root.rowsTopPadding

		Repeater {
			model: root.nodeOutputs

			delegate: NodeRow {
				typeColor: root.typeColor(modelData.type)
				width: rows.width
				height: root.rowPitch
				dotSize: root.socketDotSize
				hitWidth: root.socketHitWidth
				kind: "output"

				onSocketPressed: (mouseArea, mouse) => root.wireDragStarted(root.nodeId, modelData.id, true, mouseArea, mouse)
				onSocketMoved: (mouseArea, mouse) => root.wireDragMoved(mouseArea, mouse)
				onSocketReleased: (mouseArea, mouse) => root.wireDragEnded(mouseArea, mouse)
			}
		}

		Repeater {
			model: root.shownSettings

			delegate: NodeRow {
				typeColor: root.typeColor(modelData.type)
				width: rows.width
				height: root.rowPitch
				kind: "setting"
				value: root.valueOf(modelData.id)

				onValueEdited: (value) => root.valueEdited(root.nodeId, modelData.id, value)
				onEditingDone: root.editingDone()
			}
		}

		Repeater {
			model: root.nodeInputs

			delegate: NodeRow {
				typeColor: root.typeColor(modelData.type)
				width: rows.width
				height: root.rowPitch
				dotSize: root.socketDotSize
				hitWidth: root.socketHitWidth
				kind: "input"
				connected: root.connectedInputIds.indexOf(modelData.id) !== -1
				value: root.valueOf(modelData.id)

				onSocketPressed: (mouseArea, mouse) => root.wireDragStarted(root.nodeId, modelData.id, false, mouseArea, mouse)
				onSocketMoved: (mouseArea, mouse) => root.wireDragMoved(mouseArea, mouse)
				onSocketReleased: (mouseArea, mouse) => root.wireDragEnded(mouseArea, mouse)
				onSocketRightClicked: root.disconnectSocketRequested(root.nodeId, modelData.id)
				onValueEdited: (value) => root.valueEdited(root.nodeId, modelData.id, value)
				onEditingDone: root.editingDone()
			}
		}
	}
}
