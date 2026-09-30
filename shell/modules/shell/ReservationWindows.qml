import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config

Item {
    id: root

    required property ShellScreen screen

    property bool barEnabled: true
    property string barPosition: "top"
    property bool barPinned: true
    property int barSize: 0
    property int barOuterMargin: 0
    property bool containBar: false

    property bool dockEnabled: true
    property string dockPosition: "bottom"
    property bool dockPinned: true
    property int dockHeight: 0

    property bool frameEnabled: false
    property int frameThickness: 6

    readonly property int actualFrameSize: frameEnabled ? frameThickness : 0

    Item {
        id: noInputRegion
        width: 0
        height: 0
        visible: false
    }

    function reservationZone(edge) {
        if (!Config.barReady) return 0;
        let zone = actualFrameSize;
        if (barEnabled && barPosition === edge && barPinned) {
            zone += barSize + barOuterMargin;
            if (containBar && frameEnabled) zone += actualFrameSize;
        }
        if (dockEnabled && dockPosition === edge && dockPinned) zone += dockHeight;
        return zone;
    }

    component ReservationWindow: PanelWindow {
        required property string edge

        screen: root.screen
        visible: true
        implicitHeight: (edge === "top" || edge === "bottom") ? Math.max(1, exclusiveZone) : 0
        implicitWidth: (edge === "left" || edge === "right") ? Math.max(1, exclusiveZone) : 0
        color: "transparent"

        anchors.top: edge !== "bottom"
        anchors.bottom: edge !== "top"
        anchors.left: edge !== "right"
        anchors.right: edge !== "left"

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "pangu:reservation:" + edge

        exclusiveZone: root.reservationZone(edge)
        exclusionMode: exclusiveZone > 0 ? ExclusionMode.Normal : ExclusionMode.Ignore

        mask: Region {
            item: noInputRegion
        }
    }

    ReservationWindow { edge: "top" }
    ReservationWindow { edge: "bottom" }
    ReservationWindow { edge: "left" }
    ReservationWindow { edge: "right" }
}
