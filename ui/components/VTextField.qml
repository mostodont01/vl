import QtQuick
import QtQuick.Controls

// Themed single-line text field.
TextField {
	id: control

	implicitHeight: 28
	leftPadding: 9
	rightPadding: 9
	topPadding: 0
	bottomPadding: 0
	verticalAlignment: TextInput.AlignVCenter
	font.pixelSize: 12
	color: "#e3e7ed"
	placeholderTextColor: "#687280"
	selectionColor: "#3b6fd4"
	selectedTextColor: "#ffffff"
	selectByMouse: true

	background: Rectangle {
		radius: 5
		color: control.activeFocus ? "#15171b" : "#1d2025"
		border.color: control.activeFocus ? "#72a7ff" : control.hovered ? "#4a515c" : "#3a404a"
	}
}
