import QtQuick
import QtQuick.Controls

// Themed push button.
//   kind:   "normal", "primary" (the main action) or "danger" (destructive)
//   subtle: no background until hovered (toolbar buttons)
Button {
	id: control

	property string kind: "normal"
	property bool subtle: false

	readonly property color baseColor: kind === "primary" ? "#3b6fd4"
		: kind === "danger" ? "#3a2427" : "#2a2f37"
	readonly property color borderColor: kind === "primary" ? "#5a8be6"
		: kind === "danger" ? "#6b3238" : "#3d434d"
	readonly property color textColor: kind === "primary" ? "#ffffff"
		: kind === "danger" ? "#fca5a5" : "#e3e7ed"

	implicitHeight: 28
	leftPadding: 12
	rightPadding: 12
	topPadding: 0
	bottomPadding: 0
	font.pixelSize: 12
	hoverEnabled: true

	contentItem: Text {
		text: control.text
		font: control.font
		color: control.textColor
		opacity: control.enabled ? 1.0 : 0.4
		horizontalAlignment: Text.AlignHCenter
		verticalAlignment: Text.AlignVCenter
		elide: Text.ElideRight
	}

	background: Rectangle {
		radius: 5
		visible: !control.subtle || control.hovered || control.down
		color: control.down ? Qt.darker(control.baseColor, 1.2)
			: control.hovered && control.enabled ? Qt.lighter(control.baseColor, 1.18)
			: control.baseColor
		border.color: control.visualFocus ? "#72a7ff" : control.borderColor
		opacity: control.enabled ? 1.0 : 0.5

		Behavior on color { ColorAnimation { duration: 80 } }
	}
}
