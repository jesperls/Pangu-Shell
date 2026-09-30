import QtQuick

Item {
    id: root

    property var windows: []
    property bool active: false
    signal cleared()

    readonly property string _grabId: `grab_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`

    function updateGrab() {
        if (active) {
            FocusGrabManager.requestGrab(_grabId, () => {
                root.cleared();
            }, root.windows);
        } else {
            FocusGrabManager.releaseGrab(_grabId);
        }
    }

    onActiveChanged: updateGrab()
    onWindowsChanged: updateGrab()

    Component.onDestruction: {
        if (active) {
            FocusGrabManager.releaseGrab(_grabId);
        }
    }
}
