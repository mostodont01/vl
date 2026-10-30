import QtQuick
import QtQuick.Controls

// Themed menu. Items are ShortcutMenuItem (also for submenus) and VMenuSeparator.
Menu {
	id: control

	padding: 4
	delegate: ShortcutMenuItem {}

	background: Rectangle {
		implicitWidth: 220
		color: "#20242b"
		radius: 6
		border.color: "#454a54"
	}
}
