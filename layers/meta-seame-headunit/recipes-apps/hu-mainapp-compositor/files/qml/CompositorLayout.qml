import QtQuick 2.12
import QtQuick.Controls 2.12
import QtGraphicalEffects 1.0

/*
 * Compositor Layout - Portrait (vertical) Unified IC + HU Layout
 *
 * Display orientation: PORTRAIT 600 x 1024
 *
 *  ┌───────────────────────────────────┐  ← 600px
 *  │          IC Area  (340px tall)    │
 *  │  GearState(200px) │ Speedom(200px) │ Battery(200px) │
 *  ├───────────────────────────────────┤
 *  │          HU Area  (684px tall)    │
 *  │  GearApp(130px) │  Main content   │
 *  │                 │  NavBar(80px)   │
 *  └───────────────────────────────────┘
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
    // TOP AREA — IC (340px tall, full width)
    // ═══════════════════════════════════════════════════════
    Rectangle {
        id: icArea
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 340
        color: "#0a0a0a"

        Row {
            anchors.fill: parent
            spacing: 0

            // GearState (1/3)
            Item {
                id: gearStateContainer
                objectName: "gearStateContainer"
                width: parent.width / 3
                height: parent.height
            }

            // Divider
            Rectangle { width: 1; height: parent.height; color: "#222222" }

            // Speedometer (1/3)
            Item {
                id: speedometerContainer
                objectName: "speedometerContainer"
                width: parent.width / 3
                height: parent.height
            }

            // Divider
            Rectangle { width: 1; height: parent.height; color: "#222222" }

            // BatteryMeter (1/3)
            Item {
                id: batteryMeterContainer
                objectName: "batteryMeterContainer"
                width: parent.width / 3
                height: parent.height
            }
        }
    }

    // Horizontal divider between IC and HU
    Rectangle {
        id: hDivider
        anchors.top: icArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: "#333333"
    }

    // ═══════════════════════════════════════════════════════
    // BOTTOM AREA — HU (remaining height)
    // ═══════════════════════════════════════════════════════

    // GearApp Left Panel (130px wide)
    Rectangle {
        id: huGearPanel
        anchors.top: hDivider.bottom
        anchors.left: parent.left
        anchors.bottom: huNavigationBar.top
        width: 130
        color: "#1a1a1a"

        Item {
            id: gearAppContainer
            objectName: "gearAppContainer"
            anchors.fill: parent
        }
    }

    // Main Content Area
    Item {
        id: mainContentArea
        objectName: "mainContentArea"
        anchors.top: hDivider.bottom
        anchors.left: huGearPanel.right
        anchors.right: parent.right
        anchors.bottom: huNavigationBar.top
        anchors.margins: 8

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
    // Bottom Navigation Bar
    // ═══════════════════════════════════════════════════════
    Rectangle {
        id: huNavigationBar
        anchors.bottom: parent.bottom
        anchors.left: huGearPanel.right
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
    // Status Indicator (GearApp panel bottom)
    // ═══════════════════════════════════════════════════════
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: huGearPanel.width
        height: 30
        color: "#2d2d2d"
        radius: 5

        Text {
            id: surfaceCountText
            anchors.centerIn: parent
            text: "0 apps"
            color: "#888888"
            font.pixelSize: 11
            font.bold: true
        }
    }
}
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
