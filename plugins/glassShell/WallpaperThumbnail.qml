import QtQuick
import QtQuick.Controls
import Quickshell.Widgets
import qs.Common
import qs.Widgets

Item {
    id: root
    property string imagePath: ""
    property bool selected: false
    property bool currentWallpaper: false
    property real dimOpacity: 0.3
    property real cornerRadius: 20
    property real skewAngle: 0
    readonly property int imageStatus: preview.status
    signal chosen(point position)
    signal activated()

    Accessible.role: Accessible.Button
    Accessible.name: (imagePath ? imagePath.substring(imagePath.lastIndexOf('/') + 1) : "") + (currentWallpaper ? " — поточні шпалери" : "") + (selected ? " — вибрано" : "")
    Accessible.onPressAction: root.activated()

    CarouselCardFace {
        id: face
        anchors.fill: parent
        skewAngle: root.skewAngle
        cornerRadius: root.cornerRadius
        selected: root.selected
        secondary: root.currentWallpaper
        dimOpacity: root.dimOpacity
        Rectangle { anchors.fill: parent; color: Theme.surfaceContainerHighest }
        CachingImage {
            id: preview
            anchors.fill: parent
            imagePath: root.imagePath
            maxCacheSize: 512
            animate: false
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
        }
        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.surfaceContainerHighest, .92)
            visible: preview.status === Image.Error
            Text {
                anchors.centerIn: parent
                text: "Не вдалося відкрити зображення"
                color: Theme.error
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                width: face.safeWidth(12)
                visible: width >= 90 && root.height >= 65
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: face.centerOffsetAt(root.height - anchors.bottomMargin - height / 2)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(10, root.height * .04)
            height: Math.min(38, Math.max(28, root.height * .12))
            width: face.safeWidth(12)
            radius: height / 2
            color: Theme.withAlpha(Theme.surfaceContainerHighest, .94)
            visible: root.selected && width >= 100 && root.height >= 72
            Text {
                anchors.fill: parent
                anchors.margins: 5
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                color: Theme.surfaceText
                font.pixelSize: 13
                fontSizeMode: Text.FixedSize
                elide: Text.ElideMiddle
                text: root.imagePath.substring(root.imagePath.lastIndexOf('/') + 1)
                Accessible.name: text
            }
        }
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: face.centerOffsetAt(anchors.topMargin + height / 2)
            anchors.topMargin: 8
            width: Math.min(currentLabel.implicitWidth + 12, face.safeWidth(8))
            height: 22
            radius: 11
            color: Theme.surfaceContainerHighest
            visible: root.currentWallpaper && width >= currentLabel.implicitWidth + 12 && root.height >= 60
            Text {
                id: currentLabel
                anchors.centerIn: parent
                text: "Поточні"
                color: Theme.surfaceText
                font.pixelSize: 11
            }
        }
    }
    Timer {
        id: hoverTimer
        interval: 150
        onTriggered: if (pointer.containsMouse) root.chosen(pointer.mapToGlobal(pointer.mouseX, pointer.mouseY))
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        containmentMask: QtObject { function contains(point) { return face.containsPoint(point); } }
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        ToolTip.visible: containsMouse && root.selected
        ToolTip.text: root.imagePath.substring(root.imagePath.lastIndexOf('/') + 1)
        onEntered: hoverTimer.restart()
        onExited: hoverTimer.stop()
        onClicked: root.activated()
    }
}
