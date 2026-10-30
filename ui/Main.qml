pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "components"

ApplicationWindow {
	id: window
	width: 1440
	height: 900
	minimumWidth: 1000
	minimumHeight: 650
	visible: true
	title: (project.isDirty ? "• " : "") + project.displayName + " — VL"

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

	// Dark palette for the standard controls (menus, buttons, dialogs).
	palette.window: theme.panel
	palette.windowText: theme.text
	palette.base: theme.panelRaised
	palette.text: theme.text
	palette.button: theme.panelRaised
	palette.buttonText: theme.text
	palette.highlight: theme.accent
	palette.highlightedText: "#101722"
	palette.mid: theme.border
	palette.light: "#343943"
	palette.dark: "#15171b"
	palette.placeholderText: theme.muted

	// -- Project actions --------------------------------------------------
	// New/open/quit would throw away unsaved changes, so they go through
	// guarded(), which asks first. The action to run afterwards is parked in
	// pendingAction while the dialogs are open.

	property string pendingAction: ""
	property string pendingPath: ""
	property bool quitConfirmed: false
	// Set when Open was started from the startup popup: if it's cancelled or
	// fails, the popup comes back instead of leaving a blank project.
	property bool returnToStartup: false

	// Returns false if the action failed (only "openPath" can).
	function performAction(action, path) {
		switch (action) {
			case "new":
				project.newProject()
				nodeCanvasArea.resetView()
				break
			case "open":
				openDialog.open()
				break
			case "openPath":
				if (!project.openProject(path)) {
					reopenStartupIfNeeded()
					return false
				}
				returnToStartup = false
				nodeCanvasArea.frameAll()
				break
			case "quit":
				quitConfirmed = true
				window.close()
				break
		}
		return true
	}

	function reopenStartupIfNeeded() {
		if (returnToStartup)
			startupPopup.open()
		returnToStartup = false
	}

	function guarded(action, path) {
		if (!project.isDirty) {
			performAction(action, path)
			return
		}
		pendingAction = action
		pendingPath = path || ""
		unsavedDialog.open()
	}

	function runPendingAction() {
		var action = pendingAction
		var path = pendingPath
		clearPendingAction()
		if (action)
			performAction(action, path)
	}

	function clearPendingAction() {
		pendingAction = ""
		pendingPath = ""
	}

	// Save to the current file, or ask for one. Returns true if saved now.
	function save() {
		if (project.hasFilePath)
			return project.save()
		saveDialog.open()
		return false
	}

	onClosing: function(close) {
		if (!quitConfirmed && project.isDirty) {
			close.accepted = false
			guarded("quit")
		}
	}

	Shortcut { sequence: "Ctrl+N"; onActivated: window.guarded("new") }
	Shortcut { sequence: "Ctrl+O"; onActivated: window.guarded("open") }
	Shortcut { sequence: "Ctrl+S"; onActivated: window.save() }
	Shortcut { sequence: "Ctrl+Shift+S"; onActivated: saveDialog.open() }
	Shortcut { sequence: "Ctrl+Q"; onActivated: window.close() }
	Shortcut { sequence: "Ctrl+B"; onActivated: compilePopup.open() }
	Shortcut { sequence: "Ctrl+Z"; onActivated: graphModel.undo() }
	Shortcut { sequences: ["Ctrl+Shift+Z", "Ctrl+Y"]; onActivated: graphModel.redo() }

	// -- Dialogs ----------------------------------------------------------

	FileDialog {
		id: openDialog
		title: "Open Project"
		fileMode: FileDialog.OpenFile
		nameFilters: ["VL projects (*.vl)"]
		onAccepted: window.performAction("openPath", selectedFile.toString())
		onRejected: window.reopenStartupIfNeeded()
	}

	FileDialog {
		id: saveDialog
		title: "Save Project As"
		fileMode: FileDialog.SaveFile
		defaultSuffix: "vl"
		nameFilters: ["VL projects (*.vl)"]
		onAccepted: {
			if (project.saveAs(selectedFile.toString()))
				window.runPendingAction()
			else
				window.clearPendingAction()
		}
		onRejected: window.clearPendingAction()
	}

	MessageBox {
		id: unsavedDialog
		title: "Save changes to " + project.displayName + " before continuing?"
		text: "Your changes will be lost if you don't save them."
		buttons: ["Cancel", "Don't Save", "Save"]
		escapeButton: "Cancel"

		onClicked: function(button) {
			if (button === "Save") {
				// With no file yet, the save dialog runs the pending action.
				if (window.save())
					window.runPendingAction()
			} else if (button === "Don't Save") {
				window.runPendingAction()
			} else {
				window.clearPendingAction()
			}
		}
	}

	CompilePopup {
		id: compilePopup
		onCompileRequested: project.compileProject()
	}

	MessageBox {
		id: messageDialog
		buttons: ["OK"]
	}

	Connections {
		target: project
		function onMessageRaised(title, text) {
			messageDialog.title = title
			messageDialog.text = text
			messageDialog.open()
		}
	}

	// -- Layout -----------------------------------------------------------

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

				ToolButton {
					id: fileButton
					text: "File"
					onClicked: fileMenu.popup(fileButton, 0, fileButton.height)

					Menu {
						id: fileMenu
						width: 240

						ShortcutMenuItem { text: "New"; hint: "Ctrl+N"; onTriggered: window.guarded("new") }
						ShortcutMenuItem { text: "Open…"; hint: "Ctrl+O"; onTriggered: window.guarded("open") }

						Menu {
							id: recentMenu
							title: "Open Recent"
							enabled: project.recentProjects.length > 0

							Instantiator {
								model: project.recentProjects
								delegate: MenuItem {
									required property var modelData
									text: modelData.name + (modelData.exists ? "" : "  (missing)")
									enabled: modelData.exists
									onTriggered: window.guarded("openPath", modelData.path)
								}
								onObjectAdded: (index, object) => recentMenu.insertItem(index, object)
								onObjectRemoved: (index, object) => recentMenu.removeItem(object)
							}
						}

						MenuSeparator {}
						ShortcutMenuItem { text: "Save"; hint: "Ctrl+S"; onTriggered: window.save() }
						ShortcutMenuItem { text: "Save As…"; hint: "Ctrl+Shift+S"; onTriggered: saveDialog.open() }
						MenuSeparator {}
						ShortcutMenuItem { text: "Quit"; hint: "Ctrl+Q"; onTriggered: window.close() }
					}
				}

				Rectangle {
					Layout.preferredWidth: 1
					Layout.preferredHeight: 22
					color: theme.border
				}

				Text {
					text: project.displayName.toUpperCase() + (project.isDirty ? "  •" : "")
					color: theme.muted
					font.pixelSize: 11
					font.letterSpacing: 1.1
					ToolTip.visible: projectNameHover.hovered && project.hasFilePath
					ToolTip.text: project.filePath

					HoverHandler { id: projectNameHover }
				}

				Item { Layout.fillWidth: true }

				ToolButton {
					text: "Undo"
					enabled: graphModel.canUndo
					opacity: enabled ? 1.0 : 0.4
					display: AbstractButton.TextOnly
					onClicked: graphModel.undo()
				}
				ToolButton {
					text: "Redo"
					enabled: graphModel.canRedo
					opacity: enabled ? 1.0 : 0.4
					display: AbstractButton.TextOnly
					onClicked: graphModel.redo()
				}

				Rectangle {
					Layout.preferredWidth: 1
					Layout.preferredHeight: 22
					color: theme.border
				}

				Button {
					text: "Compile"
					onClicked: compilePopup.open()
					ToolTip.visible: hovered
					ToolTip.delay: 500
					ToolTip.text: "Compile options (Ctrl+B)"
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
					objectName: "nodeCanvas"
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

				// Issues pill (bottom-right of the canvas): error and warning
				// counts. Hovering shows the list above it.
				Column {
					id: issuesArea
					objectName: "issuesArea"
					anchors.right: parent.right
					anchors.bottom: parent.bottom
					anchors.margins: 12
					spacing: 6

					readonly property var issues: graphModel.issues
					readonly property int errorCount: issues.filter(i => i.severity === "error").length
					readonly property int warningCount: issues.length - errorCount
					readonly property color errorColor: "#f87171"
					readonly property color warningColor: "#fbbf24"

					HoverHandler { id: issuesHover }

					Rectangle {
						anchors.right: parent.right
						visible: issuesHover.hovered && issuesArea.issues.length > 0
						width: 360
						height: Math.min(issuesList.contentHeight + 12, 320)
						radius: 6
						color: "#20252c"
						border.color: theme.border

						ListView {
							id: issuesList
							anchors.fill: parent
							anchors.margins: 6
							clip: true
							spacing: 2
							model: issuesArea.issues

							delegate: Rectangle {
								id: issueRow
								required property var modelData
								width: ListView.view.width
								height: issueText.implicitHeight + 10
								radius: 4
								color: "#262b33"

								Text {
									id: issueIcon
									x: 8
									y: 5
									text: issueRow.modelData.severity === "error" ? "✕" : "⚠"
									color: issueRow.modelData.severity === "error"
										? issuesArea.errorColor : issuesArea.warningColor
									font.pixelSize: 12
								}

								Column {
									id: issueText
									anchors.left: issueIcon.right
									anchors.right: parent.right
									anchors.leftMargin: 8
									anchors.rightMargin: 8
									y: 5

									Text {
										width: parent.width
										text: issueRow.modelData.title
										color: theme.text
										font.pixelSize: 11
										font.weight: Font.DemiBold
										elide: Text.ElideRight
									}
									Text {
										width: parent.width
										text: issueRow.modelData.message
										color: theme.muted
										font.pixelSize: 11
										wrapMode: Text.WordWrap
									}
								}
							}
						}
					}

					Rectangle {
						anchors.right: parent.right
						width: issuesRow.implicitWidth + 24
						height: 28
						radius: 4
						color: issuesHover.hovered ? "#262b33" : "#20252c"
						border.color: theme.border

						Row {
							id: issuesRow
							anchors.centerIn: parent
							spacing: 12

							Text {
								visible: issuesArea.issues.length === 0
								text: "✓ NO ISSUES"
								color: theme.muted
								font.pixelSize: 10
								font.family: "monospace"
							}
							Text {
								visible: issuesArea.errorCount > 0
								text: issuesArea.errorCount + " ✕"
								color: issuesArea.errorColor
								font.pixelSize: 13
								font.family: "monospace"
							}
							Text {
								visible: issuesArea.warningCount > 0
								text: issuesArea.warningCount + " ⚠"
								color: issuesArea.warningColor
								font.pixelSize: 13
								font.family: "monospace"
							}
						}
					}
				}

				// Frame All button (top-right of the canvas)
				Rectangle {
					anchors.right: parent.right
					anchors.top: parent.top
					anchors.margins: 12
					width: frameText.implicitWidth + 20
					height: 26
					radius: 4
					color: frameMouse.containsMouse ? "#2a2f37" : "#20252c"
					border.color: theme.border

					Text {
						id: frameText
						anchors.centerIn: parent
						text: "FRAME ALL"
						color: theme.muted
						font.pixelSize: 10
						font.letterSpacing: 0.8
					}

					MouseArea {
						id: frameMouse
						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: nodeCanvasArea.frameAll()
					}

					ToolTip.visible: frameMouse.containsMouse
					ToolTip.delay: 500
					ToolTip.text: "Fit all nodes in view (Home)"
				}
			}

			// Inspector: only shown while exactly one node is selected.
			Rectangle {
				visible: nodeCanvasArea.inspectedNode !== null
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
						text: nodeCanvasArea.inspectedNode ? nodeCanvasArea.inspectedNode.title : ""
						color: theme.text
						font.pixelSize: 13
						font.weight: Font.DemiBold
					}

					Text {
						text: nodeCanvasArea.inspectedNode ? nodeCanvasArea.inspectedNode.nodeId : ""
						color: theme.muted
						font.pixelSize: 10
						font.family: "monospace"
					}

					// Placeholder until node JSON files provide inspector content.
					Text {
						text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
							+ "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. "
							+ "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris."
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

	// -- Startup popup ----------------------------------------------------
	// Shown on launch. Clicking outside (or Escape) just leaves the blank
	// project that is already open.

	component StartButton: Rectangle {
		id: startButton
		property string label: ""
		property string detail: ""
		signal clicked()

		implicitHeight: detail ? 40 : 30
		radius: 4
		color: !enabled ? "transparent" : startMouse.containsMouse ? "#2f343d" : "transparent"
		opacity: enabled ? 1.0 : 0.45

		Column {
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.leftMargin: 10
			anchors.rightMargin: 10
			anchors.verticalCenter: parent.verticalCenter
			spacing: 2

			Text {
				width: parent.width
				text: startButton.label
				color: theme.text
				font.pixelSize: 12
				elide: Text.ElideRight
			}
			Text {
				visible: startButton.detail !== ""
				width: parent.width
				text: startButton.detail
				color: theme.muted
				font.pixelSize: 10
				elide: Text.ElideMiddle
			}
		}

		MouseArea {
			id: startMouse
			anchors.fill: parent
			hoverEnabled: true
			cursorShape: Qt.PointingHandCursor
			onClicked: startButton.clicked()
		}
	}

	Popup {
		id: startupPopup
		objectName: "startupPopup"
		anchors.centerIn: Overlay.overlay
		width: 520
		height: 300
		modal: true
		dim: true
		padding: 0
		closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

		background: Rectangle {
			color: theme.panel
			radius: 8
			border.color: theme.border
		}

		onClosed: nodeCanvasArea.forceActiveFocus()

		ColumnLayout {
			anchors.fill: parent
			spacing: 0

			// Title bar
			Rectangle {
				Layout.fillWidth: true
				Layout.preferredHeight: 64
				color: "transparent"

				RowLayout {
					anchors.fill: parent
					anchors.leftMargin: 20
					spacing: 12

					Rectangle {
						Layout.preferredWidth: 32
						Layout.preferredHeight: 32
						radius: 7
						color: theme.accent

						Text {
							anchors.centerIn: parent
							text: "V"
							color: "#101722"
							font.pixelSize: 19
							font.weight: Font.Black
						}
					}

					Column {
						Text { text: "VL"; color: theme.text; font.pixelSize: 16; font.weight: Font.DemiBold }
						Text { text: "Visual Language"; color: theme.muted; font.pixelSize: 11 }
					}

					Item { Layout.fillWidth: true }
				}
			}

			Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.border }

			RowLayout {
				Layout.fillWidth: true
				Layout.fillHeight: true
				Layout.margins: 12
				spacing: 12

				// Left: new / open
				ColumnLayout {
					Layout.fillWidth: false
					Layout.preferredWidth: 150
					Layout.fillHeight: true
					spacing: 2

					Text {
						text: "START"
						color: theme.muted
						font.pixelSize: 10
						font.weight: Font.Bold
						font.letterSpacing: 1.2
						Layout.leftMargin: 10
						Layout.bottomMargin: 4
					}
					StartButton {
						Layout.fillWidth: true
						label: "New Project"
						onClicked: {
							startupPopup.close()
							window.guarded("new")
						}
					}
					StartButton {
						Layout.fillWidth: true
						label: "Open…"
						onClicked: {
							window.returnToStartup = true
							startupPopup.close()
							window.guarded("open")
						}
					}
					Item { Layout.fillHeight: true }
				}

				Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: theme.border }

				// Right: recent projects
				ColumnLayout {
					Layout.fillWidth: true
					Layout.fillHeight: true
					spacing: 2

					Text {
						text: "RECENT"
						color: theme.muted
						font.pixelSize: 10
						font.weight: Font.Bold
						font.letterSpacing: 1.2
						Layout.leftMargin: 10
						Layout.bottomMargin: 4
					}

					Text {
						visible: project.recentProjects.length === 0
						text: "No recent projects"
						color: theme.muted
						font.pixelSize: 12
						Layout.leftMargin: 10
					}

					ListView {
						Layout.fillWidth: true
						Layout.fillHeight: true
						clip: true
						spacing: 2
						model: project.recentProjects

						delegate: StartButton {
							required property var modelData
							width: ListView.view.width
							label: modelData.name + (modelData.exists ? "" : "  (missing)")
							detail: modelData.folder
							enabled: modelData.exists
							onClicked: {
								window.returnToStartup = true
								startupPopup.close()
								window.guarded("openPath", modelData.path)
							}
						}
					}
				}
			}
		}
	}

	Component.onCompleted: startupPopup.open()
}
