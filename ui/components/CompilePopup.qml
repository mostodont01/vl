pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

// Compile options. The settings live in the project (and are saved with it),
// so closing the popup any way keeps what was chosen.
//   Enter: compile    Escape / click outside: close
Popup {
	id: root

	signal compileRequested()

	parent: Overlay.overlay
	anchors.centerIn: parent
	width: 480
	modal: true
	dim: true
	padding: 20
	// While the folder picker is open, clicks in it must not close this popup.
	closePolicy: folderDialog.visible ? Popup.NoAutoClose
		: (Popup.CloseOnEscape | Popup.CloseOnPressOutside)

	background: Rectangle {
		color: "#202329"
		radius: 8
		border.color: "#383d46"
	}

	// Text fields only report on editingFinished; make sure the latest text
	// is stored before compiling.
	function commitFields() {
		project.setCompileSetting("executable_name", nameField.text)
		project.setCompileSetting("output_dir", outputField.text)
	}

	function compile() {
		commitFields()
		close()
		compileRequested()
	}

	onOpened: content.forceActiveFocus()

	component FieldLabel: Text {
		color: "#929ba8"
		font.pixelSize: 12
		Layout.alignment: Qt.AlignVCenter
	}

	// Drop-down for one of the project's compile choices.
	component ChoiceField: VComboBox {
		id: combo
		property string key: ""

		Layout.fillWidth: true
		model: project.compileChoices[key]
		textRole: "label"
		valueRole: "value"
		currentIndex: {
			var choices = project.compileChoices[key]
			for (var i = 0; i < choices.length; i++) {
				if (choices[i].value === project.compileSettings[key])
					return i
			}
			return 0
		}
		onActivated: project.setCompileSetting(key, currentValue)
	}

	FolderDialog {
		id: folderDialog
		title: "Choose Output Folder"
		onAccepted: project.setCompileSetting("output_dir", selectedFolder.toString())
	}

	ColumnLayout {
		id: content
		width: parent.width
		spacing: 14
		focus: true

		// Enter compiles from anywhere in the popup (text fields included).
		Keys.onReturnPressed: root.compile()
		Keys.onEnterPressed: root.compile()

		Text {
			text: "Compile"
			color: "#e3e7ed"
			font.pixelSize: 15
			font.weight: Font.DemiBold
		}

		GridLayout {
			Layout.fillWidth: true
			columns: 2
			columnSpacing: 14
			rowSpacing: 10

			FieldLabel { text: "Language" }
			ChoiceField { key: "language" }

			FieldLabel { text: "Target system" }
			ChoiceField { key: "target" }

			FieldLabel { text: "Build type" }
			ChoiceField { key: "build_type" }

			FieldLabel { text: "Executable name" }
			VTextField {
				id: nameField
				Layout.fillWidth: true
				text: project.compileSettings.executable_name
				placeholderText: project.hasFilePath ? project.displayName : "app"
				onEditingFinished: project.setCompileSetting("executable_name", text)
				onAccepted: root.compile()
			}

			FieldLabel { text: "Output folder" }
			RowLayout {
				Layout.fillWidth: true
				spacing: 6

				VTextField {
					id: outputField
					Layout.fillWidth: true
					text: project.compileSettings.output_dir
					placeholderText: project.defaultOutputDir || "Save the project or choose a folder"
					onEditingFinished: project.setCompileSetting("output_dir", text)
					onAccepted: root.compile()
				}
				VButton {
					text: "Browse…"
					onClicked: folderDialog.open()
				}
			}

			Item { width: 1; height: 1 }
			VCheckBox {
				text: "Run fullscreen"
				checked: project.compileSettings.fullscreen
				onToggled: project.setCompileSetting("fullscreen", checked)
			}
		}

		RowLayout {
			Layout.fillWidth: true
			Layout.topMargin: 6
			spacing: 8

			Text {
				Layout.fillWidth: true
				text: "Ctrl+B"
				color: "#687280"
				font.pixelSize: 11
			}

			VButton {
				text: "Cancel"
				onClicked: root.close()
			}
			VButton {
				text: "Compile"
				kind: "primary"
				onClicked: root.compile()
			}
		}
	}
}
