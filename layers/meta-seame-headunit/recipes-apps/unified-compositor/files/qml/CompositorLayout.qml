import QtQuick 2.12
import QtQuick.Controls 2.12
import QtGraphicalEffects 1.0

/*
 * Compositor Layout — Unified IC + HU
 *
 * ── TARGET (Elecrow 13.3" portrait, MiniHDMI) ──────────────────
 *  Display orientation : PORTRAIT  600 × 1024
 *
 *  ┌──────────────────────────┐  ← 600 px wide
 *  │     IC Area  (340 px)    │
 *  │ GearState│Speedom│Battery│  each 200 px wide
 *  ├──────────────────────────┤
 *  │     HU Area  (684 px)    │
 *  │ GearApp(130)│ Main(470)  │
 *  │             │ NavBar(80) │
 *  └──────────────────────────┘
 *
 * ── TEST (DP display, landscape) ───────────────────────────────
 *  Display orientation : LANDSCAPE  1024 × 600
 *
 *  ┌────────────────────────────────────────────────┐  ← 1024 px
 *  │ IC(280px) │ GearApp(130px) │ Main Area(614px)  │
 *  │ GearState │                │  Home/Media/Amb   │
 *  │ Speedom   │                │  NavBar(80px)     │
 *  │ Battery   │                │                   │
 *  └────────────────────────────────────────────────┘
 */

Item {
    id: root

    // ── HU containers ──
    property alias gearAppContainer:        gearAppContainer
    property alias homeScreenAppContainer:  homeScreenAppContainer
    property alias mediaAppContainer:       mediaAppContainer
    property alias ambientAppContainer:     ambientAppContainer
    property alias pdcAppContainer:         pdcAppContainer

    // ── IC containers ──
    property alias gearStateContainer:      gearStateContainer
    property alias speedometerContainer:    speedometerContainer
    property alias batteryMeterContainer:   batteryMeterContainer

    property alias surfaceCount: surfaceCountText.text
    property int currentPage: 0

    // PDC overlay visibility — set to true when gear = "R"
    property bool isReverseGear: false

    // ═══════════════════════════════════════════════════════
    // IC AREA
    // ── TARGET (portrait): top 340px, full width ──────────
    //   anchors.top: parent.top; height: 340
    //   Row { gearState | speedometer | battery }
    //
    // ── TEST (landscape): left panel 280px, full height ───
    //   anchors.left: parent.left; width: 280
    //   Column { gearState / speedometer / battery }
    // ═══════════════════════════════════════════════════════

    /* ---- TEST (landscape) — uncomment when testing with DP
    Rectangle {
        id: icArea
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 280
        color: "#0a0a0a"

        Column {
            anchors.fill: parent
            spacing: 0

            Item {
                id: gearStateContainer
                objectName: "gearStateContainer"
                width: parent.width
                height: 200
            }
            Rectangle { width: parent.width; height: 1; color: "#222222" }
            Item {
                id: speedometerContainer
                objectName: "speedometerContainer"
                width: parent.width
                height: 200
            }
            Rectangle { width: parent.width; height: 1; color: "#222222" }
            Item {
                id: batteryMeterContainer
                objectName: "batteryMeterContainer"
                width: parent.width
                height: 198
            }
        }
    }
    ---- end TEST landscape IC area ---- */

    // ---- TARGET (portrait) ----
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
            Item {
                id: gearStateContainer
                objectName: "gearStateContainer"
                width: parent.width / 3
                height: parent.height
            }
            Rectangle { width: 1; height: parent.height; color: "#222222" }
            Item {
                id: speedometerContainer
                objectName: "speedometerContainer"
                width: parent.width / 3
                height: parent.height
            }
            Rectangle { width: 1; height: parent.height; color: "#222222" }
            Item {
                id: batteryMeterContainer
                objectName: "batteryMeterContainer"
                width: parent.width / 3
                height: parent.height
            }
        }
    }

    // Divider between IC and HU
    /* ---- TEST (landscape): vertical divider — uncomment when testing with DP
    Rectangle {
        id: divider
        anchors.left: icArea.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: "#333333"
    }
    ---- end TEST ---- */

    // ---- TARGET (portrait): horizontal divider ----
    Rectangle {
        id: divider
        anchors.top: icArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: "#333333"
    }


    // ═══════════════════════════════════════════════════════
    // HU AREA — GearApp panel
    // ── TEST (landscape): anchors.left: divider.right ─────
    // ── TARGET (portrait): anchors.top: divider.bottom ────
    // ═══════════════════════════════════════════════════════

    Rectangle {
        id: huGearPanel
        // ---- TARGET (portrait) ----
        anchors.top: divider.bottom
        anchors.left: parent.left
        anchors.bottom: huNavigationBar.top
        /* ---- TEST (landscape) — uncomment when testing with DP
        anchors.left: divider.right
        anchors.top: parent.top
        anchors.bottom: huNavigationBar.top
        ---- end TEST ---- */
        width: 130
        color: "#1a1a1a"

        Item {
            id: gearAppContainer
            objectName: "gearAppContainer"
            anchors.fill: parent
        }
    }

    // ═══════════════════════════════════════════════════════
    // HU AREA — Main content (Home / Media / Ambient pages)
    // ═══════════════════════════════════════════════════════
    Item {
        id: mainContentArea
        objectName: "mainContentArea"
        z: root.isReverseGear ? 0 : 1  // Behind PDC overlay when reversing
        anchors.left: huGearPanel.right
        anchors.right: parent.right
        // ---- TARGET (portrait) ----
        anchors.top: divider.bottom
        /* ---- TEST (landscape) — uncomment when testing with DP
        anchors.top: parent.top
        ---- end TEST ---- */
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
    // PDC OVERLAY — shown when gear = "R" (Reverse)
    // Covers the main content area; PDCApp window is embedded here
    // ═══════════════════════════════════════════════════════
    Rectangle {
        id: pdcOverlay
        anchors.left: huGearPanel.right
        anchors.right: parent.right
        // ---- TARGET (portrait) ----
        anchors.top: divider.bottom
        anchors.bottom: huNavigationBar.top
        anchors.margins: 8
        color: "transparent"
        z: root.isReverseGear ? 1 : 0
        visible: opacity > 0
        opacity: root.isReverseGear ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: 300
                easing.type: Easing.InOutQuad
            }
        }

        Item {
            id: pdcAppContainer
            objectName: "pdcAppContainer"
            anchors.fill: parent
        }
    }

    // ═══════════════════════════════════════════════════════
    // Bottom Navigation Bar
    // ═══════════════════════════════════════════════════════
    Rectangle {
        id: huNavigationBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
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
    // Status indicator
    // ═══════════════════════════════════════════════════════
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: huNavigationBar.top
        anchors.bottomMargin: 5
        width: icArea.width
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
