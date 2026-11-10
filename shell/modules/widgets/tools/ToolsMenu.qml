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
        property string name: "record"
        property string icon: ScreenRecorder.isRecording ? Icons.stop : Icons.recordScreen
        property string text: ScreenRecorder.isRecording ? ScreenRecorder.duration : ""
        property string tooltip: ScreenRecorder.isRecording ? "Stop Recording" : "Screen Recorder"
        property string command: ""
        property string variant: ScreenRecorder.isRecording ? "error" : "primary"
        property string type: "button"
    }

    QtObject {
        id: replayAction
        property string name: "replay"
        property string icon: Icons.rewind
        property string tooltip: ReplayService.active ? "Stop Replay Buffer" : "Replay Buffer"
        property string command: ""
        property string variant: ReplayService.active ? "tertiary" : "primary"
        property string type: "button"
    }

    QtObject {
        id: saveReplayAction
        property string name: "saveReplay"
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
            name: "screenshot",
            icon: Icons.camera,
            tooltip: "Screenshot",
            command: ""
        },
        {
            name: "openScreenshots",
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
            name: "openRecordings",
            icon: Icons.recordings,
            tooltip: "Open Recordings",
            command: ""
        },
        {
            type: "separator"
        },
        {
            name: "colorPicker",
            icon: Icons.picker,
            tooltip: "Color Picker",
            command: ""
        },
        {
            name: "ocr",
            icon: Icons.textT,
            tooltip: "OCR",
            command: ""
        },
        {
            name: "qr",
            icon: Icons.qrCode,
            tooltip: "QR Code",
            command: ""
        },
        {
            name: "lens",
            icon: Icons.google,
            tooltip: "Google Lens",
            command: ""
        },
        {
            name: "mirror",
            icon: GlobalStates.mirrorWindowVisible ? Icons.webcamSlash : Icons.webcam,
            tooltip: "Mirror",
            command: ""
        },
        {
            name: "macros",
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
        switch (action.name) {
        case "screenshot":
            Screenshot.startCapture();
            break;
        case "record":
            if (ScreenRecorder.isRecording) {
                ScreenRecorder.toggleRecording();
            } else {
                ScreenRecorder.initialize();
                GlobalStates.screenRecordReplayMode = false;
                GlobalStates.screenRecordToolVisible = true;
            }
            break;
        case "replay":
            if (ReplayService.active) {
                ReplayService.stop();
            } else {
                ScreenRecorder.initialize();
                GlobalStates.screenRecordReplayMode = true;
                GlobalStates.screenRecordToolVisible = true;
            }
            break;
        case "saveReplay":
            ReplayService.saveClip();
            break;
        case "openScreenshots":
            root.openFolder("PICTURES", "Screenshots");
            break;
        case "openRecordings":
            root.openFolder("VIDEOS", "Recordings");
            break;
        case "colorPicker":
            ApplicationLauncher.launchCommand(["python3", Paths.script("colorpicker.py")]);
            break;
        case "ocr":
            Screenshot.startCapture("ocr");
            break;
        case "qr":
            Screenshot.startCapture("qr");
            break;
        case "lens":
            Screenshot.startCapture("lens");
            break;
        case "mirror":
            GlobalStates.mirrorWindowVisible = !GlobalStates.mirrorWindowVisible;
            break;
        case "macros":
            GlobalShortcuts.toggleMacros();
            break;
        default:
            return;
        }
        root.itemSelected();
    }
}
