pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    property var _grabs: ({})
    property var _grabOrder: []
    readonly property bool hasActiveGrab: _grabOrder.length > 0

    function hasGrabFor(screen) {
        return Object.values(_grabs).some(grab => grab.windows.some(window => window?.screen?.name === screen?.name));
    }

    function requestGrab(grabId, clearCallback, windows) {
        if (_grabs[grabId] === undefined) _grabOrder = [..._grabOrder, grabId];
        _grabs = Object.assign({}, _grabs, {[grabId]: {callback: clearCallback, windows: windows || []}});
    }

    function releaseGrab(grabId) {
        const grabs = Object.assign({}, _grabs);
        delete grabs[grabId];
        _grabs = grabs;
        _grabOrder = _grabOrder.filter(id => id !== grabId);
    }

    function clearTopGrab(screen) {
        const order = _grabOrder.filter(id => !screen || _grabs[id].windows.some(window => window?.screen?.name === screen.name));
        if (order.length === 0) return;
        const topId = order[order.length - 1];
        const callback = _grabs[topId].callback;
        releaseGrab(topId);
        if (callback) Qt.callLater(callback);
    }
}
