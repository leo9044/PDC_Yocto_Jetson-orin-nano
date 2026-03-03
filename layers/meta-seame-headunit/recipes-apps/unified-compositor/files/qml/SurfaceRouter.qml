import QtQuick 2.12

/*
 * Surface Router — routes client windows to layout containers
 *
 * ── TEST (DP landscape 1024×600) ────────────────────────────────
 *   IC apps  : 280 × 600  (column: GearState 200 / Speedom 200 / Battery 198)
 *   GearApp  : 130 × 520  (HU left panel, 520 = 600 - 80 navBar)
 *   HU main  : 614 × 520  (remaining width - margins)
 *
 * ── TARGET (Elecrow portrait 600×1024) ──────────────────────────
 *   IC apps  : 200 × 340  (row: each 1/3 of 600px wide)
 *   GearApp  : 130 × 604  (HU left panel, 604 = 1024 - 340ic - 80navBar)
 *   HU main  : 470 × 524  (remaining width, 524 = 604 - 80navBar)
 */

QtObject {
    id: router

    // ── HU containers ──
    property var gearAppContainer:       null
    property var homeScreenAppContainer: null
    property var mediaAppContainer:      null
    property var ambientAppContainer:    null

    // ── IC containers ──
    property var gearStateContainer:     null
    property var speedometerContainer:   null
    property var batteryMeterContainer:  null

    // ── Returns suggested window size ───────────────────────────
    function getSuggestedSize(identifier) {
        var id = identifier.toLowerCase()

        // IC apps — TEST: 280×600 / TARGET: 200×340
        if (id.includes("gearstate") || id.includes("gear state"))
            // return Qt.size(280, 600)   // TEST landscape
            return Qt.size(200, 340)    // TARGET portrait
        if (id.includes("speedometer"))
            // return Qt.size(280, 600)   // TEST landscape
            return Qt.size(200, 340)    // TARGET portrait
        if (id.includes("battery") || id.includes("batterymeter"))
            // return Qt.size(280, 600)   // TEST landscape
            return Qt.size(200, 340)    // TARGET portrait

        // HU GearApp — TEST: 130×520 / TARGET: 130×604
        if (identifier === "GearApp" || (id.includes("gear") && !id.includes("state")))
            // return Qt.size(130, 520)   // TEST landscape
            return Qt.size(130, 604)    // TARGET portrait

        // HU main area — TEST: 614×520 / TARGET: 470×524
        // return Qt.size(614, 520)       // TEST landscape
        return Qt.size(470, 524)        // TARGET portrait
    }

    // ── Returns target container without routing ─────────────────
    function getTargetContainer(identifier) {
        var id = identifier.toLowerCase()

        if (id.includes("gearstate") || id.includes("gear state"))
            return gearStateContainer
        if (id.includes("speedometer"))
            return speedometerContainer
        if (id.includes("battery") || id.includes("batterymeter"))
            return batteryMeterContainer

        if (identifier === "GearApp" || (id.includes("gear") && !id.includes("state")))
            return gearAppContainer
        if (identifier === "HomeScreenApp" || id.includes("homescreen") || id.includes("home screen"))
            return homeScreenAppContainer
        if (identifier === "MediaApp" || id.includes("media"))
            return mediaAppContainer
        if (identifier === "AmbientApp" || id.includes("ambient"))
            return ambientAppContainer

        return homeScreenAppContainer
    }

    // ── Assigns chrome to container, evicting existing occupant ──
    function assignToContainer(chrome, container, containerName) {
        for (var i = container.children.length - 1; i >= 0; i--) {
            var child = container.children[i]
            if (child !== chrome) {
                console.log("   ⚠️  Evicting existing surface from", containerName)
                child.visible = false
                child.parent = null
            }
        }
        chrome.parent = container
        chrome.anchors.fill = chrome.parent
        chrome.visible = true
        console.log("   →", containerName, "✅")
    }

    // ── Routes surface to the appropriate container ───────────────
    function routeSurface(chrome, identifier) {
        if (!chrome) {
            console.error("❌ Cannot route: chrome is null")
            return
        }

        var id = identifier.toLowerCase()
        console.log("🔀 Routing:", identifier)

        // IC apps
        if (id.includes("gearstate") || id.includes("gear state")) {
            if (gearStateContainer) assignToContainer(chrome, gearStateContainer, "IC GearState")
            return
        }
        if (id.includes("speedometer")) {
            if (speedometerContainer) assignToContainer(chrome, speedometerContainer, "IC Speedometer")
            return
        }
        if (id.includes("battery") || id.includes("batterymeter")) {
            if (batteryMeterContainer) assignToContainer(chrome, batteryMeterContainer, "IC BatteryMeter")
            return
        }

        // HU apps
        if (identifier === "GearApp" || (id.includes("gear") && !id.includes("state"))) {
            if (gearAppContainer) assignToContainer(chrome, gearAppContainer, "HU GearPanel")
            return
        }
        if (identifier === "HomeScreenApp" || id.includes("homescreen") || id.includes("home screen")) {
            if (homeScreenAppContainer) assignToContainer(chrome, homeScreenAppContainer, "HU HomePage")
            return
        }
        if (identifier === "MediaApp" || id.includes("media")) {
            if (mediaAppContainer) assignToContainer(chrome, mediaAppContainer, "HU MediaPage")
            return
        }
        if (identifier === "AmbientApp" || id.includes("ambient")) {
            if (ambientAppContainer) assignToContainer(chrome, ambientAppContainer, "HU AmbientPage")
            return
        }

        console.error("⚠️  Unknown identifier, hiding surface:", identifier)
        chrome.visible = false
    }
}
