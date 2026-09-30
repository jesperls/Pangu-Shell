import QtQuick

QtObject {
    id: ctrl

    property int selectedIndex: -1
    property bool renameHighlightsCancel: false

    property var refresh: null
    property var focusSearch: null
    property var setResultsCurrentIndex: null
    property var prepareRename: null

    property bool deleteMode: false
    property string pendingDeleteId: ""
    property int originalSelectedIndex: -1
    property int deleteButtonIndex: 0

    property bool renameMode: false
    property string pendingRenameId: ""
    property string pendingRenameName: ""
    property int renameSelectedIndex: -1
    property int renameButtonIndex: 1
    property string pendingRenamedId: ""

    function enterDeleteMode(id) {
        ctrl.originalSelectedIndex = ctrl.selectedIndex;
        ctrl.deleteMode = true;
        ctrl.pendingDeleteId = id;
        ctrl.deleteButtonIndex = 0;
    }

    function cancelDeleteMode() {
        ctrl.deleteMode = false;
        ctrl.pendingDeleteId = "";
        ctrl.deleteButtonIndex = 0;
        if (ctrl.focusSearch)
            ctrl.focusSearch();
        if (ctrl.refresh)
            ctrl.refresh();
        ctrl.selectedIndex = ctrl.originalSelectedIndex;
        if (ctrl.setResultsCurrentIndex)
            ctrl.setResultsCurrentIndex(ctrl.originalSelectedIndex);
        ctrl.originalSelectedIndex = -1;
    }

    function enterRenameMode(id) {
        ctrl.renameSelectedIndex = ctrl.selectedIndex;
        ctrl.renameMode = true;
        ctrl.pendingRenameId = id;
        ctrl.pendingRenameName = ctrl.prepareRename ? (ctrl.prepareRename(id) ?? "") : id;
        ctrl.renameButtonIndex = 1;
    }

    function cancelRenameMode() {
        ctrl.renameMode = false;
        ctrl.pendingRenameId = "";
        ctrl.pendingRenameName = "";
        ctrl.renameButtonIndex = ctrl.renameHighlightsCancel ? 0 : 1;
        if (ctrl.focusSearch)
            ctrl.focusSearch();
        if (ctrl.pendingRenamedId === "") {
            if (ctrl.refresh)
                ctrl.refresh();
            ctrl.selectedIndex = ctrl.renameSelectedIndex;
            if (ctrl.setResultsCurrentIndex)
                ctrl.setResultsCurrentIndex(ctrl.renameSelectedIndex);
        }
        ctrl.renameSelectedIndex = -1;
    }

    function cancelModes() {
        if (ctrl.deleteMode)
            ctrl.cancelDeleteMode();
        if (ctrl.renameMode)
            ctrl.cancelRenameMode();
    }
}
