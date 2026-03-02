import QtQuick 2.12
import QtQuick.Window 2.12
import QtWayland.Compositor 1.3

/*
 * DES Unified Compositor - Portrait Single Display
 *
 * NESTED WAYLAND COMPOSITOR
 * - Connects to Weston (wayland-1) as a client
 * - Display: PORTRAIT 600 x 1024
 * - No sub-socket: all apps connect directly to wayland-1
 *
 * Layout (portrait):
 *   Top    340px : IC area  (GearState | Speedometer | BatteryMeter)
 *   Bottom 684px : HU area  (GearApp panel + Home/Media/Ambient pages)
 */

WaylandCompositor {
    id: compositor

    // NO socketName — all apps connect directly to wayland-1 (Weston)

    // ═══════════════════════════════════════════════════════════
    // Output — portrait window shown on display via Weston
    // ═══════════════════════════════════════════════════════════
    WaylandOutput {
        id: output
        compositor: compositor
        sizeFollowsWindow: true

        window: Window {
            id: mainWindow
            width: 600
            height: 1024
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
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Surface Management
    // ═══════════════════════════════════════════════════════════
    ListModel { id: surfacesList }
    property alias surfaces: surfacesList

    SurfaceRouter {
        id: surfaceRouter
        // HU containers
        gearAppContainer:       layout.gearAppContainer
        homeScreenAppContainer: layout.homeScreenAppContainer
        mediaAppContainer:      layout.mediaAppContainer
        ambientAppContainer:    layout.ambientAppContainer
        // IC containers
        gearStateContainer:     layout.gearStateContainer
        speedometerContainer:   layout.speedometerContainer
        batteryMeterContainer:  layout.batteryMeterContainer
    }

    Component {
        id: chromeComponent
        ShellSurfaceItem {
            id: chrome
            autoCreatePopupItems: true
            width: 600
            height: 400

            onSurfaceDestroyed: {
                console.log("🗑️  Surface destroyed")
                for (var i = 0; i < surfacesList.count; i++) {
                    if (surfacesList.get(i).surface === chrome) {
                        surfacesList.remove(i)
                        break
                    }
                }
                chrome.destroy()
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // XDG Shell
    // ═══════════════════════════════════════════════════════════
    XdgShell {
        onToplevelCreated: {
            var appId = toplevel.appId || ""
            var title = toplevel.title || ""
            console.log("🪟 New toplevel:", appId, "/", title)

            var chrome = chromeComponent.createObject(layout, {
                "shellSurface": xdgSurface
            })
            surfacesList.append({"surface": chrome, "appId": appId, "title": title})

            toplevel.titleChanged.connect(function() {
                var newTitle = toplevel.title || ""
                var targetParent = surfaceRouter.getTargetContainer(newTitle)
                if (chrome.parent !== targetParent) {
                    surfaceRouter.routeSurface(chrome, newTitle)
                    toplevel.sendConfigure(surfaceRouter.getSuggestedSize(newTitle), [])
                }
            })

            var identifier = appId || title
            surfaceRouter.routeSurface(chrome, identifier)
            var sz = surfaceRouter.getSuggestedSize(identifier)
            toplevel.sendConfigure(sz, [])
            console.log("📐 configure sent:", sz.width, "x", sz.height)
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Initialization log
    // ═══════════════════════════════════════════════════════════
    Component.onCompleted: {
        console.log("════════════════════════════════════════════════════════")
        console.log("🚀 DES Unified Compositor — Portrait 600x1024")
        console.log("   Top  340px : IC  (GearState | Speedometer | BatteryMeter)")
        console.log("   Bot  684px : HU  (GearApp | Home / Media / Ambient)")
        console.log("   All apps → wayland-1 (Weston socket)")
        console.log("════════════════════════════════════════════════════════")
    }
}
