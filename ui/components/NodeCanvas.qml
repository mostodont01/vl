pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "SocketTypes.js" as SocketTypes

// The node editor canvas: grid, wires, nodes, navigation, selection,
// clipboard and the Shift+A add-node popup.
//
// Coordinates: nodes live in "world" coordinates (what the model stores).
// The visible "screen" position is  screen = pan + world * zoom.
Item {
	id: root

	// -- Navigation state -------------------------------------------------
	property real panX: 0
	property real panY: 0
	property real zoomFactor: 1.0
	readonly property real minZoom: 0.25
	readonly property real maxZoom: 3.0

	// Last known mouse position in screen coordinates.
	property real mouseCanvasX: 0
	property real mouseCanvasY: 0

	// Add-node popup position in screen coordinates.
	property real popupX: 0
	property real popupY: 0

	property var selectedNodeIds: []

	readonly property int nodeCount: nodeRepeater.count

	// The node shown in the inspector: only when exactly one is selected.
	readonly property var inspectedNode: selectedNodeIds.length === 1
		? findNodeDelegate(selectedNodeIds[0]) : null

	// Cached copy of the model's connections; bindings that read it update
	// automatically when connections change.
	readonly property var connections: graphModel ? graphModel.connections : []

	// How close (in screen pixels) the cursor must be to a socket to snap.
	readonly property real snapRadiusPx: 28
	// Mouse movement (screen pixels) before a press on a node becomes a drag.
	readonly property real dragThresholdPx: 3

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

	// -- View -------------------------------------------------------------

	function resetView() {
		root.zoomFactor = 1.0
		root.panX = 0
		root.panY = 0
	}

	// Zoom and pan so every node is visible. Zoom is clamped, so a very large
	// graph is centered at minimum zoom rather than shrunk to nothing.
	function frameAll() {
		if (nodeRepeater.count === 0) {
			resetView()
			return
		}

		var left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
		for (var i = 0; i < nodeRepeater.count; i++) {
			var d = nodeRepeater.itemAt(i)
			if (!d)
				continue
			left = Math.min(left, d.x)
			top = Math.min(top, d.y)
			right = Math.max(right, d.x + d.width)
			bottom = Math.max(bottom, d.y + d.height)
		}

		var padding = 60
		var zoom = Math.min((root.width - 2 * padding) / (right - left),
			(root.height - 2 * padding) / (bottom - top))
		zoom = Math.max(root.minZoom, Math.min(1.5, zoom))

		root.zoomFactor = zoom
		root.panX = root.width / 2 - (left + right) / 2 * zoom
		root.panY = root.height / 2 - (top + bottom) / 2 * zoom
	}

	// -- Wire dragging ----------------------------------------------------
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

		var source, sourcePort, target, targetPort
		if (dragWire.snapped) {
			source = dragWire.fromOutput ? dragWire.anchorNodeId : dragWire.snapNodeId
			sourcePort = dragWire.fromOutput ? dragWire.anchorSocketId : dragWire.snapSocketId
			target = dragWire.fromOutput ? dragWire.snapNodeId : dragWire.anchorNodeId
			targetPort = dragWire.fromOutput ? dragWire.snapSocketId : dragWire.anchorSocketId
		}

		var detachedId = dragWire.detachedConnectionId
		var backToOrigin = detachedId !== "" && dragWire.snapped
			&& dragWire.snapNodeId === dragWire.detachedNodeId
			&& dragWire.snapSocketId === dragWire.detachedSocketId

		endWireDrag()

		// Each of these is a single undo step.
		if (backToOrigin)
			return
		if (detachedId !== "" && source)
			graphModel.rerouteConnection(detachedId, source, sourcePort, target, targetPort)
		else if (detachedId !== "")
			graphModel.removeConnection(detachedId)
		else if (source)
			graphModel.addConnection(source, sourcePort, target, targetPort)
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
	// The anchor's own node is included: feedback loops are allowed.
	function findSnapTarget(worldX, worldY) {
		var best = null
		var bestDist = root.snapRadiusPx / root.zoomFactor
		var lookForOutputs = !dragWire.fromOutput

		for (var i = 0; i < nodeRepeater.count; i++) {
			var delegate = nodeRepeater.itemAt(i)
			if (!delegate)
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

	// -- Selection and moving nodes ---------------------------------------

	function clearSelection() {
		selectedNodeIds = []
		forceActiveFocus()
	}

	// Drop ids of nodes that no longer exist (after delete, undo, open...).
	function pruneSelection() {
		var kept = selectedNodeIds.filter(function(id) { return graphModel.hasNode(id) })
		if (kept.length !== selectedNodeIds.length)
			selectedNodeIds = kept
	}

	// Press on a node: select it (unless already selected) and get ready to
	// move the whole selection. Ctrl+click toggles instead.
	QtObject {
		id: nodeMove
		property string pressedNodeId: ""
		property bool ctrl: false
		property bool wasSelected: false
		property bool moving: false
		property real startScreenX: 0
		property real startScreenY: 0
		property var items: []      // [{delegate, x, y}] start positions of moved nodes
	}

	function nodePressed(nodeId, ctrl, mouseArea, mouse) {
		forceActiveFocus()
		var p = mouseArea.mapToItem(root, mouse.x, mouse.y)
		nodeMove.pressedNodeId = nodeId
		nodeMove.ctrl = ctrl
		nodeMove.wasSelected = selectedNodeIds.indexOf(nodeId) !== -1
		nodeMove.moving = false
		nodeMove.startScreenX = p.x
		nodeMove.startScreenY = p.y

		if (!ctrl && !nodeMove.wasSelected)
			selectedNodeIds = [nodeId]

		var items = []
		if (!ctrl) {
			for (var i = 0; i < selectedNodeIds.length; i++) {
				var d = findNodeDelegate(selectedNodeIds[i])
				if (d)
					items.push({ delegate: d, x: d.x, y: d.y })
			}
		}
		nodeMove.items = items
	}

	function nodeDragged(mouseArea, mouse) {
		if (nodeMove.items.length === 0)
			return
		var p = mouseArea.mapToItem(root, mouse.x, mouse.y)
		var dxScreen = p.x - nodeMove.startScreenX
		var dyScreen = p.y - nodeMove.startScreenY
		if (!nodeMove.moving && Math.hypot(dxScreen, dyScreen) < root.dragThresholdPx)
			return
		nodeMove.moving = true

		// Move the delegates directly for smooth feedback; the model is
		// updated once on release (one undo step for the whole move).
		for (var i = 0; i < nodeMove.items.length; i++) {
			var it = nodeMove.items[i]
			it.delegate.x = it.x + dxScreen / root.zoomFactor
			it.delegate.y = it.y + dyScreen / root.zoomFactor
		}
	}

	function nodeReleased() {
		if (nodeMove.moving) {
			var moves = nodeMove.items.map(function(it) {
				return { id: it.delegate.nodeId, x: it.delegate.x, y: it.delegate.y }
			})
			graphModel.moveNodes(moves)
		} else if (nodeMove.ctrl) {
			var next = selectedNodeIds.slice()
			var index = next.indexOf(nodeMove.pressedNodeId)
			if (index !== -1)
				next.splice(index, 1)
			else
				next.push(nodeMove.pressedNodeId)
			selectedNodeIds = next
		} else if (nodeMove.wasSelected) {
			// Plain click inside a multi-selection selects just that node.
			selectedNodeIds = [nodeMove.pressedNodeId]
		}
		nodeMove.items = []
		nodeMove.moving = false
	}

	// Shift + left-drag on empty canvas draws a selection box (screen coords).
	// Nodes touching the box are added to the selection.
	QtObject {
		id: boxSelect
		property bool active: false
		property real startX: 0
		property real startY: 0
		property real endX: 0
		property real endY: 0
	}

	function finishBoxSelect() {
		var x1 = (Math.min(boxSelect.startX, boxSelect.endX) - root.panX) / root.zoomFactor
		var y1 = (Math.min(boxSelect.startY, boxSelect.endY) - root.panY) / root.zoomFactor
		var x2 = (Math.max(boxSelect.startX, boxSelect.endX) - root.panX) / root.zoomFactor
		var y2 = (Math.max(boxSelect.startY, boxSelect.endY) - root.panY) / root.zoomFactor

		var next = selectedNodeIds.slice()
		for (var i = 0; i < nodeRepeater.count; i++) {
			var d = nodeRepeater.itemAt(i)
			var touches = d && d.x < x2 && d.x + d.width > x1 && d.y < y2 && d.y + d.height > y1
			if (touches && next.indexOf(d.nodeId) === -1)
				next.push(d.nodeId)
		}
		selectedNodeIds = next
		boxSelect.active = false
	}

	function deleteSelectedNodes() {
		var ids = selectedNodeIds.slice()
		selectedNodeIds = []
		graphModel.removeNodes(ids)
	}

	// -- Clipboard --------------------------------------------------------

	function mouseWorldX() { return (root.mouseCanvasX - root.panX) / root.zoomFactor }
	function mouseWorldY() { return (root.mouseCanvasY - root.panY) / root.zoomFactor }

	function copySelection() {
		graphModel.copyNodes(selectedNodeIds)
	}

	// Pastes at the mouse cursor and selects the pasted nodes.
	function paste() {
		var ids = graphModel.pasteNodes(mouseWorldX(), mouseWorldY())
		if (ids.length > 0)
			selectedNodeIds = ids
	}

	function duplicateSelection() {
		var ids = graphModel.duplicateNodes(selectedNodeIds, 30, 30)
		if (ids.length > 0)
			selectedNodeIds = ids
	}

	Shortcut { sequence: "Ctrl+C"; onActivated: root.copySelection() }
	Shortcut { sequence: "Ctrl+V"; onActivated: root.paste() }
	Shortcut { sequence: "Ctrl+D"; onActivated: root.duplicateSelection() }
	Shortcut { sequence: "Home"; onActivated: root.frameAll() }

	// -- Drawing ----------------------------------------------------------

	// Draws a wire from an output (x1, y1) to an input (x2, y2), in screen
	// coordinates. Wires leave outputs to the right and enter inputs from the left.
	// If loopY is given and the input is left of the output (a feedback wire),
	// the wire is routed below the nodes at loopY instead of behind them.
	function drawWire(ctx, x1, y1, x2, y2, color, dashed, loopY) {
		ctx.strokeStyle = color
		ctx.lineWidth = Math.max(2.0, 3.0 * root.zoomFactor)
		ctx.lineCap = "round"
		ctx.setLineDash(dashed ? [6, 4] : [])
		ctx.beginPath()
		ctx.moveTo(x1, y1)

		if (loopY !== undefined && x2 < x1) {
			var r = 40 * root.zoomFactor
			ctx.bezierCurveTo(x1 + r, y1, x1 + r, loopY, x1, loopY)
			ctx.lineTo(x2, loopY)
			ctx.bezierCurveTo(x2 - r, loopY, x2 - r, y2, x2, y2)
		} else {
			var offset = Math.max(Math.abs(x2 - x1) * 0.5, 40 * root.zoomFactor)
			ctx.bezierCurveTo(x1 + offset, y1, x2 - offset, y2, x2, y2)
		}

		ctx.stroke()
		ctx.setLineDash([])
	}

	// Screen y just below the lower of two nodes, for routing feedback wires.
	function loopYBelow(nodeIdA, nodeIdB) {
		var a = findNodeDelegate(nodeIdA)
		var b = findNodeDelegate(nodeIdB)
		var bottom = Math.max(a ? a.y + a.height : 0, b ? b.y + b.height : 0)
		return root.toScreenY(bottom + 20)
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

	Connections {
		target: graphModel
		function onModelReset() {
			root.pruneSelection()
			connectionsCanvas.requestPaint()
		}
		function onRowsRemoved() { root.pruneSelection() }
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
		var id = graphModel.addNode(typeId,
			(root.popupX - root.panX) / root.zoomFactor,
			(root.popupY - root.panY) / root.zoomFactor)
		if (id)
			selectedNodeIds = [id]
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
					SocketTypes.color(conn.dataType), false,
					root.loopYBelow(conn.sourceNode, conn.targetNode))
			}
		}
	}

	// Mouse on empty canvas (sits below the nodes, so it only gets presses
	// that no node took):
	//   left click          deselect all
	//   Shift + left-drag   box select
	//   right-drag          pan
	//   wheel               zoom around the cursor
	MouseArea {
		id: canvasMouse
		anchors.fill: parent
		acceptedButtons: Qt.LeftButton | Qt.RightButton
		hoverEnabled: true

		property real lastX: 0
		property real lastY: 0

		onPressed: function(mouse) {
			lastX = mouse.x
			lastY = mouse.y
			if (mouse.button === Qt.LeftButton && (mouse.modifiers & Qt.ShiftModifier)) {
				boxSelect.startX = mouse.x
				boxSelect.startY = mouse.y
				boxSelect.endX = mouse.x
				boxSelect.endY = mouse.y
				boxSelect.active = true
			}
		}

		onPositionChanged: function(mouse) {
			root.mouseCanvasX = mouse.x
			root.mouseCanvasY = mouse.y

			if (boxSelect.active) {
				boxSelect.endX = mouse.x
				boxSelect.endY = mouse.y
			} else if (mouse.buttons & Qt.RightButton) {
				root.panX += mouse.x - lastX
				root.panY += mouse.y - lastY
				lastX = mouse.x
				lastY = mouse.y
			}
		}

		onReleased: function(mouse) {
			if (mouse.button !== Qt.LeftButton)
				return
			if (boxSelect.active)
				root.finishBoxSelect()
			else
				root.clearSelection()
		}

		onWheel: function(wheel) {
			var oldZoom = root.zoomFactor
			var factor = wheel.angleDelta.y > 0 ? 1.1 : 1 / 1.1
			var newZoom = Math.max(root.minZoom, Math.min(root.maxZoom, oldZoom * factor))

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
				required property var nodeSettings
				required property var nodeValues
				required property bool hasAppWidget
				required property bool widgetVisible

				readonly property Node node: nodeItem
				readonly property bool isSelected: root.selectedNodeIds.indexOf(nodeId) !== -1

				width: nodeItem.implicitWidth
				height: nodeItem.implicitHeight

				// Moving a node assigns x/y directly, which breaks a plain
				// binding to nodeX/nodeY. These handlers keep following the
				// model whenever it changes.
				x: nodeX
				y: nodeY
				onNodeXChanged: x = nodeX
				onNodeYChanged: y = nodeY

				onXChanged: connectionsCanvas.requestPaint()
				onYChanged: connectionsCanvas.requestPaint()
				onHeightChanged: connectionsCanvas.requestPaint()

				Node {
					id: nodeItem
					anchors.fill: parent

					nodeId: nodeDelegate.nodeId
					nodeType: nodeDelegate.nodeType
					title: nodeDelegate.title
					nodeInputs: nodeDelegate.nodeInputs
					nodeOutputs: nodeDelegate.nodeOutputs
					nodeSettings: nodeDelegate.nodeSettings
					nodeValues: nodeDelegate.nodeValues
					hasAppWidget: nodeDelegate.hasAppWidget
					widgetVisible: nodeDelegate.widgetVisible
					connectedInputIds: root.connectedInputIdsFor(nodeDelegate.nodeId)
					selected: nodeDelegate.isSelected

					onBodyPressed: (id, ctrl, mouseArea, mouse) => root.nodePressed(id, ctrl, mouseArea, mouse)
					onBodyMoved: (mouseArea, mouse) => root.nodeDragged(mouseArea, mouse)
					onBodyReleased: root.nodeReleased()
					onWireDragStarted: (nId, sId, isOutput) => root.startWireDrag(nId, sId, isOutput)
					onWireDragMoved: (mouseArea, mouse) => root.updateWireDrag(mouseArea, mouse)
					onWireDragEnded: () => root.finishWireDrag()
					onDisconnectSocketRequested: (nId, sId) => graphModel.disconnectInput(nId, sId)
					onValueEdited: (nId, key, value) => graphModel.setNodeValue(nId, key, value)
					onEditingDone: root.forceActiveFocus()
					onWidgetVisibilityToggled: (nId) => graphModel.setWidgetVisible(nId, !nodeDelegate.widgetVisible)
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

	// Selection box
	Rectangle {
		visible: boxSelect.active
		x: Math.min(boxSelect.startX, boxSelect.endX)
		y: Math.min(boxSelect.startY, boxSelect.endY)
		width: Math.abs(boxSelect.endX - boxSelect.startX)
		height: Math.abs(boxSelect.endY - boxSelect.startY)
		color: "#1a72a7ff"
		border.color: "#72a7ff"
		border.width: 1
	}

	// Add-node popup (on top of everything)
	Popup {
		id: addNodePopup

		x: root.popupX
		y: root.popupY
		width: 220
		height: 420
		padding: 8

		background: Rectangle {
			color: "#20242b"
			radius: 8
			border.color: "#454a54"
		}

		// Categories the user has opened (category name -> true). All start
		// collapsed each time the popup opens.
		property var expanded: ({})

		// Rows shown in the list: a header per category, followed by its nodes
		// when that category is open. While searching, every category with a
		// match (in the node title or the category name) is shown open.
		readonly property var rows: {
			var query = nodeSearch.text.trim().toLowerCase()
			var result = []
			var types = graphModel.availableNodeTypes  // sorted by category, then title
			var i = 0
			while (i < types.length) {
				var category = types[i].category
				var matches = []
				for (; i < types.length && types[i].category === category; i++) {
					var t = types[i]
					if (query === "" || t.title.toLowerCase().indexOf(query) !== -1
							|| category.toLowerCase().indexOf(query) !== -1)
						matches.push(t)
				}
				if (matches.length === 0)
					continue

				var open = query !== "" || addNodePopup.expanded[category] === true
				result.push({ isHeader: true, category: category, open: open, count: matches.length })
				if (open) {
					for (var j = 0; j < matches.length; j++)
						result.push({ isHeader: false, category: category, typeId: matches[j].typeId, title: matches[j].title })
				}
			}
			return result
		}

		function toggleCategory(category) {
			var next = Object.assign({}, expanded)
			next[category] = !next[category]
			expanded = next
		}

		// Keyboard selection (Up/Down from the search field). Kept separately
		// from ListView.currentIndex, which resets whenever rows is rebuilt.
		property int selectedRow: 0

		function selectRow(index) {
			selectedRow = Math.max(0, Math.min(rows.length - 1, index))
			nodeListView.positionViewAtIndex(selectedRow, ListView.Contain)
		}

		// Enter: open/close the selected category, or add the selected node.
		function activateSelected() {
			var row = rows[selectedRow]
			if (!row)
				return
			if (row.isHeader)
				toggleCategory(row.category)
			else
				root.addNodeFromPopup(row.typeId)
		}

		// While searching, start on the first node rather than its header.
		function resetSelection() {
			var first = 0
			if (nodeSearch.text.trim() !== "") {
				for (var i = 0; i < rows.length; i++) {
					if (!rows[i].isHeader) {
						first = i
						break
					}
				}
			}
			selectRow(first)
		}

		onRowsChanged: {
			if (selectedRow >= rows.length)
				selectRow(rows.length - 1)
		}

		onOpened: {
			expanded = {}
			nodeSearch.text = ""
			selectRow(0)
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

				onTextChanged: addNodePopup.resetSelection()
				onAccepted: addNodePopup.activateSelected()
				Keys.onUpPressed: addNodePopup.selectRow(addNodePopup.selectedRow - 1)
				Keys.onDownPressed: addNodePopup.selectRow(addNodePopup.selectedRow + 1)
			}

			ListView {
				id: nodeListView
				Layout.fillWidth: true
				Layout.fillHeight: true
				clip: true
				model: addNodePopup.rows

				delegate: Rectangle {
					id: row
					required property var modelData
					required property int index

					readonly property bool selected: index === addNodePopup.selectedRow

					width: ListView.view ? ListView.view.width : 0
					height: modelData.isHeader ? 26 : 28
					radius: 4
					color: selected ? "#2a3a55" : rowMouse.containsMouse ? "#2f343d" : "transparent"
					border.color: selected ? "#72a7ff" : "transparent"

					// Category header: arrow, name and node count
					Row {
						visible: row.modelData.isHeader
						anchors.left: parent.left
						anchors.leftMargin: 6
						anchors.verticalCenter: parent.verticalCenter
						spacing: 6

						Text {
							width: 10
							text: row.modelData.open ? "▾" : "▸"
							color: "#929ba8"
							font.pixelSize: 11
						}
						Text {
							text: row.modelData.category.toUpperCase()
							color: "#b9c0cb"
							font.pixelSize: 10
							font.weight: Font.Bold
							font.letterSpacing: 1.1
						}
						Text {
							text: row.modelData.isHeader ? String(row.modelData.count) : ""
							color: "#687280"
							font.pixelSize: 10
						}
					}

					// Node entry
					Text {
						visible: !row.modelData.isHeader
						anchors.left: parent.left
						anchors.leftMargin: 24
						anchors.verticalCenter: parent.verticalCenter
						text: row.modelData.title || ""
						color: "#e2e7ef"
						font.pixelSize: 12
					}

					MouseArea {
						id: rowMouse
						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: {
							addNodePopup.selectedRow = row.index
							addNodePopup.activateSelected()
							nodeSearch.forceActiveFocus()
						}
					}
				}
			}
		}
	}
}
