// Shared helpers for socket data types. Imported by Node.qml and NodeCanvas.qml
// so sockets and wires always agree on colours.
.pragma library

function color(typeName) {
	switch (typeName) {
		case "LidarScan":
			return "#2dd4bf"
		case "int32":
			return "#f59e0b"
		case "float32":
		case "float":
			return "#4ade80"
		case "bool":
			return "#c084fc"
		default:
			return "#72a7ff"
	}
}
