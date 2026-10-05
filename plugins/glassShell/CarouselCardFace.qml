import QtQuick
import QtQuick.Effects
import qs.Common

Item {
    id: face
    default property alias artwork: content.data
    property real skewAngle: 0
    property real cornerRadius: 20
    property bool selected: false
    property bool secondary: false
    property real dimOpacity: 0.3
    // Last-resort contour guard. A carousel supplies one angle constrained by
    // its narrowest card, so this guard does not alter slopes independently.
    readonly property real effectiveSkew: Math.max(-width * 0.4, Math.min(width * 0.4, height * Math.tan(Math.max(-45, Math.min(45, skewAngle)) * Math.PI / 180)))
    readonly property color borderColor: selected ? Theme.primary : secondary ? Theme.surfaceText : Theme.outline
    function centerOffsetAt(y) {
        return effectiveSkew * (.5 - y / Math.max(1, height));
    }
    function safeWidth(margin) {
        return Math.max(0, width - Math.abs(effectiveSkew) - 2 * margin);
    }

    function trace(ctx) {
        const w = width, h = height, s = effectiveSkew;
        const lt = Math.max(0, s), rt = w + Math.min(0, s);
        const rb = w - Math.max(0, s), lb = Math.max(0, -s);
        const r = Math.max(0, Math.min(cornerRadius, h / 3, (rt - lt) / 3));
        ctx.beginPath();
        ctx.moveTo(lt + r, 0); ctx.lineTo(rt - r, 0);
        ctx.quadraticCurveTo(rt, 0, rt + (rb - rt) * r / Math.max(1, h), r);
        ctx.lineTo(rb + (rt - rb) * r / Math.max(1, h), h - r);
        ctx.quadraticCurveTo(rb, h, rb - r, h);
        ctx.lineTo(lb + r, h);
        ctx.quadraticCurveTo(lb, h, lb + (lt - lb) * r / Math.max(1, h), h - r);
        ctx.lineTo(lt + (lb - lt) * r / Math.max(1, h), r);
        ctx.quadraticCurveTo(lt, 0, lt + r, 0); ctx.closePath();
    }
    function containsPoint(point) {
        if (point.x < 0 || point.y < 0 || point.x > width || point.y > height) return false;
        const ctx = maskCanvas.getContext("2d");
        trace(ctx);
        return ctx.isPointInPath(point.x, point.y);
    }
    Item {
        id: content
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            z: 100
            color: Theme.surfaceContainer
            opacity: face.selected ? 0 : face.dimOpacity
        }
        layer.enabled: face.visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: ShaderEffectSource { sourceItem: maskCanvas; hideSource: true; live: true }
            maskThresholdMin: .3
            maskSpreadAtMin: .3
        }
    }
    Canvas {
        id: maskCanvas
        width: face.width; height: face.height
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            face.trace(ctx);
            ctx.fillStyle = "white"; ctx.fill();
        }
    }
    Canvas {
        id: border
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            face.trace(ctx);
            ctx.strokeStyle = face.borderColor;
            ctx.lineWidth = face.selected ? 2 : face.secondary ? 1.5 : .8;
            ctx.stroke();
        }
    }
    onWidthChanged: { maskCanvas.requestPaint(); border.requestPaint(); }
    onHeightChanged: { maskCanvas.requestPaint(); border.requestPaint(); }
    onEffectiveSkewChanged: { maskCanvas.requestPaint(); border.requestPaint(); }
    onCornerRadiusChanged: { maskCanvas.requestPaint(); border.requestPaint(); }
    onSelectedChanged: border.requestPaint()
    onSecondaryChanged: border.requestPaint()
    onBorderColorChanged: border.requestPaint()
}
