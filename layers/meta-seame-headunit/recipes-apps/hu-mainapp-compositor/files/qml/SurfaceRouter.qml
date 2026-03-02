import QtQuick 2.12

/*
 * Surface Router - Routes client app windows to containers
 * Handles both IC apps (GearState, Speedometer, BatteryMeter)
 * and HU apps (GearApp, HomeScreen, MediaApp, AmbientApp)
 */

QtObject {
    id: router

    // ── HU containers ──
    property var gearAppContainer: null
    property var homeScreenAppContainer: null
    property var mediaAppContainer: null
    property var ambientAppContainer: null

    // ── IC containers ──
    property var gearStateContainer: null
    property var speedometerContainer: null
    property var batteryMeterContainer: null

    // Returns the target container for a given identifier
    function getTargetContainer(identifier) {
        var id = identifier.toLowerCase()

        // IC apps
        if (id.includes("gearstate") || id.includes("gear state"))
            return gearStateContainer
        if (id.includes("speedometer"))
            return speedometerContainer
        if (id.includes("battery") || id.includes("batterymeter"))
            return batteryMeterContainer

        // HU apps
        if (identifier === "GearApp" || id.includes("gear"))
            return gearAppContainer
        if (identifier === "HomeScreenApp" || id.includes("homescreen") || id.includes("home screen"))
            return homeScreenAppContainer
        if (identifier === "MediaApp" || id.includes("media"))
            return mediaAppContainer
        if (identifier === "AmbientApp" || id.includes("ambient"))
            return ambientAppContainer

        return homeScreenAppContainer
    }

    // Returns suggested window size based on app
    function getSuggestedSize(identifier) {
        var id = identifier.toLowerCase()

        // IC apps: fill their 280x200 slot
        if (id.includes("gearstate") || id.includes("gear state"))
            return Qt.size(280, 200)
        if (id.includes("speedometer"))
            return Qt.size(280, 200)
        if (id.includes("battery") || id.includes("batterymeter"))
            return Qt.size(280, 200)

        // HU GearApp: narrow left panel
        if (identifier === "GearApp" || (id.includes("gear") && !id.includes("state")))
            return Qt.size(130, 520)

        // HU main area apps
        return Qt.size(614, 520)
    }

    // Assigns chrome to container, clearing duplicates
    function assignToContainer(chrome, container, containerName) {
        for (var i = container.children.length - 1; i >= 0; i--) {
            var child = container.children[i]
            if (child !== chrome) {
                console.log("   ⚠️  Removing existing surface from", containerName)
                child.visible = false
                child.parent = null
            }
        }
        chrome.parent = container
        chrome.anchors.fill = chrome.parent
        chrome.visible = true
        console.log("   → " + containerName + " ✅")
    }

    // Route surface to appropriate container
    function routeSurface(chrome, identifier) {
        if (!chrome) {
            console.error("❌ Cannot route: chrome is null")
            return
        }

        var id = identifier.toLowerCase()
        console.log("🔀 Routing surface:", identifier)

        // ── IC apps ──
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

        // ── HU apps ──
        if (identifier === "GearApp" || (id.includes("gear") && !id.includes("state"))) {
            if (gearAppContainer) assignToContainer(chrome, gearAppContainer, "HU Left Gear Panel")
            return
        }
        if (identifier === "HomeScreenApp" || id.includes("homescreen") || id.includes("home screen")) {
            if (homeScreenAppContainer) assignToContainer(chrome, homeScreenAppContainer, "HU Home Page")
            return
        }
        if (identifier === "MediaApp" || id.includes("media")) {
            if (mediaAppContainer) assignToContainer(chrome, mediaAppContainer, "HU Media Page")
            return
        }
        if (identifier === "AmbientApp" || id.includes("ambient")) {
            if (ambientAppContainer) assignToContainer(chrome, ambientAppContainer, "HU Ambient Page")
            return
        }

        console.error("⚠️  Unknown app_id - NOT ROUTING:", identifier)
        chrome.visible = false
    }
}

    // Get target container without actually routing
    function getTargetContainer(identifier) {
        var idLower = identifier.toLowerCase()
        
        if (identifier === "GearApp" || idLower.includes("gear")) {
            return gearAppContainer
        } else if (identifier === "HomeScreenApp" || idLower.includes("homescreen") || idLower.includes("home screen")) {
            return homeScreenAppContainer
        } else if (identifier === "MediaApp" || idLower.includes("media")) {
            return mediaAppContainer
        } else if (identifier === "AmbientApp" || idLower.includes("ambient")) {
            return ambientAppContainer
        } else {
            // Default: Home page
            return homeScreenAppContainer
        }
    }

    // Helper function to clear container and add new surface
    function assignToContainer(chrome, container, containerName) {
        // Clear any existing children in the container (prevent duplicates)
        for (var i = container.children.length - 1; i >= 0; i--) {
            var child = container.children[i]
            if (child !== chrome) {
                console.log("   ⚠️  Removing existing surface from", containerName)
                child.visible = false
                child.parent = null
            }
        }

        // Assign new surface
        chrome.parent = container
        chrome.anchors.fill = chrome.parent
        chrome.visible = true
        console.log("   → " + containerName + " ✅")
    }

    // Route surface to appropriate container
    function routeSurface(chrome, identifier) {
        if (!chrome) {
            console.error("❌ Cannot route: chrome is null")
            return
        }

        var idLower = identifier.toLowerCase()

        console.log("🔀 Routing surface...")
        console.log("   Identifier:", identifier)

        // Route by app_id or window title
        if (identifier === "GearApp" || idLower.includes("gear")) {
            if (gearAppContainer) {
                assignToContainer(chrome, gearAppContainer, "Left Gear Panel")
            } else {
                console.error("   ❌ gearAppContainer is null!")
            }
            return

        } else if (identifier === "HomeScreenApp" || idLower.includes("homescreen") || idLower.includes("home screen")) {
            if (homeScreenAppContainer) {
                assignToContainer(chrome, homeScreenAppContainer, "Home Page")
            } else {
                console.error("   ❌ homeScreenAppContainer is null!")
            }
            return

        } else if (identifier === "MediaApp" || idLower.includes("media")) {
            if (mediaAppContainer) {
                assignToContainer(chrome, mediaAppContainer, "Media Page")
            } else {
                console.error("   ❌ mediaAppContainer is null!")
            }
            return

        } else if (identifier === "AmbientApp" || idLower.includes("ambient")) {
            if (ambientAppContainer) {
                assignToContainer(chrome, ambientAppContainer, "Ambient Page")
            } else {
                console.error("   ❌ ambientAppContainer is null!")
            }
            return

        // Test client routing
        } else if (identifier === "test_gearapp" || (idLower.includes("test") && idLower.includes("gear"))) {
            if (gearAppContainer) {
                assignToContainer(chrome, gearAppContainer, "Left Gear Panel (test)")
            }
            return

        } else if (identifier === "test_homescreenapp" || (idLower.includes("test") && idLower.includes("home"))) {
            if (homeScreenAppContainer) {
                assignToContainer(chrome, homeScreenAppContainer, "Home Page (test)")
            }
            return

        } else if (identifier === "test_mediaapp" || (idLower.includes("test") && idLower.includes("media"))) {
            if (mediaAppContainer) {
                assignToContainer(chrome, mediaAppContainer, "Media Page (test)")
            }
            return

        } else if (identifier === "test_ambientapp" || (idLower.includes("test") && idLower.includes("ambient"))) {
            if (ambientAppContainer) {
                assignToContainer(chrome, ambientAppContainer, "Ambient Page (test)")
            }
            return
        }

        // Default: Don't route unknown surfaces (prevents overlapping)
        console.error("⚠️  Unknown app_id - NOT ROUTING:", identifier)
        console.error("   Surface will be hidden. Check app's QGuiApplication::setApplicationName()")

        // Hide the chrome so it doesn't appear anywhere
        chrome.visible = false
    }
}
