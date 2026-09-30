import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property string value: ""
    signal selected(string value)

    implicitHeight: 36

    readonly property var runningClasses: {
        const seen = {};
        const out = [];
        const clients = Compositor.clients.values || [];
        for (let i = 0; i < clients.length; i++) {
            const cls = clients[i].class || "";
            if (cls.length > 0 && !seen[cls]) {
                seen[cls] = true;
                out.push(cls);
            }
        }
        out.sort();
        return out;
    }

    function appEntries() {
        const source = AppSearch.list || [];
        const out = [];
        for (let i = 0; i < source.length; i++)
            out.push(source[i]);
        return out;
    }

    readonly property string displayText: {
        if (root.value === "")
            return "";
        const apps = root.appEntries();
        for (let i = 0; i < apps.length; i++) {
            const appValue = apps[i].startupClass || String(apps[i].id || "").replace(/\.desktop$/, "");
            if (appValue === root.value)
                return apps[i].name || root.value;
        }
        return root.value;
    }

    function iconSource(name) {
        if (!name || name === "image-missing")
            return "";
        return name.charAt(0) === "/" ? name : "image://icon/" + name;
    }

    function candidates(query) {
        const q = query.trim().toLowerCase();
        const seen = {};
        const rows = [];
        const running = root.runningClasses;
        for (let i = 0; i < running.length; i++) {
            const cls = running[i];
            if (q && cls.toLowerCase().indexOf(q) === -1)
                continue;
            seen[cls] = true;
            rows.push({ value: cls, label: cls, detail: "Running", icon: AppSearch.getCachedIcon(cls) });
        }
        const apps = root.appEntries();
        for (let i = 0; i < apps.length; i++) {
            const app = apps[i];
            if (app.noDisplay)
                continue;
            const value = app.startupClass || String(app.id || "").replace(/\.desktop$/, "");
            if (!value || seen[value])
                continue;
            if (q && String(app.name || "").toLowerCase().indexOf(q) === -1 && value.toLowerCase().indexOf(q) === -1)
                continue;
            seen[value] = true;
            rows.push({ value: value, label: app.name || value, detail: value, icon: app.icon || "application-x-executable" });
        }
        return rows;
    }

    function choose(value) {
        root.value = value;
        root.selected(value);
        popup.close();
    }

    StyledRect {
        anchors.fill: parent
        variant: popup.visible ? "focus" : "common"
        radius: Styling.radius(-2)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 8

            Image {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                visible: root.value !== ""
                source: root.iconSource(AppSearch.getCachedIcon(root.value))
                sourceSize: Qt.size(36, 36)
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
            }

            Text {
                Layout.fillWidth: true
                text: root.value !== "" ? root.displayText : "Select an app"
                color: root.value !== "" ? Colors.overBackground : Colors.outline
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                elide: Text.ElideRight
            }

            Text {
                text: Icons.caretDown
                font.family: Icons.font
                font.pixelSize: 12
                color: Colors.overSurfaceVariant
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                search.text = "";
                popup.open();
                search.focusInput();
            }
        }
    }

    Popup {
        id: popup
        parent: root
        x: 0
        y: root.height + 4
        width: Math.max(root.width, 400)
        height: 320
        padding: 8
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: StyledRect {
            variant: "popup"
            radius: Styling.radius(-4)
        }

        contentItem: ColumnLayout {
            spacing: 6

            SearchInput {
                id: search
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                variant: "common"
                placeholderText: "Search apps, or type a class"
                clearOnEscape: false
                onSearchTextChanged: appList.currentIndex = appList.count > 0 ? 0 : -1
                onEscapePressed: popup.close()
                onAccepted: {
                    if (appList.currentIndex >= 0 && appList.currentIndex < appList.count)
                        root.choose(appList.model[appList.currentIndex].value);
                    else if (search.text.trim() !== "")
                        root.choose(search.text.trim());
                }
                onDownPressed: if (appList.currentIndex < appList.count - 1) appList.currentIndex++
                onUpPressed: if (appList.currentIndex > 0) appList.currentIndex--
            }

            ListView {
                id: appList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.candidates(search.text)
                currentIndex: count > 0 ? 0 : -1
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: appList.width
                    height: 40
                    radius: Styling.radius(-4)
                    color: appList.currentIndex === index ? Styling.srItem("primary") : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 10

                        Image {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            source: root.iconSource(row.modelData.icon)
                            sourceSize: Qt.size(36, 36)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            asynchronous: true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.label
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                                color: appList.currentIndex === row.index ? Styling.srItem("overprimary") : Colors.overBackground
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!row.modelData.detail && row.modelData.detail !== row.modelData.label
                                text: row.modelData.detail || ""
                                font.family: Config.theme.monoFont
                                font.pixelSize: Styling.fontSize(-2)
                                color: appList.currentIndex === row.index ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: appList.currentIndex = row.index
                        onClicked: root.choose(row.modelData.value)
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    width: 6
                }
            }

            Text {
                Layout.fillWidth: true
                visible: appList.count === 0 && search.text.trim() !== ""
                text: "Not listed — press Enter to use \"" + search.text.trim() + "\""
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }
}
