import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.services
import qs.modules.globals
import qs.config

Item {
    implicitWidth: avatarClip.width
    implicitHeight: 40

    MouseArea {
        id: userHostArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (Visibilities.currentActiveModule === "dashboard") {
                Visibilities.setActiveModule("overview");
            } else if (Visibilities.currentActiveModule === "overview") {
                GlobalStates.launcherCurrentTab = 0;
                Visibilities.setActiveModule("launcher");
            } else if (Visibilities.currentActiveModule === "launcher") {
                Visibilities.setActiveModule("");
            } else {
                GlobalStates.dashboardCurrentTab = 0;
                Visibilities.setActiveModule("dashboard");
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Item {
                width: 24
                height: 24

                ClippingRectangle {
                    id: avatarClip
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    radius: Styling.radius(0)
                    clip: true

                    Image {
                        id: avatarImage
                        anchors.fill: parent
                        source: GlobalStates.hasAvatar ? "file://" + Paths.avatar : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Icons.user
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: Colors.overBackground
                        visible: !avatarImage.visible
                    }
                }
            }
        }
    }
}
