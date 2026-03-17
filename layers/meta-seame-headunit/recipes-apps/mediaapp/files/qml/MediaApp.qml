import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Controls 2.12
import QtGraphicalEffects 1.0

// MediaApp main window
// Content area: size controlled by Compositor sendConfigure (470x524 portrait)
Window {
    id: window
    // Size controlled by Compositor sendConfigure (470x524 portrait)
    visible: true
    title: "MediaApp"
    flags: Qt.Window | Qt.FramelessWindowHint

    Rectangle {
        id: root
        anchors.fill: parent

        // Background gradient matching AmbientApp style
        Rectangle {
            id: backgroundGradient
            anchors.fill: parent

            property color displayColor: ambientTheme ? ambientTheme.ambientColor : "#3498db"
            property real brightnessValue: ambientTheme ? ambientTheme.brightness : 0.8

            property color brightColor: Qt.rgba(
                displayColor.r * brightnessValue,
                displayColor.g * brightnessValue,
                displayColor.b * brightnessValue,
                1.0
            )

            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(backgroundGradient.brightColor, 1.3) }
                GradientStop { position: 0.5; color: backgroundGradient.brightColor }
                GradientStop { position: 1.0; color: Qt.darker(backgroundGradient.brightColor, 1.5) }
            }

            Behavior on brightColor {
                ColorAnimation { duration: 300 }
            }
        }

        property bool isPlaying: mediaManager.isPlaying
        property string currentSong: mediaManager.currentFile
        property int currentIndex: mediaManager.currentIndex
        property var mediaFiles: mediaManager.mediaFiles

        function getFileName(filePath) {
            if (!filePath) return "No song selected"
            var parts = filePath.split('/')
            return parts[parts.length - 1]
        }

        Component.onCompleted: {
            console.log("MediaApp: Starting auto scan...")
            autoScanTimer.start()
        }

        Timer {
            id: autoScanTimer
            interval: 1000
            onTriggered: {
                var files = mediaManager.scanAllUsbMounts()
                console.log("Auto scan completed. Found", files.length, "media files")
            }
        }

        // USB device selector row (top)
        Row {
            id: usbControls
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            ComboBox {
                id: mountBox
                width: 250
                height: 40
                model: mediaManager.usbMounts
                displayText: currentText || "No USB Device"
                background: Rectangle { color: "#3498db"; radius: 5 }
                contentItem: Text {
                    text: mountBox.displayText
                    color: "white"
                    leftPadding: 10
                    rightPadding: 10
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 13
                }
            }

            Rectangle {
                width: 40
                height: 40
                color: "transparent"

                Image {
                    id: refreshIcon
                    anchors.centerIn: parent
                    source: "qrc:/images/refresh.svg"
                    sourceSize.width: 40
                    sourceSize.height: 40
                    fillMode: Image.PreserveAspectFit
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        mediaManager.refreshUsbMounts()
                        refreshScanTimer.start()
                    }
                    onPressed: parent.scale = 0.9
                    onReleased: parent.scale = 1.0
                }

                Behavior on scale { NumberAnimation { duration: 100 } }

                Timer {
                    id: refreshScanTimer
                    interval: 500
                    onTriggered: {
                        var files = mediaManager.scanAllUsbMounts()
                        console.log("Refresh scan completed. Found", files.length, "media files")
                    }
                }
            }
        }

        // Main content: media list (left) + player controls (right)
        Row {
            anchors.top: usbControls.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            spacing: 10

            // Media file list
            Rectangle {
                width: parent.width * 0.57
                height: parent.height
                color: "#2c3e50"
                radius: 8

                Column {
                    anchors.fill: parent
                    anchors.margins: 8

                    Text {
                        text: "USB Media Files"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#ecf0f1"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Rectangle {
                        width: parent.width
                        height: 2
                        color: "#3498db"
                    }

                    ListView {
                        width: parent.width
                        height: parent.height - 30
                        model: root.mediaFiles
                        clip: true

                        delegate: Rectangle {
                            width: parent.width
                            height: 44
                            color: root.currentIndex === index ? "#3498db" : "transparent"
                            radius: 4

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.getFileName(modelData)
                                color: "#ecf0f1"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                width: parent.width - 16
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    mediaManager.playFile(index)
                                    console.log("Playing: " + modelData)
                                }
                            }
                        }
                    }
                }
            }

            // Player controls
            Rectangle {
                width: parent.width * 0.40
                height: parent.height
                color: "#2c3e50"
                radius: 8

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 14

                    Text {
                        text: "Now Playing"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#ecf0f1"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Rectangle {
                        width: parent.width
                        height: 50
                        color: "#34495e"
                        radius: 5
                        border.color: "#3498db"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.getFileName(root.currentSong)
                            color: "#ecf0f1"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width - 12
                        }
                    }

                    // Playback buttons
                    Row {
                        spacing: 10
                        anchors.horizontalCenter: parent.horizontalCenter

                        Rectangle {
                            width: 40; height: 40
                            color: "transparent"
                            Image {
                                id: backwardIcon
                                anchors.centerIn: parent
                                source: "qrc:/images/backward.svg"
                                sourceSize.width: 40; sourceSize.height: 40
                                fillMode: Image.PreserveAspectFit
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { mediaManager.previous(); console.log("Previous track") }
                                onPressed: parent.scale = 0.9
                                onReleased: parent.scale = 1.0
                            }
                            Behavior on scale { NumberAnimation { duration: 100 } }
                        }

                        Rectangle {
                            width: 50; height: 50
                            color: "transparent"
                            Image {
                                id: playPauseIcon
                                anchors.centerIn: parent
                                source: root.isPlaying ? "qrc:/images/pause.svg" : "qrc:/images/start.svg"
                                sourceSize.width: 50; sourceSize.height: 50
                                fillMode: Image.PreserveAspectFit
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (root.isPlaying) mediaManager.pause()
                                    else mediaManager.play()
                                }
                                onPressed: parent.scale = 0.9
                                onReleased: parent.scale = 1.0
                            }
                            Behavior on scale { NumberAnimation { duration: 100 } }
                        }

                        Rectangle {
                            width: 40; height: 40
                            color: "transparent"
                            Image {
                                id: forwardIcon
                                anchors.centerIn: parent
                                source: "qrc:/images/forward.svg"
                                sourceSize.width: 40; sourceSize.height: 40
                                fillMode: Image.PreserveAspectFit
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { mediaManager.next(); console.log("Next track") }
                                onPressed: parent.scale = 0.9
                                onReleased: parent.scale = 1.0
                            }
                            Behavior on scale { NumberAnimation { duration: 100 } }
                        }
                    }

                    // Volume control
                    Column {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "Volume: " + Math.round(mediaManager.volume * 100) + "%"
                            font.pixelSize: 13
                            color: "#ecf0f1"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Slider {
                            width: parent.width
                            from: 0
                            to: 100
                            value: mediaManager.volume * 100
                            stepSize: 1

                            onValueChanged: {
                                mediaManager.volume = value / 100.0
                            }

                            background: Rectangle {
                                x: parent.leftPadding
                                y: parent.topPadding + parent.availableHeight / 2 - height / 2
                                implicitWidth: 150
                                implicitHeight: 4
                                width: parent.availableWidth
                                height: implicitHeight
                                radius: 2
                                color: "#7f8c8d"
                            }

                            handle: Rectangle {
                                x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                                y: parent.topPadding + parent.availableHeight / 2 - height / 2
                                implicitWidth: 18
                                implicitHeight: 18
                                radius: 9
                                color: "#3498db"
                            }
                        }
                    }
                }
            }
        }

    } // Rectangle (root)
} // Window
