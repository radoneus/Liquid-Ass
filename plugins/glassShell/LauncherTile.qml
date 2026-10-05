// Card artwork and launcher interaction adapted from liixini/skwd skwd-launch/qml/launcher/SliceDelegate.qml.
// MIT License, Copyright (c) 2025-2026 liixini.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
import QtQuick
import Quickshell
import QtQuick.Controls
import qs.Common

Item {
    id: tile
    required property var app
    property bool selected: false
    property real skewAngle: 0
    property real cornerRadius: 20
    property real dimOpacity: .42
    property string splash: ""
    property real decodeWidth: width
    property real decodeHeight: height
    signal activated()
    signal highlighted(point position)

    function imageUrl(path) {
        if (!path) return "";
        if (path.startsWith("image://") || path.startsWith("qrc:") || path.startsWith("file:")) return path;
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }
    CarouselCardFace {
        id: face
        anchors.fill: parent
        skewAngle: tile.skewAngle
        cornerRadius: tile.cornerRadius
        selected: tile.selected
        dimOpacity: tile.dimOpacity
        Rectangle { anchors.fill: parent; color: Theme.surfaceContainerHigh }
        Image {
            id: artwork
            anchors.fill: parent
            source: tile.imageUrl(tile.splash || tile.app.background || "")
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(Math.ceil(tile.decodeWidth), Math.ceil(tile.decodeHeight))
            visible: status === Image.Ready
        }
        Image {
            id: icon
            anchors.centerIn: parent
            width: Math.min(tile.width * .5, 110)
            height: Math.min(tile.height * .55, 110)
            source: tile.app.customIcon && !tile.app.useDesktopIcon ? "" : Quickshell.iconPath(tile.app.icon || "application-x-executable", true)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: !artwork.visible && status === Image.Ready
        }
        Text {
            anchors.centerIn: parent
            visible: !artwork.visible && !icon.visible && !!tile.app.customIcon
            text: tile.app.customIcon || ""
            font.pixelSize: Math.min(tile.width, tile.height) * .4
            color: Theme.primary
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: face.centerOffsetAt(tile.height - anchors.bottomMargin - height / 2)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(10, tile.height * .04)
            width: face.safeWidth(12)
            height: Math.min(38, Math.max(28, tile.height * .12))
            radius: height / 2
            color: Theme.withAlpha(Theme.surfaceContainerHighest, .94)
            visible: tile.selected && width >= 100 && tile.height >= 72
            Text {
                anchors.fill: parent
                anchors.margins: 5
                color: Theme.surfaceText
                font.pixelSize: 13
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: tile.app.displayName || tile.app.name || ""
                Accessible.name: text
            }
        }
    }
    Timer {
        id: hoverTimer
        interval: 150
        onTriggered: if (pointer.containsMouse) tile.highlighted(pointer.mapToGlobal(pointer.mouseX, pointer.mouseY))
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        containmentMask: QtObject { function contains(point) { return face.containsPoint(point); } }
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        ToolTip.visible: containsMouse && tile.selected
        ToolTip.text: tile.app.displayName || tile.app.name || ""
        onEntered: hoverTimer.restart()
        onExited: hoverTimer.stop()
        onClicked: tile.activated()
    }
}
