import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.components
import qs.modules.globals
import qs.config

Item {
    id: root
    property bool schemeListExpanded: false
    readonly property var matugenSchemes: ["scheme-content", "scheme-expressive", "scheme-fidelity", "scheme-fruit-salad", "scheme-monochrome", "scheme-neutral", "scheme-rainbow", "scheme-tonal-spot"]
    property var presets: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.colorPresets : []

    property var combinedModel: {
        var currentPresets = presets;
        var list = [];
        for (var i = 0; i < matugenSchemes.length; i++) {
            list.push({
                id: matugenSchemes[i],
                label: getSchemeDisplayName(matugenSchemes[i]),
                type: "matugen"
            });
        }
        for (var j = 0; j < currentPresets.length; j++) {
            list.push({
                id: currentPresets[j],
                label: currentPresets[j],
                type: "preset"
            });
        }
        return list;
    }

    property bool scrollBarPressed: false
    property int selectedSchemeIndex: -1
    property bool keyboardNavigationActive: false

    signal schemeSelectorClosed
    signal escapePressedOnScheme
    signal tabPressed
    signal shiftTabPressed

    function openAndFocus() {
        schemeListExpanded = true;
        updateSelectedIndex();
        keyboardNavigationActive = true;
        schemeButton.forceActiveFocus();
        positionTimer.restart();
    }

    function positionAtSelectedScheme() {
        if (selectedSchemeIndex >= 0 && selectedSchemeIndex < combinedModel.length) {
            schemeListView.positionViewAtIndex(selectedSchemeIndex, ListView.Center);
        }
    }

    Timer {
        id: positionTimer
        interval: 50
        repeat: false
        onTriggered: {
            positionAtSelectedScheme();
        }
    }

    Connections {
        target: GlobalStates.wallpaperManager
        function onCurrentMatugenSchemeChanged() {
            updateSelectedIndex();
        }
        function onActiveColorPresetChanged() {
            updateSelectedIndex();
        }
    }

    function updateSelectedIndex() {
        if (!GlobalStates.wallpaperManager)
            return;

        var activePreset = GlobalStates.wallpaperManager.activeColorPreset;
        var activeMatugen = GlobalStates.wallpaperManager.currentMatugenScheme;

        var index = -1;

        if (activePreset) {
            for (var i = 0; i < combinedModel.length; i++) {
                if (combinedModel[i].type === "preset" && combinedModel[i].id === activePreset) {
                    index = i;
                    break;
                }
            }
        } else if (activeMatugen) {
            for (var i = 0; i < combinedModel.length; i++) {
                if (combinedModel[i].type === "matugen" && combinedModel[i].id === activeMatugen) {
                    index = i;
                    break;
                }
            }
        }

        if (index !== -1)
            selectedSchemeIndex = index;
    }

    Component.onCompleted: {
        updateSelectedIndex();
    }

    function getSchemeDisplayName(scheme) {
        const map = {
            "scheme-content": "Content",
            "scheme-expressive": "Expressive",
            "scheme-fidelity": "Fidelity",
            "scheme-fruit-salad": "Fruit Salad",
            "scheme-monochrome": "Monochrome",
            "scheme-neutral": "Neutral",
            "scheme-rainbow": "Rainbow",
            "scheme-tonal-spot": "Tonal Spot"
        };
        return map[scheme] || scheme;
    }

    function getCurrentDisplayName() {
        if (!GlobalStates.wallpaperManager)
            return "Select Scheme";

        if (GlobalStates.wallpaperManager.activeColorPreset) {
            return GlobalStates.wallpaperManager.activeColorPreset;
        }

        if (GlobalStates.wallpaperManager.currentMatugenScheme) {
            return getSchemeDisplayName(GlobalStates.wallpaperManager.currentMatugenScheme);
        }

        return "Select Scheme";
    }

    implicitWidth: 200
    implicitHeight: 48

    StyledRect {
        variant: keyboardNavigationActive && schemeButton.activeFocus ? "focus" : "pane"
        radius: Styling.radius(4)
        anchors.fill: parent

        ColumnLayout {
            id: mainLayout
            anchors.fill: parent
            anchors.margins: 4
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Button {
                    id: schemeButton
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    text: getCurrentDisplayName()
                    focus: true

                    onActiveFocusChanged: {
                        if (!activeFocus) {
                            keyboardNavigationActive = false;
                            if (schemeListExpanded) {
                                schemeListExpanded = false;
                            }
                        }
                    }

                    onClicked: {
                        keyboardNavigationActive = false;
                        schemeListExpanded = !schemeListExpanded;
                        if (schemeListExpanded) {
                            updateSelectedIndex();
                            positionTimer.restart();
                        }
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            if (keyboardNavigationActive) {
                                keyboardNavigationActive = false;
                                if (schemeListExpanded) {
                                    schemeListExpanded = false;
                                }
                                if (event.modifiers & Qt.ShiftModifier) {
                                    shiftTabPressed();
                                } else {
                                    tabPressed();
                                }
                                event.accepted = true;
                            }
                        } else if (event.key === Qt.Key_Space) {
                            schemeListExpanded = !schemeListExpanded;
                            if (schemeListExpanded) {
                                updateSelectedIndex();
                                positionTimer.restart();
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Left) {
                            Config.theme.lightMode = true;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Right) {
                            Config.theme.lightMode = false;
                            event.accepted = true;
                        } else if (!schemeListExpanded) {
                            return;
                        } else if (event.key === Qt.Key_Down) {
                            if (selectedSchemeIndex < combinedModel.length - 1) {
                                selectedSchemeIndex++;
                                schemeListView.currentIndex = selectedSchemeIndex;
                                schemeListView.positionViewAtIndex(selectedSchemeIndex, ListView.Contain);
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            if (selectedSchemeIndex > 0) {
                                selectedSchemeIndex--;
                                schemeListView.currentIndex = selectedSchemeIndex;
                                schemeListView.positionViewAtIndex(selectedSchemeIndex, ListView.Contain);
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (selectedSchemeIndex >= 0 && GlobalStates.wallpaperManager) {
                                var item = combinedModel[selectedSchemeIndex];
                                if (item.type === "preset") {
                                    GlobalStates.wallpaperManager.setColorPreset(item.id);
                                } else {
                                    GlobalStates.wallpaperManager.setMatugenScheme(item.id);
                                }
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            keyboardNavigationActive = false;
                            schemeButton.focus = false;
                            if (schemeListExpanded) {
                                schemeListExpanded = false;
                            }
                            escapePressedOnScheme();
                            event.accepted = true;
                        }
                    }

                    background: Rectangle {
                        color: Colors.background
                        radius: Styling.radius(0)
                    }

                    contentItem: Text {
                        text: parent.text
                        color: Colors.overSurface
                        font.family: Config.theme.font
                        font.pixelSize: Config.theme.fontSize
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 8
                    }
                }

                Switch {
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 40
                    checked: Config.theme.lightMode
                    focusPolicy: Qt.NoFocus

                    onCheckedChanged: {
                        Config.theme.lightMode = checked;
                    }

                    indicator: Rectangle {
                        implicitWidth: 72
                        implicitHeight: 40
                        radius: Styling.radius(0)
                        color: Colors.background

                        Text {
                            z: 1
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: Icons.sun
                            color: Config.theme.lightMode ? Styling.srItem("primary") : Colors.overBackground
                            font.family: Icons.font
                            font.pixelSize: 20
                        }

                        Text {
                            z: 1
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: Icons.moon
                            color: Config.theme.lightMode ? Colors.overBackground : Styling.srItem("primary")
                            font.family: Icons.font
                            font.pixelSize: 20
                        }

                        StyledRect {
                            variant: "primary"
                            z: 0
                            width: 36
                            height: 36
                            radius: Styling.radius(-2)
                            x: Config.theme.lightMode ? 2 : 36
                            anchors.verticalCenter: parent.verticalCenter

                            Behavior on x {
                                enabled: Styling.animDuration > 0
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }
            }

        }
    }

    onSchemeListExpandedChanged: {
        if (schemeListExpanded) {
            schemeListPopup.open();
        } else {
            schemeListPopup.close();
        }
    }

    Popup {
        id: schemeListPopup
        parent: root
        x: 0
        y: root.height + 4
        width: root.width
        height: 40 * 3 + 8
        padding: 4
        modal: false
        focus: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        onClosed: {
            if (root.schemeListExpanded) {
                root.schemeListExpanded = false;
            }
        }

        background: Rectangle {
            color: Colors.background
            radius: Styling.radius(0)
        }

        contentItem: RowLayout {
            spacing: 4

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onWheel: wheel => {
                        wheel.accepted = true;
                    }
                    onPressed: mouse => {
                        mouse.accepted = true;
                    }
                }

                ListView {
                        id: schemeListView
                        anchors.fill: parent
                        clip: true
                        model: combinedModel
                        currentIndex: selectedSchemeIndex
                        interactive: true
                        boundsBehavior: Flickable.StopAtBounds
                        highlightFollowsCurrentItem: !isScrolling

                        property bool isScrolling: dragging || flicking

                        onCurrentIndexChanged: {
                            if (currentIndex !== selectedSchemeIndex) {
                                selectedSchemeIndex = currentIndex;
                            }
                        }

                        delegate: Button {
                            required property var modelData
                            required property int index

                            width: schemeListView.width
                            height: 40
                            text: modelData.label

                            onClicked: {
                                if (GlobalStates.wallpaperManager) {
                                    if (modelData.type === "preset") {
                                        GlobalStates.wallpaperManager.setColorPreset(modelData.id);
                                    } else {
                                        GlobalStates.wallpaperManager.setMatugenScheme(modelData.id);
                                    }
                                    schemeListExpanded = false;
                                }
                            }

                            background: Rectangle {
                                color: "transparent"
                            }

                            contentItem: Text {
                                text: parent.text
                                color: selectedSchemeIndex === index ? Styling.srItem("primary") : Colors.overSurface
                                font.family: Config.theme.font
                                font.pixelSize: Config.theme.fontSize
                                font.weight: selectedSchemeIndex === index ? Font.Bold : Font.Normal
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8

                                Behavior on color {
                                    enabled: Styling.animDuration > 0
                                    ColorAnimation {
                                        duration: Styling.animDuration / 2
                                        easing.type: Easing.OutQuart
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: !schemeListView.isScrolling
                                onEntered: {
                                    if (schemeListView.isScrolling)
                                        return;
                                    selectedSchemeIndex = index;
                                    schemeListView.currentIndex = index;
                                }
                                onClicked: {
                                    if (schemeListView.isScrolling)
                                        return;
                                    if (GlobalStates.wallpaperManager) {
                                        if (modelData.type === "preset") {
                                            GlobalStates.wallpaperManager.setColorPreset(modelData.id);
                                        } else {
                                            GlobalStates.wallpaperManager.setMatugenScheme(modelData.id);
                                        }
                                        schemeListExpanded = false;
                                    }
                                }
                            }
                        }

                        highlight: StyledRect {
                            variant: "primary"
                            radius: Styling.radius(0)
                            visible: selectedSchemeIndex >= 0
                            z: -1
                        }

                        highlightMoveDuration: Styling.animDuration > 0 ? Styling.animDuration / 2 : 0
                        highlightMoveVelocity: -1
                        highlightResizeDuration: Styling.animDuration / 2
                        highlightResizeVelocity: -1
                    }
                }

                ScrollBar {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: (40 * 3) - 32
                    Layout.alignment: Qt.AlignVCenter
                    orientation: Qt.Vertical
                    visible: schemeListView.contentHeight > schemeListView.height

                    position: schemeListView.contentY / schemeListView.contentHeight
                    size: schemeListView.height / schemeListView.contentHeight

                    background: Rectangle {
                        color: Colors.background
                        radius: Styling.radius(0)
                    }

                    contentItem: StyledRect {
                        variant: "primary"
                        radius: Styling.radius(0)
                    }

                    onPressedChanged: {
                        scrollBarPressed = pressed;
                    }

                    onPositionChanged: {
                        if (scrollBarPressed && schemeListView.contentHeight > schemeListView.height) {
                            schemeListView.contentY = position * schemeListView.contentHeight;
                        }
                    }
                }
            }
        }
}
