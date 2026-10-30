import QtQuick

// A short message that appears and fades out by itself. Call show(text).
Rectangle {
	id: root

	function show(message) {
		label.text = message
		fadeOut.stop()
		opacity = 1
		hideTimer.restart()
	}

	width: Math.min(label.implicitWidth + 24, 420)
	height: label.implicitHeight + 14
	radius: 4
	color: "#2a2f37"
	border.color: "#454a54"
	opacity: 0
	visible: opacity > 0

	Text {
		id: label
		anchors.centerIn: parent
		width: Math.min(implicitWidth, 396)
		color: "#e3e7ed"
		font.pixelSize: 11
		wrapMode: Text.WordWrap
	}

	Timer {
		id: hideTimer
		interval: 3500
		onTriggered: fadeOut.start()
	}

	NumberAnimation on opacity {
		id: fadeOut
		running: false
		to: 0
		duration: 400
	}
}
