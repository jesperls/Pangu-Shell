pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.config

Singleton {
    id: root

    component Notif: QtObject {
        id: entry
        property Timer closeTimer: Timer {
            interval: 350
            onTriggered: root.finishTimeout(entry.id)
        }
        required property int id
        property Notification notification
        property list<var> actions: notification?.actions.map(action => ({
                    "identifier": action.identifier,
                    "text": action.text
                })) ?? []
        property bool popup: false
        property string appIcon: ""
        property string appName: ""
        property string body: ""
        property string image: ""
        property string summary: ""
        property double time
        property int urgency: NotificationUrgency.Normal
        property int historyPriority: 0
        property string replaceKey: ""
        property var localActionHandlers: ({})
        property Timer timer
        property bool closedConnected: false

        property string cachedAppIcon: ""
        property string cachedImage: ""

        property bool isCached: false

        onNotificationChanged: {
            if (notification) {
                appIcon = notification.appIcon ?? "";
                appName = notification.appName ?? "";
                body = notification.body ?? "";
                image = notification.image ?? "";
                summary = notification.summary ?? "";
                urgency = notification.urgency ?? NotificationUrgency.Normal;

                if (appIcon && !appIcon.startsWith("data:")) {
                    root.cacheImageAsBase64(appIcon, function (cachedData) {
                        cachedAppIcon = cachedData;
                    });
                }
                if (image && !image.startsWith("data:")) {
                    root.cacheImageAsBase64(image, function (cachedData) {
                        cachedImage = cachedData;
                    });
                }

                if (!closedConnected) {
                    notification.closed.connect(function (reason) {
                        if (reason === 3) {
                            root.discardNotification(id);
                        }
                    });
                    closedConnected = true;
                }
            }
        }

        Component.onDestruction: {
            if (timer) {
                timer.stop();
                timer.destroy();
                timer = null;
            }
        }
    }

    function historyImage(image) {
        return typeof image === "string" && !image.startsWith("image://qsimage/") ? image : "";
    }

    function notifToJSON(notif) {
        return {
            "id": notif.id,
            "actions": notif.actions,
            "appIcon": root.historyImage(notif.appIcon),
            "appName": notif.appName,
            "body": notif.body,
            "image": root.historyImage(notif.image),
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
            "historyPriority": notif.historyPriority,
            "replaceKey": notif.replaceKey,
            "cachedAppIcon": root.historyImage(notif.cachedAppIcon),
            "cachedImage": root.historyImage(notif.cachedImage),
            "isCached": notif.isCached
        };
    }

    component NotifTimer: Timer {
        required property int id
        property bool isPaused: false
        property bool expired: false
        running: !isPaused && !expired && !SuspendManager.isSuspending && interval > 0
        onTriggered: {
            expired = true;
            root.timeoutNotification(id);
        }
        function pause() { isPaused = true; }
        function resume() { isPaused = false; }
    }

    property bool silent: false
    property list<Notif> list: []
    property var popupList: list.filter(notif => notif.popup)
    property bool popupInhibited: silent
    property var latestTimeForApp: ({})

    onSilentChanged: if (StateService.initialized) StateService.set("dnd", root.silent)

    Connections {
        target: StateService
        function onStateLoaded() {
            root.silent = StateService.get("dnd", false);
        }
    }

    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    FileView {
        id: notifFileView
        path: Paths.cachePath("notifications.json")
        atomicWrites: true
        onLoaded: loadNotifications()
    }

    function appendNotification(notif) {
        root.list = [...root.list, notif];
        if (root.list.length > 200) {
            root.discardNotifications(root.list.slice(0, root.list.length - 200).map(entry => entry.id));
        }
    }

    function stringifyList(list) {
        return JSON.stringify(list.map(notif => notifToJSON(notif)), null, 2);
    }

    function jsonToNotif(json) {
        return notifComponent.createObject(root, {
            "id": json.id,
            "actions": [],
            "appIcon": root.historyImage(json.cachedAppIcon) || root.historyImage(json.appIcon),
            "appName": json.appName,
            "body": json.body,
            "image": root.historyImage(json.cachedImage) || root.historyImage(json.image),
            "summary": json.summary,
            "time": json.time,
            "urgency": json.urgency,
            "historyPriority": json.historyPriority || 0,
            "replaceKey": json.replaceKey || "",
            "cachedAppIcon": root.historyImage(json.cachedAppIcon),
            "cachedImage": root.historyImage(json.cachedImage),
            "isCached": true,
            "popup": false
        });
    }

    function saveNotifications() {
        const limitedList = limitNotificationsPerSummary(root.list);
        notifFileView.setText(stringifyList(limitedList));
    }

    function limitNotificationsPerSummary(notifications) {
        var groups = Object.create(null);

        notifications.forEach(notif => {
            const key = JSON.stringify([notif.appName, notif.summary || ""]);
            if (!groups[key]) {
                groups[key] = [];
            }
            groups[key].push(notif);
        });

        const limitedNotifications = [];
        for (const key in groups) {
            const group = groups[key];
            group.sort((a, b) => b.time - a.time);
            limitedNotifications.push(...group.slice(0, 5));
        }

        return limitedNotifications.sort((a, b) => a.time - b.time);
    }

    function loadNotifications() {
        try {
            const data = JSON.parse(notifFileView.text());
            if (!Array.isArray(data)) throw new Error("Expected a notification list");
            root.list = data.slice(-200).map(jsonToNotif);
            let maxId = 0;
            root.list.forEach(notif => {
                if (notif.id > maxId)
                    maxId = notif.id;
                if (notif.id <= -1000000)
                    root.internalIdCounter = Math.max(root.internalIdCounter, Math.abs(notif.id) - 999999);
            });
            root.idOffset = maxId + 1;
        } catch (e) {
            console.log("No saved notifications or error loading:", e);
            root.list = [];
            root.idOffset = 0;
        }
    }

    onListChanged: {
        root.list.forEach(notif => {
            if (!root.latestTimeForApp[notif.appName] || notif.time > root.latestTimeForApp[notif.appName]) {
                root.latestTimeForApp[notif.appName] = Math.max(root.latestTimeForApp[notif.appName] || 0, notif.time);
            }
        });
        Object.keys(root.latestTimeForApp).forEach(appName => {
            if (!root.list.some(notif => notif.appName === appName)) {
                delete root.latestTimeForApp[appName];
            }
        });
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            if (groups[b].historyPriority !== groups[a].historyPriority) {
                return groups[b].historyPriority - groups[a].historyPriority;
            }
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = Object.create(null);
        list.forEach((notif, index) => {
            if (!notif || !notif.appName || (!notif.summary && !notif.body)) {
                return;
            }

            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0,
                    historyPriority: 0,
                    totalCount: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            groups[notif.appName].totalCount++;
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
            groups[notif.appName].historyPriority = Math.max(groups[notif.appName].historyPriority || 0, notif.historyPriority || 0);
        });

        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var appNameList: appNameListForGroups(root.groupsByAppName)

    property int idOffset
    property int internalIdCounter: 1
    signal initDone
    signal notify(notification: var)
    signal discard(id: var)
    signal discardAll
    signal timeout(id: var)

    NotificationServer {
        id: notifServer
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: notification => {
            if (!notification || (!notification.summary && !notification.body)) {
                return;
            }

            notification.tracked = true;
            const newNotifObject = notifComponent.createObject(root, {
                "id": notification.id + root.idOffset,
                "notification": notification,
                "time": Date.now()
            });

            Qt.callLater(() => {
                root.appendNotification(newNotifObject);
                saveNotifications();
            });

            if (!root.popupInhibited) {
                newNotifObject.popup = true;
                newNotifObject.timer = notifTimerComponent.createObject(root, {
                    "id": newNotifObject.id,
                    "interval": root.popupTimeout(notification.expireTimeout, notification.urgency)
                });
            }

            root.notify(newNotifObject);
        }
    }

    function notifyInternal(options) {
        if (!options || (!options.summary && !options.body)) {
            return null;
        }

        if (options.replaceKey) {
            const existingIds = root.list.filter(notif => notif && notif.replaceKey === options.replaceKey).map(notif => notif.id);
            if (existingIds.length > 0) {
                root.discardNotifications(existingIds);
            }
        }

        const notificationId = -1000000 - root.internalIdCounter++;
        const newNotifObject = notifComponent.createObject(root, {
            "id": notificationId,
            "actions": options.actions || [],
            "appIcon": options.appIcon || "",
            "appName": options.appName || "Pangu",
            "body": options.body || "",
            "image": options.image || "",
            "summary": options.summary || "",
            "time": options.time || Date.now(),
            "urgency": options.urgency ?? NotificationUrgency.Normal,
            "historyPriority": options.historyPriority || 0,
            "replaceKey": options.replaceKey || "",
            "localActionHandlers": options.actionHandlers || {},
            "popup": !root.popupInhibited && options.popup !== false,
            "isCached": false
        });

        if (newNotifObject.popup) {
            newNotifObject.timer = notifTimerComponent.createObject(root, {
                "id": newNotifObject.id,
                "interval": root.popupTimeout(options.expireTimeout, options.urgency)
            });
        }

        root.appendNotification(newNotifObject);
        saveNotifications();
        root.notify(newNotifObject);
        return newNotifObject;
    }

    function discardNotification(id) {
        const index = root.list.findIndex(notif => notif.id === id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex(notif => notif.id + root.idOffset === id);
        if (index !== -1) {
            const removed = root.list[index];
            root.list.splice(index, 1);
            triggerListChange();
            saveNotifications();
            root.scheduleDestroy(removed);
        }
        if (notifServerIndex !== -1) {
            notifServer.trackedNotifications.values[notifServerIndex].dismiss();
        }
        root.discard(id);
    }

    function discardNotifications(ids) {
        if (!ids || ids.length === 0)
            return;

        var idsMap = {};
        ids.forEach(id => {
            idsMap[id] = true;
        });

        const newList = root.list.filter(notif => !idsMap[notif.id]);
        const removedCount = root.list.length - newList.length;

        if (removedCount > 0) {
            const removed = root.list.filter(notif => idsMap[notif.id]);
            root.list = newList;
            triggerListChange();
            saveNotifications();
            removed.forEach(notif => root.scheduleDestroy(notif));
        }

        ids.forEach(id => {
            const notifServerIndex = notifServer.trackedNotifications.values.findIndex(notif => notif.id + root.idOffset === id);
            if (notifServerIndex !== -1) {
                notifServer.trackedNotifications.values[notifServerIndex].dismiss();
            }
            root.discard(id);
        });
    }

    function discardAllNotifications() {
        const removed = root.list.slice(0);
        root.list = [];
        triggerListChange();
        saveNotifications();
        removed.forEach(notif => root.scheduleDestroy(notif));
        notifServer.trackedNotifications.values.forEach(notif => {
            notif.dismiss();
        });
        root.discardAll();
    }

    signal timeoutWithAnimation(id: var)

    function popupTimeout(timeout, urgency) {
        if (timeout === 0) return 0; // Explicit "never expire".
        if (timeout > 0) return timeout;
        return urgency === NotificationUrgency.Critical ? 0 : 5000;
    }

    function finishTimeout(id) {
        const notif = root.list.find(entry => entry.id === id);
        if (!notif) return;
        notif.popup = false;
        if (notif.timer) {
            notif.timer.destroy();
            notif.timer = null;
        }
        root.timeout(id);
    }

    function timeoutNotification(id) {
        const notif = root.list.find(entry => entry.id === id);
        if (!notif || notif.closeTimer.running) return;
        root.timeoutWithAnimation(id);
        notif.closeTimer.start();
    }

    function attemptInvokeAction(id, notifIdentifier, autoDiscard = true) {
        const entry = root.list.find(notif => notif.id === id);
        if (!entry || entry.isCached) return false;
        const localHandler = (entry.localActionHandlers || {})[notifIdentifier];
        let invoked = false;
        if (typeof localHandler === "function") {
            localHandler(id);
            invoked = true;
        } else {
            const notification = notifServer.trackedNotifications.values.find(notif => notif.id + root.idOffset === id);
            const action = notification?.actions.find(action => action.identifier === notifIdentifier);
            if (action) {
                action.invoke();
                invoked = true;
            }
        }
        if (invoked && autoDiscard)
            root.discardNotification(id);
        return invoked;
    }

    function pauseGroupTimers(appName) {
        root.popupList.forEach(notif => {
            if (notif.appName === appName && notif.timer) {
                notif.timer.pause();
            }
        });
    }

    function resumeGroupTimers(appName) {
        root.popupList.forEach(notif => {
            if (notif.appName === appName && notif.timer) {
                notif.timer.resume();
            }
        });
    }

    function pauseAllTimers() {
        root.popupList.forEach(notif => {
            if (notif.timer) {
                notif.timer.pause();
            }
        });
    }

    function resumeAllTimers() {
        root.popupList.forEach(notif => {
            if (notif.timer) {
                notif.timer.resume();
            }
        });
    }

    function hideAllPopups() {
        root.popupList.forEach(notif => {
            notif.popup = false;
            if (notif.timer) {
                notif.timer.stop();
                notif.timer.destroy();
                notif.timer = null;
            }
        });
    }

    function triggerListChange() {
        root.list = root.list.slice(0);
    }

    property var pendingDestroys: []

    Timer {
        id: destroyTimer
        interval: 300
        repeat: false
        onTriggered: {
            root.pendingDestroys.forEach(notif => notif.destroy());
            root.pendingDestroys = [];
        }
    }

    function scheduleDestroy(notif) {
        if (!notif || root.pendingDestroys.indexOf(notif) !== -1) return;
        root.pendingDestroys = [...root.pendingDestroys, notif];
        if (!destroyTimer.running) destroyTimer.start();
    }

    property int activeXhrCount: 0
    property int maxConcurrentXhr: 3

    function cacheImageAsBase64(imageUrl, callback) {
        if (!imageUrl || imageUrl.startsWith("data:")) {
            callback(imageUrl);
            return;
        }

        if (!imageUrl.startsWith("http://") && !imageUrl.startsWith("https://")) {
            callback(imageUrl);
            return;
        }

        if (imageUrl.length > 2048) {
            callback(imageUrl);
            return;
        }

        if (activeXhrCount >= maxConcurrentXhr) {
            callback(imageUrl);
            return;
        }

        activeXhrCount++;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", imageUrl, true);
        xhr.responseType = "arraybuffer";
        xhr.timeout = 5000;

        var cleanupXhr = function () {
            activeXhrCount--;
            xhr = null;
        };

        xhr.onload = function () {
            if (xhr.status === 200 && xhr.response) {
                try {
                    var arrayBuffer = xhr.response;
                    var bytes = new Uint8Array(arrayBuffer);
                    var len = Math.min(bytes.byteLength, 1024 * 1024);
                    var chunks = [];
                    for (var i = 0; i < len; i += 32768) {
                        chunks.push(String.fromCharCode.apply(null, bytes.subarray(i, Math.min(i + 32768, len))));
                    }
                    var base64 = btoa(chunks.join(''));

                    var mimeType = "image/png";
                    var lowerUrl = imageUrl.toLowerCase();
                    if (lowerUrl.includes(".jpg") || lowerUrl.includes(".jpeg")) {
                        mimeType = "image/jpeg";
                    } else if (lowerUrl.includes(".gif")) {
                        mimeType = "image/gif";
                    } else if (lowerUrl.includes(".webp")) {
                        mimeType = "image/webp";
                    }

                    callback("data:" + mimeType + ";base64," + base64);
                } catch (e) {
                    callback(imageUrl);
                }
            } else {
                callback(imageUrl);
            }
            cleanupXhr();
        };

        xhr.onerror = function () {
            callback(imageUrl);
            cleanupXhr();
        };

        xhr.ontimeout = function () {
            callback(imageUrl);
            cleanupXhr();
        };

        xhr.send();
    }

    Component.onCompleted: {
        if (StateService.initialized)
            root.silent = StateService.get("dnd", false);
        notifFileView.reload();
        root.initDone();
    }
}
