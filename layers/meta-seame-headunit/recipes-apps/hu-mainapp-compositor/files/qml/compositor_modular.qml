import QtQuick 2.12
import QtQuick.Window 2.12
import QtWayland.Compositor 1.3

/*
 * DES Unified Compositor — Single Display
 *
 * NESTED WAYLAND COMPOSITOR
 * - Connects to Weston (wayland-1) as a client
 * - No sub-socket: all apps connect directly to wayland-1
 *
 * ── TEST  (DP display, landscape) : window 1024 × 600 ──────────
 *   IC left panel 280px | GearApp 130px | Main 614px
 *
 * ── TARGET (Elecrow 13.3" portrait, MiniHDMI) : window 600 × 1024
 *   IC top 340px | HU bottom 684px (GearApp 130px + Main 470px)
 *   weston.ini [output] transform=90 required
 */

WaylandCompositor {
    id: compositor

    // Sub-compositor socket: apps connect to wayland-2 (NOT wayland-1/Weston)
    // This allows compositor to control window size and placement
    socketName: "wayland-2"

    // ═══════════════════════════════════════════════════════════
    // Output — portrait window shown on display via Weston
    // ═══════════════════════════════════════════════════════════
    WaylandOutput {
        id: output
        compositor: compositor
        sizeFollowsWindow: true

        window: Window {
            id: mainWindow
            // ---- TEST (DP landscape) ----
            width: 1024
            height: 600
            // ---- TARGET (Elecrow portrait) — uncomment when Elecrow arrives
            // width: 600
            // height: 1024
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
        console.log("🚀 DES Unified Compositor — TEST mode (DP landscape 1024x600)")
        console.log("   IC  left 280px : GearState / Speedometer / BatteryMeter")
        console.log("   HU  right      : GearApp(130px) | Main(614px) | NavBar(80px)")
        console.log("   Compositor socket : wayland-2  (apps connect here)")
        console.log("   Parent Weston     : wayland-1")
        console.log("   [TARGET: Elecrow portrait 600x1024 — switch when cable arrives]")
        console.log("════════════════════════════════════════════════════════")
    }
}
