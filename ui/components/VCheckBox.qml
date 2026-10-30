import QtQuick
import QtQuick.Controls

// Themed checkbox.
CheckBox {
	id: control

	font.pixelSize: 12
	spacing: 8
	padding: 0

	indicator: Rectangle {
		x: control.leftPadding
		y: (control.height - height) / 2
		width: 16
		height: 16
		radius: 4
		color: control.checked ? "#3b6fd4" : "#1d2025"
		border.color: control.checked ? "#5a8be6" : control.hovered ? "#4a515c" : "#3a404a"

		Text {
			anchors.centerIn: parent
			visible: control.checked
			text: "✓"
			color: "#ffffff"
			font.pixelSize: 11
			font.bold: true
		}
	}

	contentItem: Text {
		leftPadding: control.indicator.width + control.spacing
		text: control.text
		font: control.font
		color: "#e3e7ed"
		verticalAlignment: Text.AlignVCenter
	}
}
