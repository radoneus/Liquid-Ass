import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Effects
import qs.Common

// Geometry and hit testing use the same path as the GPU alpha mask. The live
// desktop fills the card/sector; it is not an icon placed inside that shape.
Item {
    id: root
    required property int workspaceId
    property var workspaceObj: null
    readonly property string workspaceName: workspaceObj?.name ?? ""
    property var monitorIpc: null
    property string monitorName: ""
    property bool capturing: false
    property bool selected: false
    property bool activeWorkspace: false
    property string shape: "rect" // rect, slice, wheel
    property real skew: 0
    property real cornerRadius: 14
    property real centerX: 0 // wheel center, relative to this tile
    property real centerY: 0
    property real outerRadius: 0
    property real innerRadius: 0
    property real startAngle: 0 // degrees from horizontal, clockwise
    property real endAngle: 0
    property real dimOpacity: 0.25
    property real previewBlur: 0
    property real hoverScale: 1.06
    property real labelScale: 1
    property bool hovering: false
    // Hover reveals the actual capture; selection, dim and scale stay independent.
    property real effectivePreviewBlur: hovering ? 0 : previewBlur
    Behavior on effectivePreviewBlur {
        enabled: !root.hovering
        NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
    }
    readonly property int visibleTitleCount: windowTitles.length > 0 ? Math.min(windowTitles.length, labelWidth >= 190 * labelScale ? 2 : 1) : 0
    readonly property var windowTitles: (workspaceObj?.toplevels?.values ?? []).map(window => window?.wayland?.title || window?.lastIpcObject?.title || window?.lastIpcObject?.class || window?.wayland?.appId || "Вікно")
    readonly property string tooltipText: (workspaceName && workspaceName !== String(workspaceId) ? workspaceName + "\n" : "") + windowTitles.join("\n")
    signal activated()
    signal hovered()

    function drawPath(ctx) {
        ctx.beginPath();
        if (shape === "wheel") {
            const a = startAngle * Math.PI / 180;
            const b = endAngle * Math.PI / 180;
            ctx.arc(centerX, centerY, outerRadius, a, b, false);
            ctx.arc(centerX, centerY, innerRadius, b, a, true);
            ctx.closePath();
        } else if (shape === "slice" && Math.abs(skew) > 0.01) {
            const s = Math.max(-width * 0.4, Math.min(width * 0.4, skew));
            ctx.moveTo(Math.max(0, s), 0);
            ctx.lineTo(width + Math.min(0, s), 0);
            ctx.lineTo(width - Math.max(0, s), height);
            ctx.lineTo(-Math.min(0, s), height);
            ctx.closePath();
        } else {
            const r = Math.max(0, Math.min(cornerRadius, width / 2, height / 2));
            ctx.moveTo(r, 0);
            ctx.lineTo(width - r, 0);
            ctx.quadraticCurveTo(width, 0, width, r);
            ctx.lineTo(width, height - r);
            ctx.quadraticCurveTo(width, height, width - r, height);
            ctx.lineTo(r, height);
            ctx.quadraticCurveTo(0, height, 0, height - r);
            ctx.lineTo(0, r);
            ctx.quadraticCurveTo(0, 0, r, 0);
            ctx.closePath();
        }
    }
    function hit(point) {
        if (point.x < 0 || point.y < 0 || point.x > width || point.y > height)
            return false;
        if (shape === "wheel") {
            const dx = point.x - centerX;
            const dy = point.y - centerY;
            const radius = Math.hypot(dx, dy);
            if (radius < innerRadius || radius > outerRadius)
                return false;
            let angle = Math.atan2(dy, dx) * 180 / Math.PI;
            while (angle < startAngle) angle += 360;
            return angle <= endAngle;
        }
        if (shape === "slice") {
            const s = Math.max(-width * 0.4, Math.min(width * 0.4, skew));
            return point.x >= Math.max(0, s) * (1 - point.y / height) - Math.min(0, s) * point.y / height
                && point.x <= width + Math.min(0, s) * (1 - point.y / height) - Math.max(0, s) * point.y / height;
        }
        const r = Math.max(0, Math.min(cornerRadius, width / 2, height / 2));
        const cx = Math.max(r, Math.min(width - r, point.x));
        const cy = Math.max(r, Math.min(height - r, point.y));
        return Math.hypot(point.x - cx, point.y - cy) <= r;
    }
    // Bound the pill by the card's actual width (or a sector's chord), not
    // the huge workspace preview behind it. Its entire text stays inside the mask.
    readonly property real labelWidth: Math.max(0, Math.min(270 * labelScale, width - 12,
        shape === "wheel"
            ? 2 * ((innerRadius + (outerRadius - innerRadius) * 0.68)
                * Math.sin((endAngle - startAngle) * Math.PI / 360) - labelHeight / 2 - 8)
            : width - Math.abs(shape === "slice" ? skew : 0) - 16))
    readonly property real labelHeight: Math.max(0, Math.min(64 * Math.max(1, labelScale), height - 8))
    readonly property real labelX: shape === "wheel"
        ? Math.max(labelWidth / 2 + 2, Math.min(width - labelWidth / 2 - 2,
            centerX + (innerRadius + (outerRadius - innerRadius) * 0.68) * Math.cos((startAngle + endAngle) * Math.PI / 360)))
        : width / 2
    readonly property real labelY: shape === "wheel"
        ? Math.max(labelHeight / 2 + 2, Math.min(height - labelHeight / 2 - 2,
            centerY + (innerRadius + (outerRadius - innerRadius) * 0.68) * Math.sin((startAngle + endAngle) * Math.PI / 360)))
        : height - labelHeight / 2 - 8

    // Visual-only enlargement: the MouseArea below keeps the original contour
    // and hit target when the user moves across neighboring overlapping cards.
    Item {
        id: visual
        anchors.fill: parent
        scale: root.hovering ? root.hoverScale : 1
        transformOrigin: Item.Center
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
    Item {
        id: content
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: ShaderEffectSource {
                sourceItem: Canvas {
                    width: root.width
                    height: root.height
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.fillStyle = "white";
                        root.drawPath(ctx);
                        ctx.fill();
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Connections {
                        target: root
                        function onShapeChanged() { parent.requestPaint(); }
                        function onSkewChanged() { parent.requestPaint(); }
                        function onCornerRadiusChanged() { parent.requestPaint(); }
                        function onCenterXChanged() { parent.requestPaint(); }
                        function onCenterYChanged() { parent.requestPaint(); }
                        function onOuterRadiusChanged() { parent.requestPaint(); }
                        function onInnerRadiusChanged() { parent.requestPaint(); }
                        function onStartAngleChanged() { parent.requestPaint(); }
                        function onEndAngleChanged() { parent.requestPaint(); }
                    }
                }
            }
            maskThresholdMin: 0.3
            maskSpreadAtMin: 0.3
        }

        WorkspaceComposition {
            anchors.fill: parent
            workspaceId: root.workspaceId
            workspaceObj: root.workspaceObj
            monitorName: root.monitorName
            monitorIpc: root.monitorIpc
            capturing: root.capturing
            previewBlur: root.effectivePreviewBlur
        }
        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.surface, root.selected || root.hovering ? 0 : root.dimOpacity)
            Behavior on color { ColorAnimation { duration: 160 } }
        }
        // Current is a persistent, labelled state; keyboard selection and pointer
        // hover use different contours and never replace this badge.
        Rectangle {
            width: 62 * root.labelScale
            height: 19 * root.labelScale
            x: root.labelX - width / 2
            y: root.labelY - root.labelHeight / 2 - height - 3
            radius: height / 2
            visible: root.activeWorkspace
            color: Theme.primary
            Text {
                anchors.centerIn: parent
                text: "Зараз"
                color: Theme.surface
                font.pixelSize: Math.max(12, 12 * root.labelScale)
                font.bold: true
            }
        }
        Item {
            x: root.labelX - width / 2
            y: root.labelY - height / 2
            width: root.labelWidth
            height: root.labelHeight
            clip: true
            Column {
                anchors.fill: parent
                anchors.margins: Math.min(5, Math.max(2, parent.height / 12))
                spacing: 3
                Rectangle {
                    width: Math.min(parent.width, monitorLabel.implicitWidth + 12)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: (parent.height - parent.spacing) / 2
                    radius: Math.min(6, height / 2)
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.85)
                    Text {
                        id: monitorLabel
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        text: "Стіл " + root.workspaceId + (root.monitorName ? " · " + root.monitorName : "")
                        color: Theme.surfaceText
                        font.pixelSize: Math.max(12, 12 * root.labelScale)
                        font.weight: root.selected ? Font.Bold : Font.Medium
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
                Row {
                    id: titleRow
                    width: parent.width
                    height: (parent.height - parent.spacing) / 2
                    spacing: 3
                    Rectangle {
                        visible: root.windowTitles.length === 0
                        width: titleRow.width
                        height: titleRow.height
                        radius: Math.min(6, height / 2)
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.85)
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            text: "Немає вікон"
                            color: Theme.surfaceText
                            font.pixelSize: Math.max(12, 12 * root.labelScale)
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                    Repeater {
                        model: root.windowTitles.slice(0, root.visibleTitleCount)
                        delegate: Rectangle {
                            id: titleChip
                            required property string modelData
                            height: titleRow.height
                            width: Math.max(0, (titleRow.width - (overflow.visible ? overflow.width + titleRow.spacing : 0)
                                - (root.visibleTitleCount - 1) * titleRow.spacing) / root.visibleTitleCount)
                            radius: Math.min(6, height / 2)
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.85)
                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                text: titleChip.modelData
                                color: Theme.surfaceText
                                font.pixelSize: Math.max(12, 12 * root.labelScale)
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                    Rectangle {
                        id: overflow
                        visible: root.windowTitles.length > root.visibleTitleCount
                        width: visible ? Math.max(25, countLabel.implicitWidth + 8) : 0
                        height: titleRow.height
                        radius: Math.min(6, height / 2)
                        color: Theme.withAlpha(Theme.primary, 0.32)
                        Text {
                            id: countLabel
                            anchors.centerIn: parent
                            text: "+" + (root.windowTitles.length - root.visibleTitleCount)
                            color: Theme.surfaceText
                            font.pixelSize: Math.max(12, 12 * root.labelScale)
                            font.bold: true
                        }
                    }
                }
            }
        }
    }

    Canvas {
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.strokeStyle = root.hovering ? Theme.surfaceText : root.selected ? Theme.primary : root.activeWorkspace ? Theme.withAlpha(Theme.primary, 0.8) : Theme.withAlpha(Theme.outline, 0.7);
            ctx.lineWidth = root.hovering ? 3 : root.selected ? 2.5 : root.activeWorkspace ? 2 : 1;
            root.drawPath(ctx);
            ctx.stroke();
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onSelectedChanged() { parent.requestPaint(); }
            function onHoveringChanged() { parent.requestPaint(); }
            function onActiveWorkspaceChanged() { parent.requestPaint(); }
            function onShapeChanged() { parent.requestPaint(); }
            function onSkewChanged() { parent.requestPaint(); }
            function onCornerRadiusChanged() { parent.requestPaint(); }
            function onCenterXChanged() { parent.requestPaint(); }
            function onCenterYChanged() { parent.requestPaint(); }
            function onOuterRadiusChanged() { parent.requestPaint(); }
            function onInnerRadiusChanged() { parent.requestPaint(); }
            function onStartAngleChanged() { parent.requestPaint(); }
            function onEndAngleChanged() { parent.requestPaint(); }
        }
    }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        containmentMask: QtObject {
            function contains(point) { return root.hit(point); }
        }
        onEntered: { root.hovering = true; root.hovered(); }
        onExited: root.hovering = false
        Controls.ToolTip {
            visible: pointer.containsMouse && root.tooltipText.length > 0
            delay: 400
            text: root.tooltipText
            contentItem: Text {
                text: root.tooltipText
                color: Theme.surfaceText
                font.pixelSize: 13
                width: Math.min(500, implicitWidth)
                wrapMode: Text.Wrap
            }
            background: Rectangle { color: Theme.surfaceContainerHigh; radius: 8; border.color: Theme.outline }
        }
        onClicked: root.activated()
    }
}
