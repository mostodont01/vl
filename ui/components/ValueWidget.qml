pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// Inline editor for one node value (a setting, or an input with nothing
// connected). Which editor is shown, and its limits, come from the node's JSON
// definition: widget = {kind, default, min, max, options, integer}.
//
// The widget never changes the value itself: it emits edited(value) and the
// model decides (and may clamp or reject it).
Item {
	id: root

	property var widget: ({})
	property var value
	property color accentColor: "#72a7ff"

	signal edited(var value)
	// Editing ended (Enter, Escape or a choice made): give focus back to the canvas.
	signal editingDone()

	readonly property var effectiveValue: value !== undefined && value !== null ? value : widget.default

	implicitHeight: 20

	function displayText() {
		var v = root.effectiveValue
		return v === undefined || v === null ? "" : String(v)
	}

	function commitText(text) {
		if (root.widget.kind === "number") {
			var n = Number(text)
			if (text.trim() === "" || isNaN(n))
				return // Invalid: the field reverts to the current value.
			root.edited(n)
		} else {
			root.edited(text)
		}
	}

	Loader {
		anchors.fill: parent
		sourceComponent: {
			switch (root.widget.kind) {
				case "number":
				case "string":
					return textEditor
				case "select":
					return selectEditor
				case "checkbox":
					return checkboxEditor
				default:
					return null
			}
		}
	}

	// Number and string fields
	Component {
		id: textEditor

		Rectangle {
			radius: 3
			color: input.activeFocus ? "#15171b" : "#1d2025"
			border.color: input.activeFocus ? root.accentColor : "#3a404a"

			TextInput {
				id: input
				anchors.fill: parent
				anchors.leftMargin: 6
				anchors.rightMargin: 6
				verticalAlignment: TextInput.AlignVCenter
				horizontalAlignment: root.widget.kind === "number" ? TextInput.AlignHCenter : TextInput.AlignLeft
				clip: true
				selectByMouse: true
				color: "#e2e7ef"
				selectionColor: root.accentColor
				font.pixelSize: 11

				// Only restrict which characters can be typed; range checks happen in the model.
				validator: RegularExpressionValidator {
					regularExpression: root.widget.kind !== "number" ? /.*/
						: root.widget.integer ? /-?\d*/ : /-?\d*\.?\d*/
				}

				text: root.displayText()

				function revert() {
					text = Qt.binding(function() { return root.displayText() })
				}

				onEditingFinished: {
					root.commitText(text)
					revert() // Show what the model actually stored.
				}
				onAccepted: root.editingDone()
				Keys.onEscapePressed: {
					revert()
					root.editingDone()
				}
			}
		}
	}

	// Drop-down list
	Component {
		id: selectEditor

		Rectangle {
			id: selectBox
			radius: 3
			color: selectMouse.containsMouse ? "#262a31" : "#1d2025"
			border.color: optionsPopup.visible ? root.accentColor : "#3a404a"

			Text {
				anchors.left: parent.left
				anchors.right: arrow.left
				anchors.leftMargin: 6
				anchors.verticalCenter: parent.verticalCenter
				text: root.displayText()
				color: "#e2e7ef"
				font.pixelSize: 11
				elide: Text.ElideRight
			}

			Text {
				id: arrow
				anchors.right: parent.right
				anchors.rightMargin: 6
				anchors.verticalCenter: parent.verticalCenter
				text: "▾"
				color: "#929ba8"
				font.pixelSize: 10
			}

			MouseArea {
				id: selectMouse
				anchors.fill: parent
				hoverEnabled: true
				cursorShape: Qt.PointingHandCursor
				onClicked: optionsPopup.open()
			}

			Popup {
				id: optionsPopup
				y: selectBox.height + 2
				width: selectBox.width
				padding: 2

				background: Rectangle {
					color: "#20242b"
					radius: 4
					border.color: "#454a54"
				}

				contentItem: Column {
					Repeater {
						model: root.widget.options

						delegate: Rectangle {
							id: option
							required property string modelData

							width: optionsPopup.availableWidth
							height: 20
							radius: 3
							color: optionMouse.containsMouse ? "#343943"
								: option.modelData === root.effectiveValue ? "#2a3140" : "transparent"

							Text {
								anchors.left: parent.left
								anchors.leftMargin: 6
								anchors.verticalCenter: parent.verticalCenter
								text: option.modelData
								color: "#e2e7ef"
								font.pixelSize: 11
							}

							MouseArea {
								id: optionMouse
								anchors.fill: parent
								hoverEnabled: true
								onClicked: {
									optionsPopup.close()
									root.edited(option.modelData)
									root.editingDone()
								}
							}
						}
					}
				}
			}
		}
	}

	// Checkbox
	Component {
		id: checkboxEditor

		Item {
			Rectangle {
				anchors.verticalCenter: parent.verticalCenter
				width: 14
				height: 14
				radius: 3
				color: root.effectiveValue ? root.accentColor : "#1d2025"
				border.color: root.effectiveValue ? root.accentColor : "#3a404a"

				Text {
					anchors.centerIn: parent
					visible: root.effectiveValue === true
					text: "✓"
					color: "#101722"
					font.pixelSize: 11
					font.bold: true
				}
			}

			MouseArea {
				width: 14
				height: parent.height
				cursorShape: Qt.PointingHandCursor
				onClicked: root.edited(!root.effectiveValue)
			}
		}
	}
}
