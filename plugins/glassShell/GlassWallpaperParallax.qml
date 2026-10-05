import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services

Scope {
    id: parallax

    property point cursorPosition: Qt.point(NaN, NaN)
    property bool requestPending: false
    function finishRequest() {
        requestDeadline.stop();
        requestSocket.connected = false;
        requestPending = false;
    }

    // Hyprland has no cursor-position signal. Query its existing IPC socket at
    // a bounded rate; unlike spawning hyprctl this creates no helper process.
    Timer {
        id: cursorTimer
        interval: 160
        repeat: true
        running: CompositorService.isHyprland && !IdleService.isShellLocked
        triggeredOnStart: true
        onTriggered: {
            if (parallax.requestPending || !Hyprland.requestSocketPath)
                return;
            parallax.requestPending = true;
            requestSocket.connected = true;
            requestDeadline.restart();
        }
        onRunningChanged: {
            if (!running)
                parallax.finishRequest();
        }
    }

    Timer {
        id: requestDeadline
        interval: 700
        onTriggered: parallax.finishRequest()
    }

    // JSON's closing brace frames a complete reply; cursorpos has no trailing
    // newline. Reuse the socket and close locally once the reply is consumed.
    Socket {
        id: requestSocket
        path: Hyprland.requestSocketPath
        connected: false
        onConnectionStateChanged: {
            if (connected) {
                write("j/cursorpos");
                flush();
            } else {
                Qt.callLater(parallax.finishRequest);
            }
        }
        onError: Qt.callLater(parallax.finishRequest)
        parser: SplitParser {
            splitMarker: "}"
            onRead: data => {
                const position = JSON.parse(data + "}");
                if (Number.isFinite(position.x) && Number.isFinite(position.y))
                    parallax.cursorPosition = Qt.point(position.x, position.y);
                parallax.finishRequest();
            }
        }
    }

    Variants {
        model: SettingsData.getFilteredScreens("wallpaper")

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "dms-glass-parallax"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region { item: Item {} }

            readonly property string wallpaperPath: SessionData.getMonitorWallpaper(modelData.name) || ""
            readonly property bool hasImage: wallpaperPath !== "" && !wallpaperPath.startsWith("#")
            readonly property string imageUrl: !hasImage ? "" : wallpaperPath.startsWith("file://")
                ? wallpaperPath : "file://" + wallpaperPath.split("/").map(part => encodeURIComponent(part)).join("/")
            readonly property var monitor: Hyprland.monitors?.values?.find(m => m.name === modelData.name) ?? null
            readonly property var geometry: monitor?.lastIpcObject ?? null
            readonly property int workspaceId: monitor?.activeWorkspace?.id ?? -1
            property real mouseX: 0
            property real mouseY: 0
            property real workspaceShift: {
                const workspaces = Hyprland.workspaces.values.filter(ws => ws.id > 0 && ws.monitor?.name === modelData.name);
                if (workspaces.length < 2)
                    return 0;
                let before = 0;
                for (const ws of workspaces) {
                    if (ws.id < workspaceId)
                        ++before;
                }
                return (before / (workspaces.length - 1) - 0.5) * 32;
            }
            readonly property real bleedX: Math.max(24, Math.min(42, width * 0.018))
            readonly property real bleedY: Math.max(20, Math.min(32, height * 0.018))
            // Keep the Wayland surface stable while asynchronous image loads
            // change status and sourceSize; only image content is conditional.
            visible: CompositorService.isHyprland

            function followPointer() {
                const cursor = parallax.cursorPosition;
                if (!geometry || !Number.isFinite(cursor.x) || !Number.isFinite(cursor.y))
                    return;
                const scale = Number(geometry.scale) || 1;
                const left = Number(geometry.x);
                const top = Number(geometry.y);
                const monitorWidth = Number(geometry.width) / scale;
                const monitorHeight = Number(geometry.height) / scale;
                if (!Number.isFinite(left) || !Number.isFinite(top) || monitorWidth <= 0 || monitorHeight <= 0
                        || cursor.x < left || cursor.x >= left + monitorWidth
                        || cursor.y < top || cursor.y >= top + monitorHeight)
                    return;
                mouseX = ((cursor.x - left) / monitorWidth - 0.5) * 2 * 11;
                mouseY = ((cursor.y - top) / monitorHeight - 0.5) * 2 * 8;
            }
            Connections {
                target: parallax
                function onCursorPositionChanged() { win.followPointer(); }
            }
            onGeometryChanged: followPointer()
            Behavior on mouseX { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on mouseY { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on workspaceShift { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

            Image {
                id: wallpaper
                visible: win.hasImage && status === Image.Ready
                x: -win.bleedX + Math.max(-win.bleedX, Math.min(win.bleedX, win.mouseX + win.workspaceShift))
                y: -win.bleedY + Math.max(-win.bleedY, Math.min(win.bleedY, win.mouseY))
                width: win.width + 2 * win.bleedX
                height: win.height + 2 * win.bleedY
                source: win.imageUrl
                sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
                asynchronous: true
                retainWhileLoading: true
                cache: true
                smooth: true
                fillMode: Image.PreserveAspectCrop
            }
        }
    }
}
