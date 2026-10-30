pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// Small colour chooser: preset swatches plus a hex field.
// Set title and currentColor, open(), and handle picked(color).
Popup {
	id: root

	property string title: ""
	property string currentColor: "#72a7ff"

	signal picked(string color)

	parent: Overlay.overlay
	anchors.centerIn: parent
	width: 252
	modal: true
	dim: false
	padding: 14
	closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

	background: Rectangle {
		color: "#20242b"
		radius: 8
		border.color: "#454a54"
	}

	function isHex(text) {
		return /^#[0-9a-fA-F]{6}$/.test(text)
	}

	function choose(color) {
		close()
		picked(color.toLowerCase())
	}

	onAboutToShow: hexField.text = currentColor

	Column {
		spacing: 12

		Text {
			text: root.title
			color: "#e3e7ed"
			font.pixelSize: 12
			font.weight: Font.DemiBold
			width: 224
			elide: Text.ElideRight
		}

		Grid {
			columns: 6
			spacing: 6

			Repeater {
				model: project.presetColors

				delegate: Rectangle {
					id: swatch
					required property string modelData
					width: 32
					height: 32
					radius: 5
					color: modelData
					border.color: modelData === root.currentColor.toLowerCase() ? "#ffffff"
						: swatchMouse.containsMouse ? "#c0c6d0" : "transparent"
					border.width: 2

					MouseArea {
						id: swatchMouse
						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: root.choose(swatch.modelData)
					}
				}
			}
		}

		Row {
			spacing: 8

			Rectangle {
				width: 28
				height: 28
				radius: 5
				color: root.isHex(hexField.text) ? hexField.text : "transparent"
				border.color: "#454a54"
			}

			VTextField {
				id: hexField
				width: 112
				placeholderText: "#rrggbb"
				onAccepted: if (root.isHex(text)) root.choose(text)
			}

			VButton {
				text: "Set"
				enabled: root.isHex(hexField.text)
				onClicked: root.choose(hexField.text)
			}
		}
	}
}
