import QtQuick
import qs.modules.theme

Item {
    id: root

    required property ListView view
    property string variant: "primary"
    property int expandedIndex: -1

    width: view.width
    height: view.currentItem ? view.currentItem.height : 0
    y: view.currentItem ? view.currentItem.y : 0
    visible: view.currentIndex >= 0 && view.currentItem !== null

    function revealExpanded() {
        if (expandedIndex >= 0 && expandedIndex < view.count)
            view.positionViewAtIndex(expandedIndex, ListView.Contain);
    }

    onHeightChanged: if (expandedIndex >= 0) Qt.callLater(root.revealExpanded)

    Behavior on x {
        enabled: Styling.animDuration > 0 && !root.view.moving
        NumberAnimation { duration: Styling.animDuration / 2; easing.type: Easing.OutCubic }
    }
    Behavior on y {
        enabled: Styling.animDuration > 0
        NumberAnimation { duration: Styling.animDuration / 2; easing.type: Easing.OutCubic }
    }
    Behavior on width {
        enabled: Styling.animDuration > 0
        NumberAnimation { duration: Styling.animDuration / 2; easing.type: Easing.OutCubic }
    }
    Behavior on height {
        enabled: Styling.animDuration > 0
        NumberAnimation { duration: Styling.animDuration; easing.type: Easing.OutQuart }
    }

    StyledRect {
        anchors.fill: parent
        variant: root.variant
        radius: Styling.radius(4)
        Behavior on color {
            enabled: Styling.animDuration > 0
            ColorAnimation { duration: Styling.animDuration / 2; easing.type: Easing.OutQuart }
        }
    }
}
