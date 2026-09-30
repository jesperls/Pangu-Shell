pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.modules.components
import qs.modules.corners
import qs.modules.theme
import qs.modules.globals
import qs.modules.widgets.dashboard.widgets
import qs.config

WlSessionLockSurface {
    id: root

    property bool startAnim: false
    property bool authenticating: false

    color: "transparent"

    TintedWallpaper {
        id: wallpaperBackground
        anchors.fill: parent
        z: 1
        radius: 0
        tintEnabled: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.tintEnabled : false

        property string lockscreenFramePath: {
            if (!GlobalStates.wallpaperManager)
                return "";
            return GlobalStates.wallpaperManager.getLockscreenFramePath(GlobalStates.wallpaperManager.currentWallpaper);
        }

        source: lockscreenFramePath ? "file://" + lockscreenFramePath + "?v=" + (GlobalStates.wallpaperManager?.lockscreenVersion ?? 0) : ""

        opacity: startAnim ? 1 : 0
        visible: true

        Behavior on opacity {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration * 2
                easing.type: Easing.OutQuint
            }
        }

        layer.enabled: Config.lockscreen.blurWallpaper ?? true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: startAnim ? 1 : 0
            blurMax: 64
        }

        property real zoomScale: startAnim ? 1.25 : 1.0
        transform: Scale {
            origin.x: wallpaperBackground.width / 2
            origin.y: wallpaperBackground.height / 2
            xScale: wallpaperBackground.zoomScale
            yScale: wallpaperBackground.zoomScale
        }

        Behavior on zoomScale {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration * 2
                easing.type: Easing.OutExpo
            }
        }
    }

    Rectangle {
        id: dimOverlay
        anchors.fill: parent
        color: "black"
        opacity: startAnim ? (Config.lockscreen.dimOpacity ?? 25) / 100 : 0
        z: 3

        property real zoomScale: startAnim ? 1.1 : 1.0

        transform: Scale {
            origin.x: dimOverlay.width / 2
            origin.y: dimOverlay.height / 2
            xScale: dimOverlay.zoomScale
            yScale: dimOverlay.zoomScale
        }

        Behavior on opacity {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration * 2
                easing.type: Easing.OutQuint
            }
        }

        Behavior on zoomScale {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration * 2
                easing.type: Easing.OutExpo
            }
        }
    }

    Item {
        id: clockContainer
        anchors.centerIn: parent
        width: clockColumn.width
        height: clockColumn.height
        z: 10
        visible: Config.lockscreen.showClock ?? true

        property date currentTime: new Date()

        Column {
            id: clockColumn
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6

            Item {
                id: clockWrapper
                width: clockRow.width
                height: hoursText.height * 1.5

                Row {
                    id: clockRow
                    spacing: 0

                    Text {
                        id: hoursText
                        text: Config.bar.use12hFormat ? (clockContainer.currentTime.getHours() % 12 || 12).toString() : Qt.formatTime(clockContainer.currentTime, "hh")
                        font.family: "League Gothic"
                        font.pixelSize: 240
                        color: Colors.primaryFixed
                        antialiasing: true
                        opacity: startAnim ? 1 : 0

                        property real slideOffset: startAnim ? 0 : -150

                        transform: Translate {
                            y: hoursText.slideOffset
                        }

                        layer.enabled: true
                        layer.effect: BgShadow {}

                        Behavior on opacity {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Styling.animDuration * 2
                                easing.type: Easing.OutExpo
                            }
                        }

                        Behavior on slideOffset {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Styling.animDuration * 2
                                easing.type: Easing.OutExpo
                            }
                        }
                    }

                    Text {
                        id: minutesText
                        text: Qt.formatTime(clockContainer.currentTime, "mm")
                        font.family: "League Gothic"
                        font.pixelSize: 240
                        color: Colors.primaryFixedDim
                        antialiasing: true
                        anchors.verticalCenter: undefined
                        anchors.top: hoursText.top
                        anchors.topMargin: hoursText.height * 0.5
                        opacity: startAnim ? 1 : 0

                        property real slideOffset: startAnim ? 0 : 150

                        transform: Translate {
                            y: minutesText.slideOffset
                        }

                        layer.enabled: true
                        layer.effect: BgShadow {}

                        Behavior on opacity {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Styling.animDuration * 2
                                easing.type: Easing.OutExpo
                            }
                        }

                        Behavior on slideOffset {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Styling.animDuration * 2
                                easing.type: Easing.OutExpo
                            }
                        }
                    }

                    Text {
                        id: amPmText
                        text: Config.bar.use12hFormat ? Qt.formatTime(clockContainer.currentTime, "ap").toLowerCase() : ""
                        font.family: "League Gothic"
                        font.pixelSize: 100
                        color: hoursText.color
                        antialiasing: true
                        anchors.top: hoursText.top
                        anchors.topMargin: hoursText.height * 0.35 
                        visible: Config.bar.use12hFormat
                        opacity: startAnim ? 1 : 0

                        property real slideOffset: startAnim ? 0 : -150

                        transform: Translate {
                            y: amPmText.slideOffset
                        }

                        layer.enabled: true
                        layer.effect: BgShadow {}

                        Behavior on opacity {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Styling.animDuration * 2
                                easing.type: Easing.OutExpo
                            }
                        }

                        Behavior on slideOffset {
                            enabled: Styling.animDuration > 0
                            NumberAnimation {
                                duration: Styling.animDuration * 2
                                easing.type: Easing.OutExpo
                            }
                        }
                    }
                }

            }

            Text {
                id: dateText
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clockContainer.currentTime, "dddd, MMMM d")
                font.family: Config.theme.font
                font.pixelSize: 30
                font.weight: Font.Medium
                color: Colors.primaryFixedDim
                antialiasing: true
                opacity: startAnim ? 1 : 0
                visible: Config.lockscreen.showDate ?? true

                property real slideOffset: startAnim ? 0 : 40

                transform: Translate {
                    y: dateText.slideOffset
                }

                Behavior on opacity {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration * 2
                        easing.type: Easing.OutExpo
                    }
                }

                Behavior on slideOffset {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration * 2
                        easing.type: Easing.OutExpo
                    }
                }
            }

            Text {
                id: usernameText
                anchors.horizontalCenter: parent.horizontalCenter
                text: usernameCollector.text.trim()
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(2)
                font.weight: Font.Normal
                color: Colors.overSurfaceVariant
                antialiasing: true
                opacity: startAnim ? 1 : 0
                visible: (Config.lockscreen.showUsername ?? true) && usernameCollector.text.trim() !== ""

                Behavior on opacity {
                    enabled: Styling.animDuration > 0
                    NumberAnimation {
                        duration: Styling.animDuration * 2
                        easing.type: Easing.OutExpo
                    }
                }
            }
        }

        Timer {
            interval: 1000
            running: GlobalStates.lockscreenVisible
            repeat: true
            onTriggered: clockContainer.currentTime = new Date()
        }
    }

    Item {
        id: playerContainer
        z: 10
        visible: Config.lockscreen.showMediaPlayer ?? true

        property bool isTopPosition: Config.lockscreen.position === "top"

        anchors {
            left: parent.left
            leftMargin: startAnim ? 32 : -(playerContainer.width + 64)
            top: isTopPosition ? parent.top : undefined
            topMargin: isTopPosition ? 32 : 0
            bottom: !isTopPosition ? parent.bottom : undefined
            bottomMargin: !isTopPosition ? 32 : 0
        }
        width: 350
        height: playerContent.height

        opacity: startAnim ? 1 : 0

        Behavior on anchors.leftMargin {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration * 2
                easing.type: Easing.OutExpo
            }
        }

        Behavior on opacity {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration * 2
                easing.type: Easing.OutQuad
            }
        }

        LockPlayer {
            id: playerContent
            width: parent.width
        }
    }

    Item {
        id: passwordContainer
        z: 10

        property bool isTopPosition: Config.lockscreen.position === "top"

        anchors {
            horizontalCenter: parent.horizontalCenter
            top: isTopPosition ? parent.top : undefined
            topMargin: isTopPosition ? (startAnim ? 32 : -80) : 0
            bottom: !isTopPosition ? parent.bottom : undefined
            bottomMargin: !isTopPosition ? (startAnim ? 32 : -80) : 0
        }
        width: 350
        height: 96

        opacity: startAnim ? 1 : 0
        scale: startAnim ? 1 : 0.92

        Behavior on anchors.topMargin {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration * 2
                easing.type: Easing.OutExpo
            }
        }

        Behavior on anchors.bottomMargin {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration * 2
                easing.type: Easing.OutExpo
            }
        }

        Behavior on opacity {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration * 2
                easing.type: Easing.OutQuad
            }
        }

        Behavior on scale {
            enabled: Styling.animDuration > 0
            NumberAnimation {
                duration: Styling.animDuration * 2
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }
        }

        StyledRect {
            id: passwordInputBox
            variant: "bg"
            anchors.centerIn: parent
            width: parent.width
            height: 96
            radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0

            property real shakeOffset: 0
            property bool showError: false

            transform: Translate {
                x: passwordInputBox.shakeOffset
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 24
                spacing: 12

                Rectangle {
                    id: avatarContainer
                    width: 64
                    height: 64
                    radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0
                    color: "transparent"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Config.lockscreen.showAvatar ?? true

                    Image {
                        mipmap: true
                        id: userAvatar
                        anchors.fill: parent
                        source: GlobalStates.hasAvatar ? "file://" + Paths.avatar : ""
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                        visible: status === Image.Ready

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                            maskSource: ShaderEffectSource {
                                sourceItem: Rectangle {
                                    width: userAvatar.width
                                    height: userAvatar.height
                                    radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Icons.user
                        font.family: Icons.font
                        font.pixelSize: 32
                        color: Colors.overBackground
                        visible: userAvatar.status !== Image.Ready
                    }
                }

                StyledRect {
                    id: passwordFieldBg
                    width: parent.width - (avatarContainer.visible ? avatarContainer.width + parent.spacing : 0)
                    height: 48
                    anchors.verticalCenter: parent.verticalCenter
                    variant: passwordInputBox.showError ? "error" : "common"
                    radius: Config.roundness > 0 ? (height / 2) * (Config.roundness / 16) : 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 32
                        spacing: 8

                        Text {
                            id: userIcon
                            text: authenticating ? Icons.circleNotch : Icons.user
                            font.family: Icons.font
                            font.pixelSize: 24
                            color: passwordFieldBg.item
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            z: 10
                            rotation: 0

                            Behavior on color {
                                enabled: Styling.animDuration > 0
                                ColorAnimation {
                                    duration: Styling.animDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Timer {
                                id: spinnerTimer
                                interval: 100
                                repeat: true
                                running: authenticating
                                onTriggered: {
                                    userIcon.rotation = (userIcon.rotation + 45) % 360;
                                }
                            }

                            onTextChanged: {
                                if (userIcon.text === Icons.user) {
                                    userIcon.rotation = 0;
                                }
                            }
                        }

                        TextField {
                            id: passwordInput
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            placeholderText: usernameCollector.text.trim()
                            placeholderTextColor: Qt.rgba(passwordFieldBg.item.r, passwordFieldBg.item.g, passwordFieldBg.item.b, 0.5)
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: passwordFieldBg.item
                            background: null
                            echoMode: TextInput.Password
                            verticalAlignment: TextInput.AlignVCenter
                            enabled: !authenticating

                            Behavior on color {
                                enabled: Styling.animDuration > 0
                                ColorAnimation {
                                    duration: Styling.animDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Behavior on placeholderTextColor {
                                enabled: Styling.animDuration > 0
                                ColorAnimation {
                                    duration: Styling.animDuration
                                    easing.type: Easing.OutQuad
                                }
                            }

                            onAccepted: {
                                if (passwordInput.text.trim() === "")
                                    return;

                                authPasswordHolder.password = passwordInput.text;
                                passwordInput.text = "";

                                authenticating = true;
                                pamAuth.start();
                            }
                        }
                    }
                }
            }

            SequentialAnimation {
                id: wrongPasswordAnim
                ScriptAction {
                    script: {
                        passwordInputBox.showError = true;
                    }
                }
                NumberAnimation {
                    target: passwordInputBox
                    property: "shakeOffset"
                    to: 10
                    duration: 50
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: passwordInputBox
                    property: "shakeOffset"
                    to: -10
                    duration: 100
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: passwordInputBox
                    property: "shakeOffset"
                    to: 10
                    duration: 100
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: passwordInputBox
                    property: "shakeOffset"
                    to: 0
                    duration: 50
                    easing.type: Easing.InOutQuad
                }
                ScriptAction {
                    script: {
                        passwordInput.text = "";
                        authenticating = false;
                        passwordInputBox.showError = false;
                    }
                }
            }
        }
    }

    Timer {
        id: unlockTimer
        interval: Styling.animDuration * 2  // Wait for zoom out (1x) + fade out (1x)
        onTriggered: {
            GlobalStates.lockscreenVisible = false;
        }
    }

    Process {
        id: usernameProc
        command: ["whoami"]
        running: true

        stdout: StdioCollector {
            id: usernameCollector
            waitForEnd: true
        }
    }

    QtObject {
        id: authPasswordHolder
        property string password: ""
    }

    PamContext {
        id: pamAuth
        configDirectory: Paths.shellDir + "/config/pam"
        config: "password.conf"

        onPamMessage: {
            console.log("PAM Message:", this.message, "Type:", this.messageType, "Required:", this.responseRequired);
            if (this.responseRequired) {
                this.respond(authPasswordHolder.password);
            }
        }

        onCompleted: result => {
            authPasswordHolder.password = "";

            if (result === PamResult.Success) {
                startAnim = false;

                unlockTimer.start();

                authenticating = false;
            } else {
                console.warn("PAM auth failed with result:", result);
                if (Styling.animDuration > 0) {
                    wrongPasswordAnim.start();
                } else {
                    passwordInput.text = "";
                    authenticating = false;
                    passwordInputBox.showError = false;
                }
            }
        }
    }

    RoundCorner {
        id: topLeft
        size: Styling.radius(4)
        anchors.left: parent.left
        anchors.top: parent.top
        corner: RoundCorner.CornerEnum.TopLeft
        z: 100
    }

    RoundCorner {
        id: topRight
        size: Styling.radius(4)
        anchors.right: parent.right
        anchors.top: parent.top
        corner: RoundCorner.CornerEnum.TopRight
        z: 100
    }

    RoundCorner {
        id: bottomLeft
        size: Styling.radius(4)
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        corner: RoundCorner.CornerEnum.BottomLeft
        z: 100
    }

    RoundCorner {
        id: bottomRight
        size: Styling.radius(4)
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        corner: RoundCorner.CornerEnum.BottomRight
        z: 100
    }

    Component.onCompleted: {
        startAnim = true;
        passwordInput.forceActiveFocus();
    }
}
