import QtQuick
import QtQuick.Controls

// Menu item that shows its keyboard shortcut on the right. This is only the
// hint: the shortcut itself is a Shortcut in Main.qml, so it also works while
// the menu is closed.
MenuItem {
	id: item

	property string hint: ""

	contentItem: Item {
		implicitWidth: label.implicitWidth + hintLabel.implicitWidth + 32
		implicitHeight: label.implicitHeight

		Text {
			id: label
			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			text: item.text
			font: item.font
			color: item.highlighted ? item.palette.highlightedText : item.palette.text
			opacity: item.enabled ? 1.0 : 0.45
		}

		Text {
			id: hintLabel
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			text: item.hint
			font.pixelSize: 11
			color: item.highlighted ? item.palette.highlightedText : "#929ba8"
		}
	}
}
