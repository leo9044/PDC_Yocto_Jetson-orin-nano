import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.3
import QtGraphicalEffects 1.0

// AmbientApp main window
// Content area: size controlled by Compositor sendConfigure (470x524 portrait)
Window {
    id: window
    // Size controlled by Compositor sendConfigure (470x524 portrait)
    visible: true
    title: "AmbientApp"
    flags: Qt.Window | Qt.FramelessWindowHint

    Rectangle {
        id: root
        anchors.fill: parent

        property color wheelColor: colorWheel.color
        property color backendColor: ambientManager.ambientColor
        property color displayColor: backendColor !== "" ? backendColor : wheelColor

        // Background gradient
        Rectangle {
            id: backgroundGradient
            anchors.fill: parent

            property real brightnessValue: ambientManager.brightness
            property color brightColor: Qt.rgba(
                root.displayColor.r * brightnessValue,
                root.displayColor.g * brightnessValue,
                root.displayColor.b * brightnessValue,
                1.0
            )

            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(backgroundGradient.brightColor, 1.3) }
                GradientStop { position: 0.5; color: backgroundGradient.brightColor }
                GradientStop { position: 1.0; color: Qt.darker(backgroundGradient.brightColor, 1.5) }
            }

            Behavior on brightnessValue {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }
        }

        Behavior on displayColor {
            ColorAnimation { duration: 300; easing.type: Easing.OutQuad }
        }

        onWheelColorChanged: {
            if (root.visible) {
                ambientManager.ambientColor = wheelColor.toString()
            }
        }

        onBackendColorChanged: {
            if (backendColor !== "") {
                console.log("🎨 [Gear → UI] Backend color changed to:", backendColor.toString())
            }
        }

        Component.onCompleted: {
            ambientManager.ambientColor = wheelColor.toString()
        }

        // Color wheel (centered, slightly above middle)
        Rectangle {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -30
            width: 270
            height: 270
            color: "transparent"

            Control {
                id: colorWheel
                anchors.centerIn: parent
                property real ringWidth: 25
                property real hsvValue: 1.0
                property real hsvSaturation: 1.0

                readonly property color color: Qt.hsva(mousearea.angle, 1.0, 1.0, 1.0)

                contentItem: Item {
                    implicitWidth: 270
                    implicitHeight: width

                    Canvas {
                        id: colorWheelCanvas
                        width: parent.width
                        height: parent.height

                        onPaint: {
                            var ctx = getContext("2d")
                            var centerX = width / 2
                            var centerY = height / 2
                            var outerRadius = width / 2
                            var innerRadius = outerRadius - colorWheel.ringWidth

                            var segments = 360
                            for (var i = 0; i < segments; i++) {
                                var startAngle = (i - 90) * Math.PI / 180
                                var endAngle = (i + 1 - 90) * Math.PI / 180
                                var hue = i / segments

                                ctx.beginPath()
                                ctx.arc(centerX, centerY, outerRadius, startAngle, endAngle, false)
                                ctx.arc(centerX, centerY, innerRadius, endAngle, startAngle, true)
                                ctx.closePath()

                                ctx.fillStyle = Qt.hsva(hue, 1.0, 1.0, 1.0)
                                ctx.fill()
                            }
                        }

                        Component.onCompleted: requestPaint()
                    }

                    Rectangle {
                        id: indicator
                        x: (parent.width - width) / 2
                        y: colorWheel.ringWidth * 0.1

                        width: colorWheel.ringWidth * 0.8
                        height: width
                        radius: width / 2

                        color: 'white'
                        border {
                            width: mousearea.containsPress ? 3 : 1
                            color: Qt.lighter(colorWheel.color)
                            Behavior on width { NumberAnimation { duration: 50 } }
                        }

                        transform: Rotation {
                            angle: mousearea.angle * 360
                            origin.x: indicator.width / 2
                            origin.y: colorWheel.availableHeight / 2 - indicator.y
                        }
                    }

                    MouseArea {
                        id: mousearea
                        anchors.fill: parent
                        property real angle: Math.atan2(width / 2 - mouseX, mouseY - height / 2) / 3.14 / 2 + 0.5
                    }
                }
            }

            // Car image centered inside the wheel
            Item {
                anchors.centerIn: parent
                width: 110
                height: 75

                Image {
                    id: carImageAmbient
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    source: "qrc:/images/car.svg"
                    fillMode: Image.PreserveAspectFit
                    opacity: 0.8
                }
            }
        }

        // Brightness slider (bottom)
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 30
            width: 380
            height: 80
            radius: 12
            color: "#2c3e50"
            opacity: 0.95

            Column {
                anchors.centerIn: parent
                width: 340
                spacing: 8

                Text {
                    text: "Brightness: " + Math.round(brightnessSlider.value) + "%"
                    font.pixelSize: 14
                    font.bold: true
                    color: "#ecf0f1"
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Slider {
                    id: brightnessSlider
                    width: parent.width
                    from: 0
                    to: 100
                    value: (ambientManager.brightness - 0.5) * 200
                    stepSize: 1

                    onMoved: {
                        ambientManager.brightness = 0.5 + (value / 200.0)
                    }

                    background: Rectangle {
                        x: parent.leftPadding
                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                        implicitWidth: 200
                        implicitHeight: 8
                        width: parent.availableWidth
                        height: implicitHeight
                        radius: 4
                        color: "#34495e"

                        Rectangle {
                            width: parent.width * (brightnessSlider.value / 100.0)
                            height: parent.height
                            radius: parent.radius
                            color: "#3498db"
                        }
                    }

                    handle: Rectangle {
                        x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: 11
                        color: "#3498db"
                        border.color: "#2980b9"
                        border.width: 2
                    }
                }
            }
        }

    } // Rectangle root
} // Window
