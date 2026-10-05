import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common

// One workspace, in monitor coordinates. Every window is a real toplevel capture;
// absence of a frame is deliberately different from an empty workspace.
Item {
    id: root
    required property int workspaceId
    property var workspaceObj: null
    property string monitorName: ""
    property var monitorIpc: null
    property bool capturing: false
    property real previewBlur: 0

    readonly property var windows: workspaceObj?.toplevels?.values ?? []
    readonly property real monitorScale: monitorIpc?.scale > 0 ? monitorIpc.scale : 1
    readonly property bool rotated: ((monitorIpc?.transform ?? 0) % 2) === 1
    readonly property real desktopWidth: monitorIpc?.width > 0 ? (rotated ? monitorIpc.height : monitorIpc.width) / monitorScale : 1920
    readonly property real desktopHeight: monitorIpc?.height > 0 ? (rotated ? monitorIpc.width : monitorIpc.height) / monitorScale : 1080
    readonly property real originX: monitorIpc?.x ?? 0
    readonly property real originY: monitorIpc?.y ?? 0
    readonly property real zoom: Math.max(width / desktopWidth, height / desktopHeight)
    readonly property real offsetX: (width - desktopWidth * zoom) / 2
    readonly property real offsetY: (height - desktopHeight * zoom) / 2
    readonly property string wallpaperPath: {
        const __ = SessionData.monitorWallpapers;
        return (monitorName ? SessionData.getMonitorWallpaper(monitorName) : "") || SessionData.wallpaperPath || "";
    }
    function fileUrl(path) {
        return "file://" + path.split('/').map(segment => encodeURIComponent(segment)).join('/');
    }

    clip: true
    // Blur only the desktop composition; the tile's ID/title pill and outline
    // are drawn in a separate layer and remain legible.
    layer.enabled: capturing && previewBlur > 0
    layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 32
        blur: Math.max(0, Math.min(32, root.previewBlur)) / 32
        autoPaddingEnabled: false
    }

    Rectangle {
        anchors.fill: parent
        color: root.wallpaperPath.startsWith('#') ? root.wallpaperPath : Theme.surfaceContainer
    }
    Image {
        anchors.fill: parent
        source: root.wallpaperPath && !root.wallpaperPath.startsWith('#') ? root.fileUrl(root.wallpaperPath) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
    }

    // The IPC geometry is in the global logical desktop; the captured surface
    // itself is positioned in those coordinates, including floating windows.
    Repeater {
        model: root.windows
        delegate: Item {
            id: windowItem
            required property var modelData
            required property int index
            readonly property var windowData: modelData?.lastIpcObject ?? null
            readonly property bool fullScreen: (windowData?.fullscreen ?? 0) !== 0
            readonly property bool floating: windowData?.floating ?? false
            readonly property real rawWidth: Math.max(1, windowData?.size?.[0] ?? 1) * root.zoom
            readonly property real rawHeight: Math.max(1, windowData?.size?.[1] ?? 1) * root.zoom
            x: root.offsetX + ((windowData?.at?.[0] ?? root.originX) - root.originX) * root.zoom
            y: root.offsetY + ((windowData?.at?.[1] ?? root.originY) - root.originY) * root.zoom
            width: rawWidth
            height: rawHeight
            z: fullScreen ? 20000 + index : floating ? 10000 + index : index
            visible: !!modelData && !!windowData && width > 1 && height > 1

            ScreencopyView {
                id: frame
                anchors.fill: parent
                captureSource: root.capturing ? windowItem.modelData?.wayland : null
                live: root.capturing
                visible: hasContent
            }
            Rectangle {
                anchors.fill: parent
                visible: root.capturing && !frame.hasContent
                color: Theme.surfaceContainerHigh
                border.width: Math.max(1, root.zoom)
                border.color: Theme.outline
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 8
                    text: "Кадр недоступний"
                    color: Theme.surfaceText
                    font.pixelSize: Math.max(9, Math.min(20, 13 * root.zoom))
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
}
