pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "SocketTypes.js" as SocketTypes

// The node editor canvas: grid, wires, nodes, navigation, selection and the
// Shift+A add-node popup.
//
// Coordinates: nodes live in "world" coordinates (what the model stores).
// The visible "screen" position is  screen = pan + world * zoom.
Item {
	id: root

	// -- Navigation state -------------------------------------------------
	property real panX: 0
	property real panY: 0
	property real zoomFactor: 1.0

	// Last known mouse position in screen coordinates.
	property real mouseCanvasX: 0
	property real mouseCanvasY: 0

	// Add-node popup position in screen coordinates.
	property real popupX: 0
	property real popupY: 0

	property var selectedNodeIds: []

	readonly property int nodeCount: nodeRepeater.count

	// Cached copy of the model's connections; bindings that read it update
	// automatically when connections change.
	readonly property var connections: graphModel ? graphModel.connections : []

	// How close (in screen pixels) the cursor must be to a socket to snap.
	readonly property real snapRadiusPx: 28

	// -- Wire dragging state ----------------------------------------------
	// A drag always has one fixed end (the anchor socket) and one end that
	// follows the cursor. When fromOutput is true the anchor is an output and
	// we look for inputs to snap to; otherwise the reverse.
	QtObject {
		id: dragWire
		property bool active: false
		property bool fromOutput: true
		property string anchorNodeId: ""
		property string anchorSocketId: ""
		property string dataType: ""
		property real anchorWorldX: 0
		property real anchorWorldY: 0
		property real cursorWorldX: 0
		property real cursorWorldY: 0

		// Set when an existing wire was picked up from an input. That wire is
		// hidden while dragging and replaced (or deleted) on release.
		property string detachedConnectionId: ""
		property string detachedNodeId: ""
		property string detachedSocketId: ""

		// Socket currently snapped to, if any.
		property bool snapped: false
		property string snapNodeId: ""
		property string snapSocketId: ""
		property real snapWorldX: 0
		property real snapWorldY: 0
	}

	// -- Coordinate helpers -----------------------------------------------

	function toWorld(mouseArea, mouse) {
		var p = mouseArea.mapToItem(root, mouse.x, mouse.y)
		return { x: (p.x - root.panX) / root.zoomFactor, y: (p.y - root.panY) / root.zoomFactor }
	}

	function toScreenX(worldX) { return root.panX + worldX * root.zoomFactor }
	function toScreenY(worldY) { return root.panY + worldY * root.zoomFactor }

	function findNodeDelegate(nodeId) {
		for (var i = 0; i < nodeRepeater.count; i++) {
			var it = nodeRepeater.itemAt(i)
			if (it && it.nodeId === nodeId)
				return it
		}
		return null
	}

	function getSocketWorldPos(nodeId, socketId, isOutput) {
		var delegate = findNodeDelegate(nodeId)
		if (!delegate)
			return null
		var center = delegate.node.getSocketCenter(socketId, isOutput)
		if (!center)
			return null
		return { x: delegate.x + center.x, y: delegate.y + center.y }
	}

	function connectedInputIdsFor(nodeId) {
		var ids = []
		for (var i = 0; i < root.connections.length; i++) {
			if (root.connections[i].targetNode === nodeId)
				ids.push(root.connections[i].targetPort)
		}
		return ids
	}

	function findIncomingConnection(nodeId, socketId) {
		for (var i = 0; i < root.connections.length; i++) {
			var c = root.connections[i]
			if (c.targetNode === nodeId && c.targetPort === socketId)
				return c
		}
		return null
	}

	// -- Wire dragging ----------------------------------------------------

	// Pressing an output starts a new wire. Pressing an unconnected input
	// starts a wire backwards (towards an output). Pressing a connected input
	// picks up its existing wire, so it can be moved to another input or
	// dropped on empty canvas to delete it.
	function startWireDrag(nodeId, socketId, isOutput) {
		var anchorNode = nodeId
		var anchorSocket = socketId
		var fromOutput = isOutput
		var detached = null

		if (!isOutput) {
			detached = findIncomingConnection(nodeId, socketId)
			if (detached) {
				anchorNode = detached.sourceNode
				anchorSocket = detached.sourcePort
				fromOutput = true
			}
		}

		var anchorPos = getSocketWorldPos(anchorNode, anchorSocket, fromOutput)
		if (!anchorPos)
			return

		var delegate = findNodeDelegate(anchorNode)
		var sockets = fromOutput ? delegate.nodeOutputs : delegate.nodeInputs
		var type = ""
		for (var i = 0; i < sockets.length; i++) {
			if (sockets[i].id === anchorSocket)
				type = sockets[i].type
		}

		dragWire.fromOutput = fromOutput
		dragWire.anchorNodeId = anchorNode
		dragWire.anchorSocketId = anchorSocket
		dragWire.dataType = type
		dragWire.anchorWorldX = anchorPos.x
		dragWire.anchorWorldY = anchorPos.y
		dragWire.detachedConnectionId = detached ? detached.id : ""
		dragWire.detachedNodeId = detached ? nodeId : ""
		dragWire.detachedSocketId = detached ? socketId : ""

		// A picked-up wire starts snapped to the input it came from, so a
		// plain click on a connected input leaves the wire unchanged.
		if (detached) {
			var originPos = getSocketWorldPos(nodeId, socketId, false)
			setSnap(nodeId, socketId, originPos.x, originPos.y)
			dragWire.cursorWorldX = originPos.x
			dragWire.cursorWorldY = originPos.y
		} else {
			clearSnap()
			dragWire.cursorWorldX = anchorPos.x
			dragWire.cursorWorldY = anchorPos.y
		}

		dragWire.active = true
		forceActiveFocus() // So Escape can cancel the drag.
		dragWireCanvas.requestPaint()
		connectionsCanvas.requestPaint()
	}

	function updateWireDrag(mouseArea, mouse) {
		if (!dragWire.active)
			return

		var world = toWorld(mouseArea, mouse)
		dragWire.cursorWorldX = world.x
		dragWire.cursorWorldY = world.y

		var target = findSnapTarget(world.x, world.y)
		if (target)
			setSnap(target.nodeId, target.socketId, target.worldX, target.worldY)
		else
			clearSnap()

		dragWireCanvas.requestPaint()
	}

	function finishWireDrag() {
		if (!dragWire.active)
			return

		var snappedBackToOrigin = dragWire.detachedConnectionId !== ""
			&& dragWire.snapped
			&& dragWire.snapNodeId === dragWire.detachedNodeId
			&& dragWire.snapSocketId === dragWire.detachedSocketId

		if (!snappedBackToOrigin) {
			if (dragWire.detachedConnectionId !== "")
				graphModel.removeConnection(dragWire.detachedConnectionId)

			if (dragWire.snapped) {
				if (dragWire.fromOutput)
					graphModel.addConnection(dragWire.anchorNodeId, dragWire.anchorSocketId,
						dragWire.snapNodeId, dragWire.snapSocketId)
				else
					graphModel.addConnection(dragWire.snapNodeId, dragWire.snapSocketId,
						dragWire.anchorNodeId, dragWire.anchorSocketId)
			}
		}

		endWireDrag()
	}

	// Abort without changing the graph (Escape).
	function cancelWireDrag() {
		endWireDrag()
	}

	function endWireDrag() {
		dragWire.active = false
		dragWire.detachedConnectionId = ""
		clearSnap()
		dragWireCanvas.requestPaint()
		connectionsCanvas.requestPaint()
	}

	function setSnap(nodeId, socketId, worldX, worldY) {
		dragWire.snapped = true
		dragWire.snapNodeId = nodeId
		dragWire.snapSocketId = socketId
		dragWire.snapWorldX = worldX
		dragWire.snapWorldY = worldY
	}

	function clearSnap() {
		dragWire.snapped = false
		dragWire.snapNodeId = ""
		dragWire.snapSocketId = ""
	}

	// Nearest socket on the opposite side that the model would accept,
	// within the snap radius. Incompatible sockets are ignored entirely.
	function findSnapTarget(worldX, worldY) {
		var best = null
		var bestDist = root.snapRadiusPx / root.zoomFactor
		var lookForOutputs = !dragWire.fromOutput

		for (var i = 0; i < nodeRepeater.count; i++) {
			var delegate = nodeRepeater.itemAt(i)
			if (!delegate || delegate.nodeId === dragWire.anchorNodeId)
				continue

			var sockets = lookForOutputs ? delegate.nodeOutputs : delegate.nodeInputs
			for (var j = 0; j < sockets.length; j++) {
				var sock = sockets[j]
				var center = delegate.node.getSocketCenter(sock.id, lookForOutputs)
				var sx = delegate.x + center.x
				var sy = delegate.y + center.y
				var dist = Math.hypot(worldX - sx, worldY - sy)
				if (dist >= bestDist)
					continue

				var allowed = lookForOutputs
					? graphModel.isConnectionAllowed(delegate.nodeId, sock.id, dragWire.anchorNodeId, dragWire.anchorSocketId)
					: graphModel.isConnectionAllowed(dragWire.anchorNodeId, dragWire.anchorSocketId, delegate.nodeId, sock.id)
				if (!allowed)
					continue

				bestDist = dist
				best = { nodeId: delegate.nodeId, socketId: sock.id, worldX: sx, worldY: sy }
			}
		}
		return best
	}

	// -- Drawing ----------------------------------------------------------

	// Draws a wire from an output (x1, y1) to an input (x2, y2), in screen
	// coordinates. Wires leave outputs to the right and enter inputs from the left.
	function drawWire(ctx, x1, y1, x2, y2, color, dashed) {
		var offset = Math.max(Math.abs(x2 - x1) * 0.5, 40 * root.zoomFactor)
		ctx.strokeStyle = color
		ctx.lineWidth = Math.max(2.0, 3.0 * root.zoomFactor)
		ctx.lineCap = "round"
		ctx.setLineDash(dashed ? [6, 4] : [])
		ctx.beginPath()
		ctx.moveTo(x1, y1)
		ctx.bezierCurveTo(x1 + offset, y1, x2 - offset, y2, x2, y2)
		ctx.stroke()
		ctx.setLineDash([])
	}

	function repaintAll() {
		backgroundGrid.requestPaint()
		connectionsCanvas.requestPaint()
		if (dragWire.active)
			dragWireCanvas.requestPaint()
	}

	onPanXChanged: repaintAll()
	onPanYChanged: repaintAll()
	onZoomFactorChanged: repaintAll()
	onConnectionsChanged: connectionsCanvas.requestPaint()

	// -- Selection --------------------------------------------------------

	// Plain click selects only this node (or deselects it if it was the
	// only selection). Ctrl+click toggles it in the selection.
	function selectNode(nodeId, additive) {
		var next = selectedNodeIds.slice()
		var index = next.indexOf(nodeId)

		if (additive) {
			if (index !== -1)
				next.splice(index, 1)
			else
				next.push(nodeId)
		} else {
			next = (next.length === 1 && index !== -1) ? [] : [nodeId]
		}

		selectedNodeIds = next
		forceActiveFocus()
	}

	function deleteSelectedNodes() {
		var ids = selectedNodeIds.slice()
		selectedNodeIds = []
		for (var i = 0; i < ids.length; i++)
			graphModel.removeNode(ids[i])
	}

	// -- Keyboard ---------------------------------------------------------

	focus: true
	activeFocusOnTab: true

	Keys.onPressed: function(event) {
		if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
			deleteSelectedNodes()
			event.accepted = true
		} else if (event.key === Qt.Key_Escape && dragWire.active) {
			cancelWireDrag()
			event.accepted = true
		}
	}

	// -- Add-node popup (Shift+A) -----------------------------------------

	function openAddNodePopup() {
		var startX = root.mouseCanvasX > 0 ? root.mouseCanvasX : (root.width - addNodePopup.width) / 2
		var startY = root.mouseCanvasY > 0 ? root.mouseCanvasY : (root.height - addNodePopup.height) / 2
		root.popupX = Math.max(8, Math.min(root.width - addNodePopup.width - 8, startX))
		root.popupY = Math.max(8, Math.min(root.height - addNodePopup.height - 8, startY))
		addNodePopup.open()
	}

	function closeAddNodePopup() {
		root.forceActiveFocus()
		addNodePopup.close()
	}

	// Creates the node at the popup's position.
	function addNodeFromPopup(typeId) {
		graphModel.addNode(typeId,
			(root.popupX - root.panX) / root.zoomFactor,
			(root.popupY - root.panY) / root.zoomFactor)
		closeAddNodePopup()
	}

	// Closes the popup once the mouse moves well away from it.
	function checkPopupDistance() {
		if (!addNodePopup.visible)
			return

		var margin = 80
		var outside =
			root.mouseCanvasX < root.popupX - margin ||
			root.mouseCanvasX > root.popupX + addNodePopup.width + margin ||
			root.mouseCanvasY < root.popupY - margin ||
			root.mouseCanvasY > root.popupY + addNodePopup.height + margin

		if (outside)
			closeAddNodePopup()
	}

	HoverHandler {
		onPointChanged: {
			root.mouseCanvasX = point.position.x
			root.mouseCanvasY = point.position.y
			root.checkPopupDistance()
		}
	}

	Shortcut {
		sequence: "Shift+A"
		context: Qt.WindowShortcut
		onActivated: root.openAddNodePopup()
	}

	// -- Layers (bottom to top) -------------------------------------------

	// Background grid
	Canvas {
		id: backgroundGrid
		anchors.fill: parent

		onPaint: {
			var ctx = getContext("2d")
			ctx.clearRect(0, 0, width, height)
			ctx.strokeStyle = "#292e36"
			ctx.lineWidth = 1

			var spacing = 24 * root.zoomFactor
			if (spacing < 4)
				return

			var offsetX = ((root.panX % spacing) + spacing) % spacing
			var offsetY = ((root.panY % spacing) + spacing) % spacing

			for (var x = offsetX; x < width; x += spacing) {
				ctx.beginPath()
				ctx.moveTo(x, 0)
				ctx.lineTo(x, height)
				ctx.stroke()
			}
			for (var y = offsetY; y < height; y += spacing) {
				ctx.beginPath()
				ctx.moveTo(0, y)
				ctx.lineTo(width, y)
				ctx.stroke()
			}
		}
	}

	// Committed wires (drawn below nodes)
	Canvas {
		id: connectionsCanvas
		anchors.fill: parent

		onPaint: {
			var ctx = getContext("2d")
			ctx.clearRect(0, 0, width, height)

			for (var i = 0; i < root.connections.length; i++) {
				var conn = root.connections[i]
				if (conn.id === dragWire.detachedConnectionId)
					continue // Being dragged; drawn by dragWireCanvas instead.

				var src = root.getSocketWorldPos(conn.sourceNode, conn.sourcePort, true)
				var tgt = root.getSocketWorldPos(conn.targetNode, conn.targetPort, false)
				if (!src || !tgt)
					continue

				root.drawWire(ctx,
					root.toScreenX(src.x), root.toScreenY(src.y),
					root.toScreenX(tgt.x), root.toScreenY(tgt.y),
					SocketTypes.color(conn.dataType), false)
			}
		}
	}

	// Right-drag pans, wheel zooms around the cursor. Sits below the nodes,
	// so it only receives events on empty canvas.
	MouseArea {
		id: navigationMouse
		anchors.fill: parent
		acceptedButtons: Qt.RightButton
		hoverEnabled: true

		property real lastX: 0
		property real lastY: 0

		onPressed: function(mouse) {
			lastX = mouse.x
			lastY = mouse.y
		}

		onPositionChanged: function(mouse) {
			root.mouseCanvasX = mouse.x
			root.mouseCanvasY = mouse.y

			if (!(mouse.buttons & Qt.RightButton))
				return

			root.panX += mouse.x - lastX
			root.panY += mouse.y - lastY
			lastX = mouse.x
			lastY = mouse.y
		}

		onWheel: function(wheel) {
			var oldZoom = root.zoomFactor
			var factor = wheel.angleDelta.y > 0 ? 1.1 : 1 / 1.1
			var newZoom = Math.max(0.25, Math.min(3.0, oldZoom * factor))

			// Keep the world point under the cursor fixed while zooming.
			var worldX = (wheel.x - root.panX) / oldZoom
			var worldY = (wheel.y - root.panY) / oldZoom
			root.zoomFactor = newZoom
			root.panX = wheel.x - worldX * newZoom
			root.panY = wheel.y - worldY * newZoom

			wheel.accepted = true
		}
	}

	// World layer: holds all nodes, transformed by pan and zoom.
	Item {
		id: world

		x: root.panX
		y: root.panY

		transform: Scale {
			origin.x: 0
			origin.y: 0
			xScale: root.zoomFactor
			yScale: root.zoomFactor
		}

		Repeater {
			id: nodeRepeater
			model: graphModel

			delegate: Item {
				id: nodeDelegate

				required property string nodeId
				required property string nodeType
				required property string title
				required property real nodeX
				required property real nodeY
				required property var nodeInputs
				required property var nodeOutputs

				readonly property Node node: nodeItem
				readonly property bool isSelected: root.selectedNodeIds.indexOf(nodeId) !== -1

				width: nodeItem.implicitWidth
				height: nodeItem.implicitHeight

				// Dragging a node assigns x/y directly, which breaks a plain
				// binding to nodeX/nodeY. These handlers keep following the
				// model whenever it changes.
				x: nodeX
				y: nodeY
				onNodeXChanged: x = nodeX
				onNodeYChanged: y = nodeY

				onXChanged: connectionsCanvas.requestPaint()
				onYChanged: connectionsCanvas.requestPaint()

				Node {
					id: nodeItem
					anchors.fill: parent

					nodeId: nodeDelegate.nodeId
					nodeType: nodeDelegate.nodeType
					title: nodeDelegate.title
					nodeInputs: nodeDelegate.nodeInputs
					nodeOutputs: nodeDelegate.nodeOutputs
					connectedInputIds: root.connectedInputIdsFor(nodeDelegate.nodeId)
					selected: nodeDelegate.isSelected

					onSelectionRequested: (id, additive) => root.selectNode(id, additive)
					onWireDragStarted: (nId, sId, isOutput) => root.startWireDrag(nId, sId, isOutput)
					onWireDragMoved: (mouseArea, mouse) => root.updateWireDrag(mouseArea, mouse)
					onWireDragEnded: () => root.finishWireDrag()
					onDisconnectSocketRequested: (nId, sId) => graphModel.disconnectInput(nId, sId)
				}
			}
		}
	}

	// Wire being dragged (drawn above nodes)
	Canvas {
		id: dragWireCanvas
		anchors.fill: parent

		onPaint: {
			var ctx = getContext("2d")
			ctx.clearRect(0, 0, width, height)

			if (!dragWire.active)
				return

			var anchorX = root.toScreenX(dragWire.anchorWorldX)
			var anchorY = root.toScreenY(dragWire.anchorWorldY)
			var endX = root.toScreenX(dragWire.snapped ? dragWire.snapWorldX : dragWire.cursorWorldX)
			var endY = root.toScreenY(dragWire.snapped ? dragWire.snapWorldY : dragWire.cursorWorldY)
			var color = SocketTypes.color(dragWire.dataType)

			// Always draw output -> input so the curve bends the right way.
			if (dragWire.fromOutput)
				root.drawWire(ctx, anchorX, anchorY, endX, endY, color, !dragWire.snapped)
			else
				root.drawWire(ctx, endX, endY, anchorX, anchorY, color, !dragWire.snapped)

			if (dragWire.snapped) {
				ctx.fillStyle = color
				ctx.beginPath()
				ctx.arc(endX, endY, 6 * root.zoomFactor, 0, 2 * Math.PI)
				ctx.fill()
			}
		}
	}

	// Add-node popup (on top of everything)
	Popup {
		id: addNodePopup

		x: root.popupX
		y: root.popupY
		width: 220
		height: 320
		padding: 8

		background: Rectangle {
			color: "#20242b"
			radius: 8
			border.color: "#454a54"
		}

		onOpened: {
			nodeSearch.text = ""
			nodeSearch.forceActiveFocus()
		}

		ColumnLayout {
			anchors.fill: parent
			spacing: 8

			TextField {
				id: nodeSearch
				Layout.fillWidth: true
				placeholderText: "Search nodes..."
				focus: true

				// Enter adds the first match.
				onAccepted: {
					if (nodeListView.count > 0)
						root.addNodeFromPopup(nodeListView.model[0].typeId)
				}
			}

			ListView {
				id: nodeListView
				Layout.fillWidth: true
				Layout.fillHeight: true
				clip: true

				model: graphModel.availableNodeTypes.filter(function(entry) {
					return entry.title.toLowerCase().indexOf(nodeSearch.text.toLowerCase()) !== -1
				})

				delegate: ItemDelegate {
					required property var modelData

					width: ListView.view ? ListView.view.width : 0
					text: modelData.title
					onClicked: root.addNodeFromPopup(modelData.typeId)
				}
			}
		}
	}
}
