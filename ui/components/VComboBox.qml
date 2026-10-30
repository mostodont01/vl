import QtQuick
import QtQuick.Controls

// Themed drop-down list. Works with a plain array or an array of objects
// (set textRole / valueRole as usual).
ComboBox {
	id: control

	implicitHeight: 28
	font.pixelSize: 12
	hoverEnabled: true

	function entryText(entry) {
		return control.textRole && typeof entry === "object" ? entry[control.textRole] : entry
	}

	background: Rectangle {
		radius: 5
		color: control.hovered ? "#23272e" : "#1d2025"
		border.color: control.popup.visible || control.visualFocus ? "#72a7ff"
			: control.hovered ? "#4a515c" : "#3a404a"
	}

	contentItem: Text {
		leftPadding: 10
		rightPadding: control.indicator.width + 14
		text: control.displayText
		font: control.font
		color: "#e3e7ed"
		verticalAlignment: Text.AlignVCenter
		elide: Text.ElideRight
	}

	indicator: Text {
		x: control.width - width - 10
		y: (control.height - height) / 2
		text: "▾"
		color: "#929ba8"
		font.pixelSize: 11
	}

	delegate: ItemDelegate {
		id: entry
		required property var modelData
		required property int index

		width: ListView.view ? ListView.view.width : control.width
		height: 28
		highlighted: control.highlightedIndex === index
		leftPadding: 8

		contentItem: Text {
			text: control.entryText(entry.modelData)
			font: control.font
			color: entry.index === control.currentIndex ? "#9ec2ff" : "#e3e7ed"
			verticalAlignment: Text.AlignVCenter
			elide: Text.ElideRight
		}

		background: Rectangle {
			radius: 4
			color: entry.highlighted ? "#2f3a4d" : "transparent"
		}
	}

	popup: Popup {
		y: control.height + 4
		width: control.width
		padding: 4
		implicitHeight: Math.min(contentItem.implicitHeight + 8, 300)

		contentItem: ListView {
			clip: true
			implicitHeight: contentHeight
			model: control.popup.visible ? control.delegateModel : null
			currentIndex: control.highlightedIndex
		}

		background: Rectangle {
			color: "#20242b"
			radius: 6
			border.color: "#454a54"
		}
	}
}
