import QtQuick
import qs.modules.components
import qs.modules.theme
import qs.modules.globals

import qs.modules.services
import qs.config

ActionGrid {
    id: root

    signal itemSelected

    QtObject {
        id: recordAction
        property string icon: ScreenRecorder.isRecording ? Icons.stop : Icons.recordScreen
        property string text: ScreenRecorder.isRecording ? ScreenRecorder.duration : ""
        property string tooltip: ScreenRecorder.isRecording ? "Stop Recording" : "Screen Recorder"
        property string command: ""
        property string variant: ScreenRecorder.isRecording ? "error" : "primary"
        property string type: "button"
    }

    QtObject {
        id: replayAction
        property string icon: Icons.rewind
        property string tooltip: ReplayService.active ? "Stop Replay Buffer" : "Replay Buffer"
        property string command: ""
        property string variant: ReplayService.active ? "tertiary" : "primary"
        property string type: "button"
    }

    QtObject {
        id: saveReplayAction
        property string icon: Icons.clip
        property string tooltip: "Save Replay"
        property string command: ""
        property string variant: "tertiary"
        property string type: "button"
    }

    layout: "row"
    buttonSize: 48
    iconSize: 20
    spacing: 8

    property var allActions: [
        {
            icon: Icons.camera,
            tooltip: "Screenshot",
            command: ""
        },
        {
            icon: Icons.screenshots,
            tooltip: "Open Screenshots",
            command: ""
        },
        {
            type: "separator"
        },
        recordAction,
        replayAction,
        saveReplayAction,
        {
            icon: Icons.recordings,
            tooltip: "Open Recordings",
            command: ""
        },
        {
            type: "separator"
        },
        {
            icon: Icons.picker,
            tooltip: "Color Picker",
            command: ""
        },
        {
            icon: Icons.textT,
            tooltip: "OCR",
            command: ""
        },
        {
            icon: Icons.qrCode,
            tooltip: "QR Code",
            command: ""
        },
        {
            icon: Icons.google,
            tooltip: "Google Lens",
            command: ""
        },
        {
            icon: GlobalStates.mirrorWindowVisible ? Icons.webcamSlash : Icons.webcam,
            tooltip: "Mirror",
            command: ""
        },
        {
            icon: Icons.keyboard,
            tooltip: "Macros & Hotkeys",
            command: ""
        }
    ]

    actions: allActions.filter(action => action !== saveReplayAction || ReplayService.active)

    function openFolder(kind, subdirectory) {
        ApplicationLauncher.launchCommand(["bash", "-c", 'directory=$(xdg-user-dir "$1")/$2; mkdir -p -- "$directory" && exec xdg-open "$directory"', "pangu-open-directory", kind, subdirectory]);
    }

    onActionTriggered: action => {
        if (action.tooltip === "Screenshot") {
            Screenshot.startCapture();
            root.itemSelected();
        } else if (action.tooltip === "Screen Recorder") {
            ScreenRecorder.initialize();
            GlobalStates.screenRecordReplayMode = false;
            GlobalStates.screenRecordToolVisible = true;
            root.itemSelected();
        } else if (action.tooltip === "Stop Recording") {
            ScreenRecorder.toggleRecording();
            root.itemSelected();
        } else if (action.tooltip === "Replay Buffer" || action.tooltip === "Stop Replay Buffer") {
            if (ReplayService.active) {
                ReplayService.stop();
            } else {
                ScreenRecorder.initialize();
                GlobalStates.screenRecordReplayMode = true;
                GlobalStates.screenRecordToolVisible = true;
            }
            root.itemSelected();
        } else if (action.tooltip === "Save Replay") {
            ReplayService.saveClip();
            root.itemSelected();
        } else if (action.tooltip === "Open Screenshots") {
            root.openFolder("PICTURES", "Screenshots");
            root.itemSelected();
        } else if (action.tooltip === "Open Recordings") {
            root.openFolder("VIDEOS", "Recordings");
            root.itemSelected();
        } else if (action.tooltip === "Color Picker") {
            ApplicationLauncher.launchCommand(["python3", Paths.script("colorpicker.py")]);
            root.itemSelected();
        } else if (action.tooltip === "OCR") {
            Screenshot.startCapture("ocr");
            root.itemSelected();
        } else if (action.tooltip === "QR Code") {
            Screenshot.startCapture("qr");
            root.itemSelected();
        } else if (action.tooltip === "Google Lens") {
            Screenshot.startCapture("lens");
            root.itemSelected();
        } else if (action.tooltip === "Mirror") {
            GlobalStates.mirrorWindowVisible = !GlobalStates.mirrorWindowVisible;
            root.itemSelected();
        } else if (action.tooltip === "Macros & Hotkeys") {
            GlobalShortcuts.toggleMacros();
            root.itemSelected();
        }
    }
}
