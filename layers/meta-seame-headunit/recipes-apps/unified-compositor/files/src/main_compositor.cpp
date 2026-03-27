#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDebug>
#include <QSurfaceFormat>
#include "VehicleControlClient.h"

int main(int argc, char *argv[])
{
    // Set vsomeip environment for VehicleControl client
    qputenv("VSOMEIP_APPLICATION_NAME", "UnifiedCompositor");
    qputenv("VSOMEIP_CONFIGURATION", "/etc/commonapi/vsomeip_compositor.json");
    qputenv("COMMONAPI_CONFIG", "/etc/commonapi/commonapi_compositor.ini");

    // Wayland platform settings
    qputenv("QT_QPA_PLATFORM", "wayland");
    qputenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");
    qputenv("QT_WAYLAND_SHELL_INTEGRATION", "xdg-shell");

    if (qgetenv("XDG_RUNTIME_DIR").isEmpty()) {
        qputenv("XDG_RUNTIME_DIR", "/run/user/1000");
    }

    QSurfaceFormat format = QSurfaceFormat::defaultFormat();
    format.setDepthBufferSize(24);
    format.setStencilBufferSize(8);
    format.setVersion(2, 0);
    format.setRenderableType(QSurfaceFormat::OpenGLES);
    format.setSwapBehavior(QSurfaceFormat::SingleBuffer);
    QSurfaceFormat::setDefaultFormat(format);

#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
#endif

    QGuiApplication app(argc, argv);

    app.setApplicationName("HeadUnitApp");
    app.setApplicationVersion("2.0-Kiosk");
    app.setOrganizationName("SEA-ME");
    app.setDesktopFileName("HeadUnitApp");

    qDebug() << "═══════════════════════════════════════════════════════";
    qDebug() << "UnifiedCompositor (Portrait 600x1024)";
    qDebug() << "App ID: HeadUnitApp → HDMI-A-1 (1024x600)";
    qDebug() << "═══════════════════════════════════════════════════════";

    // ═══════════════════════════════════════════════════════
    // VehicleControl vsomeip client
    // Subscribes to gearDistanceChanged; exposes currentGear to QML
    // so compositor can show PDC overlay when gear = "R"
    // ═══════════════════════════════════════════════════════
    VehicleControlClient vehicleControlClient;
    vehicleControlClient.connectToService();

    QQmlApplicationEngine engine;

    // Expose VehicleControlClient to QML
    engine.rootContext()->setContextProperty("vehicleControlClient", &vehicleControlClient);

    engine.addImportPath("/usr/lib/qml");

    const QUrl url(QStringLiteral("qrc:/qml/compositor_modular.qml"));
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                qCritical() << "❌ Failed to load Compositor QML:" << url;
                QCoreApplication::exit(-1);
            } else {
                qDebug() << "✅ Compositor UI loaded — ready to embed app windows";
            }
        },
        Qt::QueuedConnection);

    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        qCritical() << "❌ No root objects found!";
        return -1;
    }

    qDebug() << "🚀 Compositor running...";
    return app.exec();
}
