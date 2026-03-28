import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    id: root
    visible: true
    width: 470
    height: 524
    color: "#000000"
    title: "PDCApp"

    // Distance thresholds (cm)
    readonly property int greenThreshold: 50
    readonly property int yellowThreshold: 30
    readonly property int redThreshold: 15

    property int currentDistance: vehicleControlClient.currentDistance
    property bool noSignal: !vehicleControlClient.serviceAvailable
    property int frameCounter: 0

    property string distanceZone: {
        if (currentDistance > greenThreshold) return "safe"
        else if (currentDistance > yellowThreshold) return "green"
        else if (currentDistance > redThreshold) return "yellow"
        else return "red"
    }

    property color zoneColor: {
        if (distanceZone === "red")    return "#FF0000"
        if (distanceZone === "yellow") return "#FFBB00"
        if (distanceZone === "green")  return "#00FF00"
        return "#888888"
    }

    Connections {
        target: videoReceiver
        function onFrameReady() { frameCounter++ }
    }

    // ── Full-screen camera feed ──────────────────────────────────────
    Image {
        id: cameraImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        cache: false
        source: "image://camera/frame?" + frameCounter

        // "Waiting" overlay — shown until a frame arrives
        Rectangle {
            anchors.centerIn: parent
            width: waitText.width + 40
            height: waitText.height + 20
            color: "#80000000"
            radius: 10
            visible: !videoReceiver.receiving || !videoReceiver.hasFrame

            Text {
                id: waitText
                anchors.centerIn: parent
                text: videoReceiver.receiving ? "Waiting for video..." : "Camera Starting..."
                font.pixelSize: 18
                color: "#FFFFFF"
            }
        }
    }

    // ── Camera guide overlay (trapezoid zone lines) ──────────────────
    Item {
        id: cameraGuide
        anchors.fill: parent

        // Trapezoid occupies the lower portion of the screen (typical real-car PDC style).
        // Top of trap at ~40% down, bottom near screen edge.
        // topLeftX/topRightX are the widths at trapTopY; bottomLeftX/bottomRightX at trapBottomY.
        readonly property real trapTopY: 0.40
        readonly property real trapBottomY: 0.96
        readonly property real topLeftX: 0.38
        readonly property real topRightX: 0.62
        readonly property real bottomLeftX: 0.10
        readonly property real bottomRightX: 0.90
        readonly property real zone1End: trapTopY + (trapBottomY - trapTopY) * 0.33
        readonly property real zone2Start: zone1End
        readonly property real zone2End: trapTopY + (trapBottomY - trapTopY) * 0.67
        readonly property real zone3Start: zone2End

        function leftX(yFrac) {
            var t = (yFrac - trapTopY) / (trapBottomY - trapTopY)
            return topLeftX + (bottomLeftX - topLeftX) * t
        }
        function rightX(yFrac) {
            var t = (yFrac - trapTopY) / (trapBottomY - trapTopY)
            return topRightX + (bottomRightX - topRightX) * t
        }

        // Red zone guide (bottom third)
        Canvas {
            anchors.fill: parent
            opacity: (noSignal || distanceZone === "safe") ? 0.0
                   : distanceZone === "red" ? 0.85 : 0.5
            Behavior on opacity { NumberAnimation { duration: 300 } }
            SequentialAnimation on opacity {
                running: distanceZone === "red" && !noSignal
                loops: Animation.Infinite
                NumberAnimation { from: 0.85; to: 0.2; duration: 400 }
                NumberAnimation { from: 0.2; to: 0.85; duration: 400 }
            }
            onPaint: {
                var ctx = getContext("2d"), w = width, h = height
                ctx.clearRect(0, 0, w, h)
                ctx.strokeStyle = "#FF0000"; ctx.lineWidth = 10; ctx.lineCap = "round"
                var y1 = cameraGuide.zone3Start, y2 = cameraGuide.trapBottomY, m = w * 0.07
                ctx.beginPath(); ctx.moveTo(cameraGuide.leftX(y1)*w,  y1*h); ctx.lineTo(cameraGuide.leftX(y2)*w,  y2*h); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cameraGuide.leftX(y1)*w,  y1*h); ctx.lineTo(cameraGuide.leftX(y1)*w+m, y1*h); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cameraGuide.rightX(y1)*w, y1*h); ctx.lineTo(cameraGuide.rightX(y2)*w, y2*h); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cameraGuide.rightX(y1)*w, y1*h); ctx.lineTo(cameraGuide.rightX(y1)*w-m, y1*h); ctx.stroke()
            }
        }

        // Yellow zone guide (middle third)
        Canvas {
            anchors.fill: parent
            opacity: (noSignal || distanceZone === "safe") ? 0.0
                   : distanceZone === "yellow" ? 0.85
                   : distanceZone === "green"  ? 0.5 : 0.0
            Behavior on opacity { NumberAnimation { duration: 300 } }
            SequentialAnimation on opacity {
                running: distanceZone === "yellow" && !noSignal
                loops: Animation.Infinite
                NumberAnimation { from: 0.85; to: 0.2; duration: 400 }
                NumberAnimation { from: 0.2; to: 0.85; duration: 400 }
            }
            onPaint: {
                var ctx = getContext("2d"), w = width, h = height
                ctx.clearRect(0, 0, w, h)
                ctx.strokeStyle = "#FFBB00"; ctx.lineWidth = 10; ctx.lineCap = "round"
                var y1 = cameraGuide.zone2Start, y2 = cameraGuide.zone2End, m = w * 0.07
                ctx.beginPath(); ctx.moveTo(cameraGuide.leftX(y1)*w,  y1*h); ctx.lineTo(cameraGuide.leftX(y2)*w,  y2*h); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cameraGuide.leftX(y1)*w,  y1*h); ctx.lineTo(cameraGuide.leftX(y1)*w+m, y1*h); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cameraGuide.rightX(y1)*w, y1*h); ctx.lineTo(cameraGuide.rightX(y2)*w, y2*h); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cameraGuide.rightX(y1)*w, y1*h); ctx.lineTo(cameraGuide.rightX(y1)*w-m, y1*h); ctx.stroke()
            }
        }

        // Green zone guide (top third)
        Canvas {
            anchors.fill: parent
            opacity: (!noSignal && distanceZone === "green") ? 0.85 : 0.0
            Behavior on opacity { NumberAnimation { duration: 300 } }
            SequentialAnimation on opacity {
                running: distanceZone === "green" && !noSignal
                loops: Animation.Infinite
                NumberAnimation { from: 0.85; to: 0.2; duration: 400 }
                NumberAnimation { from: 0.2; to: 0.85; duration: 400 }
            }
            onPaint: {
                var ctx = getContext("2d"), w = width, h = height
                ctx.clearRect(0, 0, w, h)
                ctx.strokeStyle = "#44FF44"; ctx.lineWidth = 10; ctx.lineCap = "round"
                var y1 = cameraGuide.trapTopY, y2 = cameraGuide.zone1End, m = w * 0.07
                ctx.beginPath(); ctx.moveTo(cameraGuide.leftX(y1)*w,  y1*h); ctx.lineTo(cameraGuide.leftX(y2)*w,  y2*h); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cameraGuide.leftX(y1)*w,  y1*h); ctx.lineTo(cameraGuide.leftX(y1)*w+m, y1*h); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cameraGuide.rightX(y1)*w, y1*h); ctx.lineTo(cameraGuide.rightX(y2)*w, y2*h); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cameraGuide.rightX(y1)*w, y1*h); ctx.lineTo(cameraGuide.rightX(y1)*w-m, y1*h); ctx.stroke()
            }
        }
    }

    // ── Distance badge — top-left ────────────────────────────────────
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 10
        width: distBadgeText.width + 24
        height: distBadgeText.height + 16
        color: "#CC000000"
        radius: 8
        border.width: 2
        border.color: noSignal ? "#888888" : zoneColor

        Text {
            id: distBadgeText
            anchors.centerIn: parent
            text: noSignal ? "No Signal" : currentDistance + " cm"
            font.pixelSize: 26
            font.bold: true
            color: noSignal ? "#888888" : zoneColor
        }
    }

    // ── REAR CAM indicator — top-right ───────────────────────────────
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        width: camRow.width + 16
        height: 26
        color: "#80000000"
        radius: 5

        Row {
            id: camRow
            anchors.centerIn: parent
            spacing: 6

            Rectangle {
                width: 10; height: 10; radius: 5
                color: videoReceiver.receiving ? "#FF0000" : "#888888"
                anchors.verticalCenter: parent.verticalCenter
                SequentialAnimation on opacity {
                    running: videoReceiver.receiving
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 500 }
                    NumberAnimation { to: 1.0; duration: 500 }
                }
            }
            Text {
                text: "REAR CAM"
                font.pixelSize: 12; font.bold: true
                color: "#FFFFFF"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ── vsomeip connection dot — bottom-right ────────────────────────
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 10
        width: 12; height: 12; radius: 6
        color: vehicleControlClient.serviceAvailable ? "#00ff00" : "#ff0000"
    }
}
