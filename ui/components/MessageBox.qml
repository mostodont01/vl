pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A themed message dialog: title, text and a row of buttons (left to right).
// clicked(label) reports the chosen button. Used instead of Qt's
// MessageDialog, which doesn't match the theme and logs binding-loop warnings.
Popup {
	id: root

	property string title: ""
	property string text: ""
	property var buttons: ["OK"]
	property string defaultButton: buttons[buttons.length - 1]
	// Reported when the dialog is closed with Escape; "" reports nothing.
	property string escapeButton: ""

	signal clicked(string button)

	property bool answered: false

	parent: Overlay.overlay
	anchors.centerIn: parent
	width: 420
	modal: true
	dim: true
	padding: 20
	closePolicy: Popup.CloseOnEscape

	background: Rectangle {
		color: "#202329"
		radius: 8
		border.color: "#383d46"
	}

	function choose(button) {
		answered = true
		close()
		clicked(button)
	}

	onAboutToShow: answered = false
	onClosed: {
		if (!answered && escapeButton !== "")
			clicked(escapeButton)
	}

	ColumnLayout {
		width: parent.width
		spacing: 10

		Text {
			Layout.fillWidth: true
			text: root.title
			color: "#e3e7ed"
			font.pixelSize: 14
			font.weight: Font.DemiBold
			wrapMode: Text.WordWrap
		}

		Text {
			Layout.fillWidth: true
			visible: root.text !== ""
			text: root.text
			color: "#929ba8"
			font.pixelSize: 12
			wrapMode: Text.WordWrap
		}

		RowLayout {
			Layout.fillWidth: true
			Layout.topMargin: 8
			spacing: 8

			Item { Layout.fillWidth: true }

			Repeater {
				model: root.buttons

				delegate: VButton {
					required property string modelData
					text: modelData
					kind: modelData === root.defaultButton ? "primary" : "normal"
					onClicked: root.choose(modelData)
				}
			}
		}
	}
}
