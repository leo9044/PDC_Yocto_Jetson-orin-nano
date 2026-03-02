import QtQuick 2.12
import QtQuick.Controls 2.12
import QtGraphicalEffects 1.0

/*
 * Compositor Layout - Unified IC + HU Layout
 *
 * Single display split:
 *   Left  280px : IC area (GearState 93px | Speedometer 94px | BatteryMeter 93px)
 *   Right 744px : HU area (GearApp 130px panel + main content 614px)
 *
 * Total: 1024 x 600
 */

Item {
    id: root

    // ── HU containers ──
    property alias gearAppContainer: gearAppContainer
    property alias homeScreenAppContainer: homeScreenAppContainer
    property alias mediaAppContainer: mediaAppContainer
    property alias ambientAppContainer: ambientAppContainer

    // ── IC containers ──
    property alias gearStateContainer: gearStateContainer
    property alias speedometerContainer: speedometerContainer
    property alias batteryMeterContainer: batteryMeterContainer

    property alias surfaceCount: surfaceCountText.text
    property int currentPage: 0

    // ═══════════════════════════════════════════════════════
    // LEFT PANEL — IC Area (280px wide)
    // ═══════════════════════════════════════════════════════
    Rectangle {
        id: icPanel
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 280
        color: "#0a0a0a"

        Column {
            anchors.fill: parent
            spacing: 0

            // GearState (93px)
            Item {
                id: gearStateContainer
                objectName: "gearStateContainer"
                width: parent.width
                height: 200
            }

            // Divider
            Rectangle { width: parent.width; height: 1; color: "#222222" }

            // Speedometer (middle, fills remaining)
            Item {
                id: speedometerContainer
                objectName: "speedometerContainer"
                width: parent.width
                height: 200
            }

            // Divider
            Rectangle { width: parent.width; height: 1; color: "#222222" }

            // BatteryMeter (200px)
            Item {
                id: batteryMeterContainer
                objectName: "batteryMeterContainer"
                width: parent.width
                height: 199
            }
        }
    }

    // Vertical divider between IC and HU
    Rectangle {
        id: divider
        anchors.left: icPanel.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: "#333333"
    }

    // ═══════════════════════════════════════════════════════
    // RIGHT AREA — HU Area (744px wide)
    // ═══════════════════════════════════════════════════════

    // GearApp Left Panel (130px)
    Rectangle {
        id: huGearPanel
        anchors.left: divider.right
        anchors.top: parent.top
        anchors.bottom: huNavigationBar.top
        width: 130
        color: "#1a1a1a"

        Item {
            id: gearAppContainer
            objectName: "gearAppContainer"
            anchors.fill: parent
        }
    }

    // Main Content Area (614px)
    Item {
        id: mainContentArea
        objectName: "mainContentArea"
        anchors.left: huGearPanel.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: huNavigationBar.top
        anchors.margins: 10

        Rectangle {
            id: homePage
            anchors.fill: parent
            visible: root.currentPage === 0
            color: "transparent"
            Item {
                id: homeScreenAppContainer
                objectName: "homeScreenAppContainer"
                anchors.fill: parent
            }
        }

        Rectangle {
            id: mediaPage
            anchors.fill: parent
            visible: root.currentPage === 1
            color: "transparent"
            Item {
                id: mediaAppContainer
                objectName: "mediaAppContainer"
                anchors.fill: parent
            }
        }

        Rectangle {
            id: ambientPage
            anchors.fill: parent
            visible: root.currentPage === 2
            color: "transparent"
            Item {
                id: ambientAppContainer
                objectName: "ambientAppContainer"
                anchors.fill: parent
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // Bottom Navigation Bar (HU side only)
    // ═══════════════════════════════════════════════════════
    Rectangle {
        id: huNavigationBar
        anchors.bottom: parent.bottom
        anchors.left: divider.right
        anchors.right: parent.right
        height: 80
        color: "#2d2d2d"

        Row {
            anchors.centerIn: parent
            spacing: 20

            TabButton {
                width: 80; height: 60
                checked: root.currentPage === 0
                onClicked: root.currentPage = 0
                background: Rectangle {
                    color: parent.checked ? "#27ae60" : "#444444"
                    radius: 8
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                contentItem: Image {
                    anchors.centerIn: parent
                    width: 50; height: 50
                    source: "qrc:/asset/car_white.svg"
                    fillMode: Image.PreserveAspectFit
                }
            }

            TabButton {
                width: 80; height: 60
                checked: root.currentPage === 1
                onClicked: root.currentPage = 1
                background: Rectangle {
                    color: parent.checked ? "#2196F3" : "#444444"
                    radius: 8
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                contentItem: Image {
                    anchors.centerIn: parent
                    width: 50; height: 50
                    source: "qrc:/asset/mp3_white.svg"
                    fillMode: Image.PreserveAspectFit
                }
            }

            TabButton {
                width: 80; height: 60
                checked: root.currentPage === 2
                onClicked: root.currentPage = 2
                background: Rectangle {
                    color: parent.checked ? "#FF9800" : "#444444"
                    radius: 8
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                contentItem: Image {
                    anchors.centerIn: parent
                    width: 50; height: 50
                    source: "qrc:/asset/ambient_light.svg"
                    fillMode: Image.PreserveAspectFit
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // Status Indicator
    // ═══════════════════════════════════════════════════════
    Rectangle {
        anchors.left: divider.right
        anchors.bottom: huNavigationBar.top
        anchors.bottomMargin: 5
        width: huGearPanel.width
        height: 30
        color: "#2d2d2d"
        radius: 5

        Text {
            id: surfaceCountText
            anchors.centerIn: parent
            text: "0 apps"
            color: "#888888"
            font.pixelSize: 12
            font.bold: true
        }
    }
}

    // ═══════════════════════════════════════════════════════
    // Left Side Panel - Permanent GearApp Display
    // ═══════════════════════════════════════════════════════
    Rectangle {
        id: leftGearPanel
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: navigationBar.top
        width: 130
        color: "#1a1a1a"

        // Container for GearApp window
        Item {
            id: gearAppContainer
            objectName: "gearAppContainer"
            anchors.fill: parent
        }
    }

    // ═══════════════════════════════════════════════════════
    // Main Content Area - Switchable Pages
    // ═══════════════════════════════════════════════════════
    Item {
        id: mainContentArea
        objectName: "mainContentArea"
        anchors.left: leftGearPanel.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: navigationBar.top
        anchors.margins: 10

        // ───────────────────────────────────────────────────
        // Page 0: HOME (HomeScreenApp window container)
        // ───────────────────────────────────────────────────
        Rectangle {
            id: homePage
            anchors.fill: parent
            visible: root.currentPage === 0
            color: "transparent"

            // Container for HomeScreenApp window
            Item {
                id: homeScreenAppContainer
                objectName: "homeScreenAppContainer"
                anchors.fill: parent
            }
        }

        // ───────────────────────────────────────────────────
        // Page 1: MEDIA (MediaApp window container)
        // ───────────────────────────────────────────────────
        Rectangle {
            id: mediaPage
            anchors.fill: parent
            visible: root.currentPage === 1
            color: "transparent"

            // Container for MediaApp window
            Item {
                id: mediaAppContainer
                objectName: "mediaAppContainer"
                anchors.fill: parent
            }
        }

        // ───────────────────────────────────────────────────
        // Page 2: AMBIENT (AmbientApp window container)
        // ───────────────────────────────────────────────────
        Rectangle {
            id: ambientPage
            anchors.fill: parent
            visible: root.currentPage === 2
            color: "transparent"

            // Container for AmbientApp window
            Item {
                id: ambientAppContainer
                objectName: "ambientAppContainer"
                anchors.fill: parent
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // Bottom Navigation Bar
    // ═══════════════════════════════════════════════════════
    Rectangle {
        id: navigationBar
        anchors.bottom: parent.bottom
        anchors.left: leftGearPanel.right
        anchors.right: parent.right
        height: 80
        color: "#2d2d2d"

        Row {
            anchors.centerIn: parent
            spacing: 20

            // Home Button (car icon)
            TabButton {
                width: 80
                height: 60
                checked: root.currentPage === 0
                onClicked: root.currentPage = 0

                background: Rectangle {
                    color: parent.checked ? "#27ae60" : "#444444"
                    radius: 8

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                }

                contentItem: Image {
                    anchors.centerIn: parent
                    width: 50
                    height: 50
                    source: "qrc:/asset/car_white.svg"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }

            // Media Button (mp3 icon)
            TabButton {
                width: 80
                height: 60
                checked: root.currentPage === 1
                onClicked: root.currentPage = 1

                background: Rectangle {
                    color: parent.checked ? "#2196F3" : "#444444"
                    radius: 8

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                }

                contentItem: Image {
                    anchors.centerIn: parent
                    width: 50
                    height: 50
                    source: "qrc:/asset/mp3_white.svg"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }

            // Ambient Button (ambient_light icon)
            TabButton {
                width: 80
                height: 60
                checked: root.currentPage === 2
                onClicked: root.currentPage = 2

                background: Rectangle {
                    color: parent.checked ? "#FF9800" : "#444444"
                    radius: 8

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                }

                contentItem: Image {
                    anchors.centerIn: parent
                    width: 50
                    height: 50
                    source: "qrc:/asset/ambient_light.svg"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // Status Indicator (Bottom-left corner)
    // ═══════════════════════════════════════════════════════
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: navigationBar.top
        anchors.bottomMargin: 5
        width: leftGearPanel.width
        height: 30
        color: "#2d2d2d"
        radius: 5

        Text {
            id: surfaceCountText
            anchors.centerIn: parent
            text: "0 apps"
            color: "#888888"
            font.pixelSize: 12
            font.bold: true
        }
    }
}
