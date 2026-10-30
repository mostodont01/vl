import QtQuick
import QtQuick.Controls

// Themed menu item that shows its keyboard shortcut on the right. This is
// only the hint: the shortcut itself is a Shortcut in Main.qml, so it also
// works while the menu is closed. Submenus show an arrow instead.
MenuItem {
	id: item

	property string hint: ""

	implicitHeight: 28
	leftPadding: 10
	rightPadding: 10
	font.pixelSize: 12
	arrow: null

	contentItem: Item {
		implicitWidth: label.implicitWidth + hintLabel.implicitWidth + 32
		implicitHeight: label.implicitHeight

		Text {
			id: label
			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			text: item.text
			font: item.font
			color: "#e3e7ed"
			opacity: item.enabled ? 1.0 : 0.4
		}

		Text {
			id: hintLabel
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			text: item.subMenu ? "▸" : item.hint
			font.pixelSize: 11
			color: "#7f8996"
			opacity: item.enabled ? 1.0 : 0.4
		}
	}

	background: Rectangle {
		radius: 4
		color: item.highlighted && item.enabled ? "#2f3a4d" : "transparent"
	}
}
