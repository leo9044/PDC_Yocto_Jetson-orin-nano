import QtQuick 2.12
import QtQuick.Window 2.12
import QtWayland.Compositor 1.3

/*
 * DES Unified Compositor - Single Wayland Compositor
 *
 * This is a NESTED WAYLAND COMPOSITOR
 * - Connects to Weston (wayland-1) as a client
 * - Shows fullscreen on single display via Weston
 * - Does NOT create a sub-socket: all apps connect directly to wayland-1
 * - Manages both IC and HU app windows in a split layout
 *
 * Layout:
 * - Left panel (280px): IC area (GearState | Speedometer | BatteryMeter)
 * - Right area: HU area (GearApp panel + HomeScreen/Media/Ambient pages)
 */

WaylandCompositor {
    id: compositor

    // NO socketName here — all apps connect directly to wayland-1 (Weston)
    // IC apps: WAYLAND_DISPLAY=wayland-1
    // HU apps: WAYLAND_DISPLAY=wayland-1

    // ═══════════════════════════════════════════════════════════
    // Nested Compositor Output - Shows on display via Weston
    // ═══════════════════════════════════════════════════════════
    WaylandOutput {
        id: output
        compositor: compositor
        sizeFollowsWindow: true

        window: Window {
            id: mainWindow
            width: 1024
            height: 600
            visible: true
            title: "UnifiedCompositor"
            color: "#000000"

            Component.onCompleted: {
                mainWindow.contentItem.grabToImage(function(result) {
                    console.log("✅ OpenGL context initialized")
                })
            }

            CompositorLayout {
                id: layout
                anchors.fill: parent

                onSurfaceCountChanged: {
                    var count = surfacesList.count
                    layout.surfaceCount = count + " apps"
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Surface Management
    // ═══════════════════════════════════════════════════════════
    ListModel {
        id: surfacesList
    }

    property alias surfaces: surfacesList

    SurfaceRouter {
        id: surfaceRouter
        // HU containers
        gearAppContainer: layout.gearAppContainer
        homeScreenAppContainer: layout.homeScreenAppContainer
        mediaAppContainer: layout.mediaAppContainer
        ambientAppContainer: layout.ambientAppContainer
        // IC containers
        gearStateContainer: layout.gearStateContainer
        speedometerContainer: layout.speedometerContainer
        batteryMeterContainer: layout.batteryMeterContainer
    }

    Component {
        id: chromeComponent

        ShellSurfaceItem {
            id: chrome
            autoCreatePopupItems: true
            width: 800
            height: 600

            onSurfaceDestroyed: {
                console.log("🗑️  Surface destroyed")
                for (var i = 0; i < surfacesList.count; i++) {
                    if (surfacesList.get(i).surface === chrome) {
                        surfacesList.remove(i)
                        break
                    }
                }
                layout.surfaceCount = surfacesList.count + " apps"
                chrome.destroy()
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // XDG Shell Extension
    // ═══════════════════════════════════════════════════════════
    XdgShell {
        onToplevelCreated: {
            var appId = toplevel.appId || ""
            var title = toplevel.title || ""

            console.log("═══════════════════════════════════════")
            console.log("🪟 New XDG Toplevel created")
            console.log("   App ID:", appId)
            console.log("   Window Title:", title)

            var chrome = chromeComponent.createObject(layout, {
                "shellSurface": xdgSurface
            })

            surfacesList.append({"surface": chrome, "appId": appId, "title": title})
            layout.surfaceCount = surfacesList.count + " apps"

            toplevel.titleChanged.connect(function() {
                var newTitle = toplevel.title || ""
                var currentParent = chrome.parent

                console.log("📝 Title changed to:", newTitle)
                var targetParent = surfaceRouter.getTargetContainer(newTitle)

                if (currentParent !== targetParent) {
                    surfaceRouter.routeSurface(chrome, newTitle)
                    var newSize = surfaceRouter.getSuggestedSize(newTitle)
                    toplevel.sendConfigure(newSize, [])
                }
                console.log("═══════════════════════════════════════")
            })

            var identifier = appId || title
            surfaceRouter.routeSurface(chrome, identifier)

            var suggestedSize = surfaceRouter.getSuggestedSize(identifier)
            toplevel.sendConfigure(suggestedSize, [])
            console.log("📐 Sent configure:", suggestedSize.width, "x", suggestedSize.height)
            console.log("✅ Surface routed successfully")
            console.log("═══════════════════════════════════════")
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Initialization
    // ═══════════════════════════════════════════════════════════
    Component.onCompleted: {
        console.log("════════════════════════════════════════════════════════")
        console.log("🚀 DES Unified Compositor (Single Display)")
        console.log("════════════════════════════════════════════════════════")
        console.log("🖥️  1024x600 — IC(left 280px) + HU(right 744px)")
        console.log("   IC area:  GearState | Speedometer | BatteryMeter")
        console.log("   HU area:  GearApp panel + Home/Media/Ambient pages")
        console.log("")
        console.log("🔌 All apps connect to: wayland-1 (Weston socket)")
        console.log("════════════════════════════════════════════════════════")
    }
}

    // ═══════════════════════════════════════════════════════════
    // Nested Compositor Output - Shows on HDMI via Weston
    // This window will be displayed fullscreen on HDMI-A-1 by Weston
    // ═══════════════════════════════════════════════════════════
    WaylandOutput {
        id: output
        compositor: compositor
        sizeFollowsWindow: true

        window: Window {
            id: mainWindow
            width: 1024   // HDMI resolution
            height: 600
            visible: true
            title: "HeadUnit-Compositor"
            color: "#000000"
            
            // Enable OpenGL rendering for texture handling
            Component.onCompleted: {
                // Force OpenGL context creation
                mainWindow.contentItem.grabToImage(function(result) {
                    console.log("✅ OpenGL context initialized")
                })
            }

            // Load the layout component for HU apps
            CompositorLayout {
                id: layout
                anchors.fill: parent

                // Update surface count when surfaces change
                onSurfaceCountChanged: {
                    var count = surfacesList.count
                    layout.surfaceCount = count + " apps"
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Surface Management
    // ═══════════════════════════════════════════════════════════

    // List to track all surfaces
    ListModel {
        id: surfacesList
    }

    property alias surfaces: surfacesList

    // Surface router (handles routing logic)
    SurfaceRouter {
        id: surfaceRouter
        gearAppContainer: layout.gearAppContainer
        homeScreenAppContainer: layout.homeScreenAppContainer
        mediaAppContainer: layout.mediaAppContainer
        ambientAppContainer: layout.ambientAppContainer
    }

    // Component to wrap each wayland surface
    Component {
        id: chromeComponent

        ShellSurfaceItem {
            id: chrome
            autoCreatePopupItems: true
            
            // Set initial size to prevent 0x0 configure
            width: 800
            height: 600
            
            // Don't send configure here - it will be sent after routing
            // with correct size based on app type

            onSurfaceDestroyed: {
                console.log("🗑️  Surface destroyed")
                for (var i = 0; i < surfacesList.count; i++) {
                    if (surfacesList.get(i).surface === chrome) {
                        surfacesList.remove(i)
                        break
                    }
                }

                // Update surface count
                layout.surfaceCount = surfacesList.count + " apps"

                chrome.destroy()
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // XDG Shell Extension (Modern Wayland Protocol)
    // ═══════════════════════════════════════════════════════════
    XdgShell {
        onToplevelCreated: {
            var appId = toplevel.appId || ""
            var title = toplevel.title || ""

            console.log("═══════════════════════════════════════")
            console.log("🪟 New XDG Toplevel created")
            console.log("   App ID:", appId)
            console.log("   Window Title:", title)
            console.log("   Target area: HDMI (Head Unit)")

            var chrome = chromeComponent.createObject(layout, {
                "shellSurface": xdgSurface
            })

            // Add to surface list
            surfacesList.append({"surface": chrome, "appId": appId, "title": title})

            // Update surface count
            layout.surfaceCount = surfacesList.count + " apps"

            // Monitor title changes for routing
            toplevel.titleChanged.connect(function() {
                var newTitle = toplevel.title || ""
                var currentParent = chrome.parent
                
                console.log("═══════════════════════════════════════")
                console.log("📝 Title changed to:", newTitle)
                console.log("   Current parent ID:", currentParent ? currentParent.objectName : "NULL")
                
                // Route to determine target container
                var targetParent = surfaceRouter.getTargetContainer(newTitle)
                console.log("   Target parent ID:", targetParent ? targetParent.objectName : "NULL")
                
                // Only re-route if target container is different
                if (currentParent !== targetParent) {
                    console.log("   🔄 Re-routing:", currentParent ? currentParent.objectName : "unknown", "→", targetParent ? targetParent.objectName : "unknown")
                    surfaceRouter.routeSurface(chrome, newTitle)
                    
                    // Send correct size after re-routing
                    var newSize = Qt.size(880, 520)
                    if (chrome.parent === layout.gearAppContainer) {
                        newSize = Qt.size(130, 520)
                        console.log("   → Re-configured to Gear Panel: 130x520")
                    } else {
                        console.log("   → Re-configured to Main Area: 880x520")
                    }
                    toplevel.sendConfigure(newSize, [])
                } else {
                    console.log("   ⏩ Already in correct container (", currentParent ? currentParent.objectName : "NULL", "), skipping re-configure")
                }
                
                console.log("═══════════════════════════════════════")
            })

            // Initial routing
            var identifier = appId || title
            var routingResult = surfaceRouter.routeSurface(chrome, identifier)
            
            // CRITICAL: Send initial configure with size to client
            // Determine size based on which container it was routed to
            console.log("🔍 Checking identifier for size:", identifier, "appId:", appId, "title:", title)
            console.log("   chrome.parent:", chrome.parent ? chrome.parent.objectName || "unnamed" : "null")
            
            var suggestedSize = Qt.size(880, 520)  // Default for main area
            
            // Check which container the surface is in
            if (chrome.parent === layout.gearAppContainer) {
                suggestedSize = Qt.size(130, 520)
                console.log("   → Routed to Gear Panel: 130x520")
            } else {
                // Main area apps
                console.log("   → Routed to Main Area: 880x520")
            }
            
            // Use toplevel directly from the signal parameter
            toplevel.sendConfigure(suggestedSize, [])
            console.log("📐 Sent configure:", suggestedSize.width, "x", suggestedSize.height)

            console.log("✅ Surface routed successfully")
            console.log("═══════════════════════════════════════")
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Initialization
    // ═══════════════════════════════════════════════════════════
    Component.onCompleted: {
        console.log("════════════════════════════════════════════════════════")
        console.log("🚀 DES Head Unit - Nested Wayland Compositor")
        console.log("════════════════════════════════════════════════════════")
        console.log("🖥️  Window (1024x600) - Shows on HDMI via Weston")
        console.log("   • Left Panel (130px): GearApp")
        console.log("   • Main Area Pages:")
        console.log("       [0] HOME - HomeScreenApp window")
        console.log("       [1] MEDIA - MediaApp window")
        console.log("       [2] AMBIENT - AmbientApp window")
        console.log("   • Bottom Bar (80px): [Home] [Media] [Ambient]")
        console.log("")
        console.log("⏳ Waiting for client apps to connect...")
        console.log("   HU Apps:")
        console.log("     - 'GearApp' → Left panel")
        console.log("     - 'HomeScreenApp' → Home page")
        console.log("     - 'MediaApp' → Media page")
        console.log("     - 'AmbientApp' → Ambient page")
        console.log("")
        console.log("🔌 Sub-compositor socket: $XDG_RUNTIME_DIR/wayland-3")
        console.log("   Parent compositor: Weston (wayland-1)")
        console.log("   Client apps connect via: QT_QPA_PLATFORM=wayland WAYLAND_DISPLAY=wayland-3")
        console.log("════════════════════════════════════════════════════════")
    }
}
