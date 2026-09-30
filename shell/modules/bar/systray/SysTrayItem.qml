import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config

MouseArea {
    id: root

    required property var bar
    required property SystemTrayItem item
    objectName: "trayItem-" + (item?.id ?? "")
    property int trayItemSize: Math.max(16, Math.min(32, Config.bar.trayIconSize ?? 20))
    property string popupGroup: "bar"
    property var ownerPopup: null
    signal activated()
    property bool isHovered: false

    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    Layout.fillHeight: bar.orientation === "horizontal"
    Layout.fillWidth: bar.orientation === "vertical"
    implicitWidth: trayItemSize
    implicitHeight: trayItemSize

    onClicked: event => {
        if (event.button === Qt.LeftButton && (event.modifiers & Qt.ShiftModifier)) {
            TrayService.setHidden(item, !TrayService.isHidden(item));
            event.accepted = true;
            return;
        }
        switch (event.button) {
        case Qt.LeftButton:
            if (item.onlyMenu && item.hasMenu) systrayPopup.toggle();
            else { item.activate(); root.activated(); }
            break;
        case Qt.RightButton:
            if (item.hasMenu) {
                systrayPopup.toggle();
            }
            break;
        case Qt.MiddleButton:
            item.secondaryActivate();
            break;
        }
        event.accepted = true;
    }

    onWheel: event => {
        const horizontal = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y);
        item.scroll(horizontal ? event.angleDelta.x : event.angleDelta.y, horizontal);
        event.accepted = true;
    }

    BarPopup {
        id: systrayPopup
        anchorItem: root
        bar: root.bar
        groupId: root.popupGroup
        parentPopup: root.ownerPopup

        contentWidth: 220
        contentHeight: Math.min(itemsColumn.implicitHeight + 16, 400)

        popupPadding: 8
        visualMargin: 16

        QsMenuOpener {
            id: menuOpener
            menu: root.item.menu
        }

        ScrollView {
            anchors.fill: parent
            contentWidth: availableWidth
            clip: true

            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                id: itemsColumn
                width: parent.width
                spacing: 2

                Repeater {
                    model: menuOpener.children ? menuOpener.children.values : []

                    delegate: ColumnLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 2

                        property bool submenuExpanded: false

                        SystrayMenuItem {
                            Layout.fillWidth: true

                            textStr: modelData.text || ""
                            iconSource: modelData.icon || ""
                            isImageIcon: iconSource.indexOf("/") !== -1 || iconSource.indexOf(".") !== -1
                            isSeparator: modelData.isSeparator || false
                            hasSubmenu: modelData.hasChildren || false
                            expanded: parent.submenuExpanded
                            buttonType: modelData.buttonType || 0
                            checkState: modelData.checkState || 0

                            onClicked: {
                                if (modelData.hasChildren) {
                                    parent.submenuExpanded = !parent.submenuExpanded;
                                } else {
                                    if (modelData.triggered) {
                                        modelData.triggered();
                                    } else if (modelData.activate) {
                                        modelData.activate();
                                    }
                                    systrayPopup.close();
                                }
                            }
                        }

                        ColumnLayout {
                            visible: submenuExpanded && modelData.hasChildren
                            Layout.fillWidth: true
                            spacing: 2

                            QsMenuOpener {
                                id: subMenuOpener
                                menu: modelData.hasChildren ? modelData : null
                            }

                            Repeater {
                                model: subMenuOpener.children ? subMenuOpener.children.values : []

                                delegate: SystrayMenuItem {
                                    required property var modelData

                                    Layout.fillWidth: true
                                    depth: 1

                                    textStr: modelData.text || ""
                                    iconSource: modelData.icon || ""
                                    isImageIcon: iconSource.indexOf("/") !== -1 || iconSource.indexOf(".") !== -1
                                    isSeparator: modelData.isSeparator || false
                                    buttonType: modelData.buttonType || 0
                                    checkState: modelData.checkState || 0

                                    onClicked: {
                                        if (modelData.triggered) {
                                            modelData.triggered();
                                        } else if (modelData.activate) {
                                            modelData.activate();
                                        }
                                        systrayPopup.close();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    TrayIcon {
        item: root.item
        anchors.centerIn: parent
    }

    StyledToolTip {
        show: root.isHovered && !systrayPopup.isOpen
        tooltipText: root.item.tooltipTitle || root.item.title
        description: (root.item.tooltipDescription ? root.item.tooltipDescription + "\n" : "")
            + (TrayService.isHidden(root.item) ? "Shift-click to show in the bar" : "Shift-click to move to overflow")
    }

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }
}
