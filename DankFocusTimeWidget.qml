import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets
import "TimeUtils.js" as TimeUtils

PluginComponent {
    id: root

    layerNamespacePlugin: "dankFocusTime"

    readonly property int stateSchemaVersion: 1
    readonly property int retentionDays: 30
    readonly property int leaseIntervalMs: 2000
    readonly property int leaseTtlMs: 5000
    readonly property int flushIntervalMs: 15000
    readonly property string leaseVarName: "collectorLease"
    readonly property string liveSessionVarName: "liveSession"
    readonly property string ignoredAppId: "org.quickshell"
    readonly property string instanceId: "dft-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    property bool initialized: false
    property bool isMaster: false
    property real nowMs: Date.now()
    property var daysState: ({})
    property var collectorLease: null
    property var liveSession: null
    property var activeSession: null

    readonly property string todayKey: TimeUtils.dayKeyFromMs(nowMs)
    readonly property var mergedTodayEntries: buildEntriesForDay(todayKey)
    readonly property var retainedDayKeys: buildRetainedDayKeys()
    readonly property int trackedDaysCount: buildTrackedDaysCount()
    readonly property real todayPersistedMs: {
        const day = daysState[todayKey];
        return TimeUtils.isPlainObject(day) ? Number(day.totalMs || 0) : 0;
    }
    readonly property real retainedPersistedMs: calculatePersistedTotalMs()
    readonly property bool hasFreshLease: leaseIsFresh(collectorLease, nowMs)
    readonly property bool hasFreshLiveSession: {
        return TimeUtils.isPlainObject(liveSession)
            && hasFreshLease
            && collectorLease.ownerInstanceId === liveSession.ownerInstanceId;
    }
    readonly property real todayLiveDeltaMs: {
        if (!hasFreshLiveSession || liveSession.dayKey !== todayKey)
            return 0;
        return Math.max(0, nowMs - Number(liveSession.startedAt || nowMs));
    }
    readonly property real todayTotalMs: todayPersistedMs + todayLiveDeltaMs
    readonly property real overallTotalMs: retainedPersistedMs + todayLiveDeltaMs
    readonly property var overallEntries: buildOverallEntries()
    readonly property var topOverallEntry: overallEntries.length > 0 ? overallEntries[0] : null
    readonly property string collectorStatusText: {
        if (SessionService.locked)
            return "Locked - timing is paused until you unlock.";
        if (hasFreshLiveSession)
            return (liveSession.title || liveSession.appName || "Focused window") + " is accumulating time now.";
        if (isMaster)
            return "Collector is ready and waiting for a focused window.";
        if (hasFreshLease)
            return "Showing synced data from another bar instance.";
        return "Waiting to acquire the collector lease.";
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: iconWrap.width
            implicitHeight: iconWrap.height

            Item {
                id: iconWrap
                width: root.iconSizeLarge
                height: root.iconSizeLarge

                DankIcon {
                    anchors.centerIn: parent
                    name: "timer"
                    size: root.iconSizeLarge - 2
                    color: root.hasFreshLiveSession ? Theme.primary : Theme.surfaceText
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    color: root.hasFreshLiveSession ? Theme.primary : Theme.outlineButton
                    visible: root.hasFreshLease || root.todayPersistedMs > 0
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: iconWrap.width
            implicitHeight: iconWrap.height

            Item {
                id: iconWrap
                width: root.iconSizeLarge
                height: root.iconSizeLarge

                DankIcon {
                    anchors.centerIn: parent
                    name: "timer"
                    size: root.iconSizeLarge - 4
                    color: root.hasFreshLiveSession ? Theme.primary : Theme.surfaceText
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    color: root.hasFreshLiveSession ? Theme.primary : Theme.outlineButton
                    visible: root.hasFreshLease || root.todayPersistedMs > 0
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            headerText: "Focus Time"
            detailsText: "Overall totals across retained history. Locked time is excluded from timing."
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                StyledRect {
                    width: parent.width
                    implicitHeight: summaryColumn.implicitHeight + Theme.spacingL * 2
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius

                    Column {
                        id: summaryColumn
                        x: Theme.spacingL
                        y: Theme.spacingL
                        width: parent.width - Theme.spacingL * 2
                        spacing: Theme.spacingXS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            Column {
                                width: (parent.width - Theme.spacingM * 2) / 3
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: "Overall"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    text: TimeUtils.formatDuration(root.overallTotalMs)
                                    font.pixelSize: Theme.fontSizeLarge + 2
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                }
                            }

                            Column {
                                width: (parent.width - Theme.spacingM * 2) / 3
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: "Today"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    text: TimeUtils.formatDuration(root.todayTotalMs)
                                    font.pixelSize: Theme.fontSizeLarge + 2
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                }
                            }

                            Column {
                                width: (parent.width - Theme.spacingM * 2) / 3
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: "Tracked Days"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    text: root.trackedDaysCount.toString()
                                    font.pixelSize: Theme.fontSizeLarge + 2
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                }
                            }
                        }

                        StyledText {
                            text: root.collectorStatusText
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            text: root.topOverallEntry
                                ? "Top title: " + root.topOverallEntry.title + " • " + TimeUtils.formatDuration(root.topOverallEntry.totalMs)
                                : "No focused-window time has been recorded yet."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Loader {
                    width: parent.width
                    sourceComponent: root.overallEntries.length > 0 ? entriesListComponent : emptyStateComponent
                }
            }
        }
    }

    popoutWidth: 460
    popoutHeight: 520

    Component {
        id: emptyStateComponent

        StyledRect {
            width: parent.width
            implicitHeight: emptyColumn.implicitHeight + Theme.spacingL * 2
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadius

            Column {
                id: emptyColumn
                x: Theme.spacingL
                y: Theme.spacingL
                width: parent.width - Theme.spacingL * 2
                spacing: Theme.spacingXS

                StyledText {
                    text: "Nothing to show yet"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }

                StyledText {
                    text: "Keep the widget on a bar and focus an app window to start building the overall history."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Component {
        id: entriesListComponent

        Item {
            width: parent.width
            implicitHeight: entriesSection.implicitHeight

            Column {
                id: entriesSection
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    text: "Retained Leaderboard"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }

                StyledText {
                    text: "Window-title totals across the last " + root.retentionDays + " days."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                DankFlickable {
                    id: entriesFlickable
                    width: parent.width
                    height: Math.min(300, entriesColumn.implicitHeight)
                    contentWidth: width
                    contentHeight: entriesColumn.implicitHeight
                    clip: true

                    Column {
                        id: entriesColumn
                        width: entriesFlickable.width
                        spacing: Theme.spacingS

                        Repeater {
                            model: root.overallEntries
                            delegate: entryRowComponent
                        }
                    }
                }
            }
        }
    }

    Component {
        id: entryRowComponent

        StyledRect {
            property var entryData: modelData

            width: parent ? parent.width : 0
            implicitHeight: contentRow.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: root.isLiveEntry(entryData) ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

            Row {
                id: contentRow
                x: Theme.spacingM
                y: Theme.spacingM
                width: parent.width - Theme.spacingM * 2
                spacing: Theme.spacingM

                Item {
                    id: iconHolder
                    width: 34
                    height: 34

                    IconImage {
                        id: appIcon
                        anchors.fill: parent
                        source: root.iconSourceForEntry(entryData)
                        visible: status === Image.Ready
                        smooth: true
                        mipmap: true
                        asynchronous: true
                    }

                    StyledRect {
                        anchors.fill: parent
                        radius: width / 2
                        color: Theme.surfaceContainerHighest
                        visible: !appIcon.visible

                        StyledText {
                            anchors.centerIn: parent
                            text: root.initialForEntry(entryData)
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                        }
                    }
                }

                Column {
                    id: textColumn
                    width: Math.max(0, contentRow.width - iconHolder.width - durationColumn.width - contentRow.spacing * 2)
                    spacing: Theme.spacingXS

                    StyledText {
                        text: entryData.title || entryData.appName || "Untitled Window"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    StyledText {
                        text: root.subtitleForEntry(entryData)
                        visible: text.length > 0
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                Column {
                    id: durationColumn
                    width: Math.max(durationText.implicitWidth, liveText.implicitWidth)
                    spacing: Theme.spacingXS

                    StyledText {
                        id: durationText
                        text: TimeUtils.formatDuration(entryData.totalMs)
                        font.pixelSize: Theme.fontSizeSmall + 1
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignRight
                        width: parent.width
                    }

                    StyledText {
                        id: liveText
                        text: root.isLiveEntry(entryData) ? "Live" : ""
                        visible: text.length > 0
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.primary
                        horizontalAlignment: Text.AlignRight
                        width: parent.width
                    }
                }
            }
        }
    }

    Component.onCompleted: tryInitialize()

    Component.onDestruction: {
        if (isMaster)
            stopTracking("destroy");
        clearLeaseIfOwned();
    }

    onPluginIdChanged: tryInitialize()
    onActiveWindowChanged: syncTracking("active-window")

    Connections {
        target: root.activeWindow
        ignoreUnknownSignals: true

        function onTitleChanged() {
            root.syncTracking("title");
        }

        function onAppIdChanged() {
            root.syncTracking("app-id");
        }
    }

    Connections {
        target: SessionService

        function onLockedChanged() {
            root.syncTracking("locked");
        }
    }

    Connections {
        target: PluginService

        function onPluginStateChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.loadStateFromService();
        }

        function onGlobalVarChanged(changedPluginId, varName) {
            if (changedPluginId !== root.pluginId)
                return;

            if (varName === root.leaseVarName) {
                root.refreshLeaseFromGlobal();
                root.evaluateLeaseOwnership();
            } else if (varName === root.liveSessionVarName) {
                root.refreshLiveSessionFromGlobal();
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    Timer {
        interval: root.leaseIntervalMs
        running: root.initialized
        repeat: true
        onTriggered: root.tickLease()
    }

    Timer {
        interval: root.flushIntervalMs
        running: root.initialized
        repeat: true
        onTriggered: root.syncTracking("periodic")
    }

    function tryInitialize() {
        if (initialized || !pluginId)
            return;

        initialized = true;
        loadStateFromService();
        refreshLeaseFromGlobal();
        refreshLiveSessionFromGlobal();

        Qt.callLater(function () {
            tickLease();
            syncTracking("init");
        });
    }

    function refreshLeaseFromGlobal() {
        collectorLease = TimeUtils.cloneValue(PluginService.getGlobalVar(pluginId, leaseVarName, null));
    }

    function refreshLiveSessionFromGlobal() {
        liveSession = TimeUtils.cloneValue(PluginService.getGlobalVar(pluginId, liveSessionVarName, null));
    }

    function leaseIsFresh(lease, referenceNow) {
        return TimeUtils.isPlainObject(lease)
            && !!lease.ownerInstanceId
            && (referenceNow - Number(lease.heartbeatAt || 0)) < leaseTtlMs;
    }

    function desiredLease(referenceNow) {
        return {
            ownerInstanceId: instanceId,
            heartbeatAt: referenceNow,
            screenName: parentScreen ? parentScreen.name : "",
            section: section
        };
    }

    function tickLease() {
        if (!initialized || !pluginId)
            return;

        const referenceNow = Date.now();
        const lease = collectorLease;

        if (!leaseIsFresh(lease, referenceNow) || lease.ownerInstanceId === instanceId)
            PluginService.setGlobalVar(pluginId, leaseVarName, desiredLease(referenceNow));

        refreshLeaseFromGlobal();
        evaluateLeaseOwnership();
    }

    function evaluateLeaseOwnership() {
        const shouldOwn = leaseIsFresh(collectorLease, Date.now())
            && collectorLease.ownerInstanceId === instanceId;

        if (shouldOwn === isMaster)
            return;

        if (isMaster && !shouldOwn)
            releaseMastership("lease-lost");

        isMaster = shouldOwn;

        if (isMaster)
            acquireMastership();
    }

    function acquireMastership() {
        loadStateFromService();
        ensureSchemaState();
        syncTracking("became-master");
    }

    function releaseMastership(reason) {
        stopTracking(reason);
    }

    function ensureSchemaState() {
        if (PluginService.loadPluginState(pluginId, "schemaVersion", 0) === stateSchemaVersion)
            return;

        PluginService.savePluginState(pluginId, "schemaVersion", stateSchemaVersion);
        PluginService.savePluginState(pluginId, "days", TimeUtils.pruneDays(daysState, retentionDays, Date.now()));
    }

    function loadStateFromService() {
        if (!pluginId)
            return;

        const schemaVersion = PluginService.loadPluginState(pluginId, "schemaVersion", 0);
        const loadedDays = PluginService.loadPluginState(pluginId, "days", {});

        if (schemaVersion !== stateSchemaVersion || !TimeUtils.isPlainObject(loadedDays)) {
            daysState = ({});
            return;
        }

        daysState = TimeUtils.pruneDays(TimeUtils.cloneValue(loadedDays), retentionDays, Date.now());
    }

    function persistState(reason) {
        if (!pluginId || !isMaster)
            return;

        daysState = TimeUtils.pruneDays(daysState, retentionDays, Date.now());
        PluginService.savePluginState(pluginId, "schemaVersion", stateSchemaVersion);
        PluginService.savePluginState(pluginId, "days", daysState);
    }

    function currentTrackableSession() {
        if (SessionService.locked || !activeWindow || (!activeWindow.appId && !activeWindow.title))
            return null;

        if (activeWindow.appId === ignoredAppId)
            return null;

        const appId = activeWindow.appId || "";
        const desktopEntry = appId ? DesktopEntries.heuristicLookup(Paths.moddedAppId(appId)) : null;
        const appName = appId ? Paths.getAppName(appId, desktopEntry) : "";
        const title = (activeWindow.title || appName || appId || "Unknown Window").toString().trim();
        const resolvedAppName = (appName || title || appId || "Unknown App").toString().trim();

        return {
            appId: appId,
            appName: resolvedAppName,
            title: title,
            desktopEntryId: desktopEntry && desktopEntry.id ? desktopEntry.id : "",
            bucketKey: JSON.stringify({
                appId: appId,
                title: title
            })
        };
    }

    function appendDuration(session, startMs, endMs) {
        if (!session || !(endMs > startMs))
            return;

        const nextDays = TimeUtils.cloneValue(daysState) || {};
        let cursor = startMs;

        while (cursor < endMs) {
            const dayKey = TimeUtils.dayKeyFromMs(cursor);
            const boundary = Math.min(endMs, TimeUtils.nextDayStartMs(cursor));
            const duration = boundary - cursor;
            const existingDay = TimeUtils.isPlainObject(nextDays[dayKey]) ? nextDays[dayKey] : {
                totalMs: 0,
                items: {}
            };
            const nextItems = TimeUtils.isPlainObject(existingDay.items) ? existingDay.items : {};
            const existingEntry = TimeUtils.isPlainObject(nextItems[session.bucketKey]) ? nextItems[session.bucketKey] : {
                appId: session.appId,
                appName: session.appName,
                title: session.title,
                desktopEntryId: session.desktopEntryId,
                totalMs: 0,
                lastSeenAt: endMs
            };

            existingEntry.appId = session.appId;
            existingEntry.appName = session.appName;
            existingEntry.title = session.title;
            existingEntry.desktopEntryId = session.desktopEntryId;
            existingEntry.totalMs = Number(existingEntry.totalMs || 0) + duration;
            existingEntry.lastSeenAt = endMs;
            nextItems[session.bucketKey] = existingEntry;

            nextDays[dayKey] = {
                totalMs: Number(existingDay.totalMs || 0) + duration,
                items: nextItems
            };

            cursor = boundary;
        }

        daysState = TimeUtils.pruneDays(nextDays, retentionDays, endMs);
    }

    function checkpointActiveSession(endMs, reason) {
        if (!activeSession)
            return;

        const startMs = Number(activeSession.segmentStartAt || 0);
        if (!(endMs > startMs))
            return;

        appendDuration(activeSession, startMs, endMs);
        activeSession.segmentStartAt = endMs;
        persistState(reason);
    }

    function publishLiveSession(session) {
        if (!pluginId || !session)
            return;

        PluginService.setGlobalVar(pluginId, liveSessionVarName, {
            ownerInstanceId: instanceId,
            dayKey: TimeUtils.dayKeyFromMs(session.segmentStartAt || Date.now()),
            bucketKey: session.bucketKey,
            appId: session.appId,
            appName: session.appName,
            title: session.title,
            desktopEntryId: session.desktopEntryId,
            startedAt: session.segmentStartAt
        });
    }

    function clearLiveSessionIfOwned() {
        if (!pluginId)
            return;

        const currentLiveSession = PluginService.getGlobalVar(pluginId, liveSessionVarName, null);
        if (TimeUtils.isPlainObject(currentLiveSession) && currentLiveSession.ownerInstanceId === instanceId)
            PluginService.setGlobalVar(pluginId, liveSessionVarName, null);
    }

    function stopTracking(reason) {
        if (activeSession)
            checkpointActiveSession(Date.now(), reason);

        activeSession = null;
        clearLiveSessionIfOwned();
    }

    function syncTracking(reason) {
        if (!initialized || !isMaster)
            return;

        const referenceNow = Date.now();
        const nextSession = currentTrackableSession();
        const sameBucket = activeSession && nextSession && activeSession.bucketKey === nextSession.bucketKey;
        const crossedDay = activeSession
            && TimeUtils.dayKeyFromMs(activeSession.segmentStartAt || referenceNow) !== TimeUtils.dayKeyFromMs(referenceNow);
        const needsCheckpoint = !!activeSession && (reason === "periodic" || !sameBucket || crossedDay);

        if (needsCheckpoint)
            checkpointActiveSession(referenceNow, reason);

        if (!nextSession) {
            activeSession = null;
            clearLiveSessionIfOwned();
            return;
        }

        if (!sameBucket) {
            activeSession = nextSession;
            activeSession.segmentStartAt = referenceNow;
            publishLiveSession(activeSession);
            return;
        }

        activeSession.appId = nextSession.appId;
        activeSession.appName = nextSession.appName;
        activeSession.title = nextSession.title;
        activeSession.desktopEntryId = nextSession.desktopEntryId;
        activeSession.bucketKey = nextSession.bucketKey;
        if (needsCheckpoint)
            activeSession.segmentStartAt = referenceNow;
        publishLiveSession(activeSession);
    }

    function clearLeaseIfOwned() {
        if (!pluginId)
            return;

        const currentLease = PluginService.getGlobalVar(pluginId, leaseVarName, null);
        if (TimeUtils.isPlainObject(currentLease) && currentLease.ownerInstanceId === instanceId) {
            PluginService.setGlobalVar(pluginId, leaseVarName, {
                ownerInstanceId: "",
                heartbeatAt: 0
            });
        }
    }

    function buildEntriesForDay(dayKey) {
        const day = TimeUtils.isPlainObject(daysState[dayKey]) ? TimeUtils.cloneValue(daysState[dayKey]) : {
            totalMs: 0,
            items: {}
        };
        const items = TimeUtils.isPlainObject(day.items) ? day.items : {};

        if (hasFreshLiveSession && liveSession.dayKey === dayKey && liveSession.bucketKey) {
            const liveEntry = TimeUtils.isPlainObject(items[liveSession.bucketKey]) ? items[liveSession.bucketKey] : {
                appId: liveSession.appId,
                appName: liveSession.appName,
                title: liveSession.title,
                desktopEntryId: liveSession.desktopEntryId,
                totalMs: 0,
                lastSeenAt: nowMs
            };

            liveEntry.appId = liveSession.appId;
            liveEntry.appName = liveSession.appName;
            liveEntry.title = liveSession.title;
            liveEntry.desktopEntryId = liveSession.desktopEntryId;
            liveEntry.totalMs = Number(liveEntry.totalMs || 0) + Math.max(0, nowMs - Number(liveSession.startedAt || nowMs));
            liveEntry.lastSeenAt = nowMs;
            items[liveSession.bucketKey] = liveEntry;
        }

        const entries = [];
        for (const bucketKey in items) {
            const item = items[bucketKey];
            if (!TimeUtils.isPlainObject(item))
                continue;

            const totalMs = Number(item.totalMs || 0);
            if (totalMs <= 0)
                continue;

            entries.push({
                bucketKey: bucketKey,
                appId: item.appId || "",
                appName: item.appName || "",
                title: item.title || item.appName || "Untitled Window",
                desktopEntryId: item.desktopEntryId || "",
                totalMs: totalMs,
                lastSeenAt: Number(item.lastSeenAt || 0)
            });
        }

        entries.sort(function (left, right) {
            if (left.totalMs !== right.totalMs)
                return right.totalMs - left.totalMs;
            if (left.lastSeenAt !== right.lastSeenAt)
                return right.lastSeenAt - left.lastSeenAt;
            return left.title.localeCompare(right.title);
        });

        return entries;
    }

    function buildRetainedDayKeys() {
        return Object.keys(daysState).sort();
    }

    function buildTrackedDaysCount() {
        const keys = buildRetainedDayKeys();
        if (hasFreshLiveSession && keys.indexOf(todayKey) === -1)
            return keys.length + 1;
        return keys.length;
    }

    function calculatePersistedTotalMs() {
        let total = 0;
        const keys = Object.keys(daysState);

        for (let i = 0; i < keys.length; i++) {
            const day = daysState[keys[i]];
            if (!TimeUtils.isPlainObject(day))
                continue;
            total += Number(day.totalMs || 0);
        }

        return total;
    }

    function buildOverallEntries() {
        const aggregate = {};
        const keys = Object.keys(daysState);

        for (let i = 0; i < keys.length; i++) {
            const day = daysState[keys[i]];
            if (!TimeUtils.isPlainObject(day) || !TimeUtils.isPlainObject(day.items))
                continue;

            for (const bucketKey in day.items) {
                const item = day.items[bucketKey];
                if (!TimeUtils.isPlainObject(item))
                    continue;

                if (!TimeUtils.isPlainObject(aggregate[bucketKey])) {
                    aggregate[bucketKey] = {
                        bucketKey: bucketKey,
                        appId: item.appId || "",
                        appName: item.appName || "",
                        title: item.title || item.appName || "Untitled Window",
                        desktopEntryId: item.desktopEntryId || "",
                        totalMs: 0,
                        lastSeenAt: 0,
                        dayCount: 0
                    };
                }

                aggregate[bucketKey].appId = item.appId || aggregate[bucketKey].appId;
                aggregate[bucketKey].appName = item.appName || aggregate[bucketKey].appName;
                aggregate[bucketKey].title = item.title || aggregate[bucketKey].title;
                aggregate[bucketKey].desktopEntryId = item.desktopEntryId || aggregate[bucketKey].desktopEntryId;
                aggregate[bucketKey].totalMs += Number(item.totalMs || 0);
                aggregate[bucketKey].lastSeenAt = Math.max(aggregate[bucketKey].lastSeenAt, Number(item.lastSeenAt || 0));
                aggregate[bucketKey].dayCount += 1;
            }
        }

        if (hasFreshLiveSession && liveSession.bucketKey) {
            if (!TimeUtils.isPlainObject(aggregate[liveSession.bucketKey])) {
                aggregate[liveSession.bucketKey] = {
                    bucketKey: liveSession.bucketKey,
                    appId: liveSession.appId || "",
                    appName: liveSession.appName || "",
                    title: liveSession.title || liveSession.appName || "Untitled Window",
                    desktopEntryId: liveSession.desktopEntryId || "",
                    totalMs: 0,
                    lastSeenAt: 0,
                    dayCount: 0
                };
            }

            aggregate[liveSession.bucketKey].appId = liveSession.appId || aggregate[liveSession.bucketKey].appId;
            aggregate[liveSession.bucketKey].appName = liveSession.appName || aggregate[liveSession.bucketKey].appName;
            aggregate[liveSession.bucketKey].title = liveSession.title || aggregate[liveSession.bucketKey].title;
            aggregate[liveSession.bucketKey].desktopEntryId = liveSession.desktopEntryId || aggregate[liveSession.bucketKey].desktopEntryId;
            aggregate[liveSession.bucketKey].totalMs += Math.max(0, nowMs - Number(liveSession.startedAt || nowMs));
            aggregate[liveSession.bucketKey].lastSeenAt = Math.max(aggregate[liveSession.bucketKey].lastSeenAt, nowMs);
            if (aggregate[liveSession.bucketKey].dayCount === 0)
                aggregate[liveSession.bucketKey].dayCount = 1;
        }

        const entries = [];
        for (const bucketKey in aggregate) {
            if (aggregate[bucketKey].totalMs > 0)
                entries.push(aggregate[bucketKey]);
        }

        entries.sort(function (left, right) {
            if (left.totalMs !== right.totalMs)
                return right.totalMs - left.totalMs;
            if (left.lastSeenAt !== right.lastSeenAt)
                return right.lastSeenAt - left.lastSeenAt;
            return left.title.localeCompare(right.title);
        });

        return entries;
    }

    function isLiveEntry(entry) {
        return hasFreshLiveSession
            && TimeUtils.isPlainObject(entry)
            && entry.bucketKey === liveSession.bucketKey;
    }

    function desktopEntryForApp(appId) {
        if (!appId)
            return null;
        return DesktopEntries.heuristicLookup(Paths.moddedAppId(appId));
    }

    function iconSourceForEntry(entry) {
        if (!entry || !entry.appId)
            return "";
        return Paths.getAppIcon(entry.appId, desktopEntryForApp(entry.appId));
    }

    function initialForEntry(entry) {
        const appName = entry && entry.appName ? entry.appName : "";
        if (appName.length > 0)
            return appName.charAt(0).toUpperCase();
        const title = entry && entry.title ? entry.title : "";
        return title.length > 0 ? title.charAt(0).toUpperCase() : "?";
    }

    function subtitleForEntry(entry) {
        if (!entry)
            return "";
        const parts = [];
        if (entry.appName && entry.appName !== entry.title)
            parts.push(entry.appName);
        if (entry.dayCount && entry.dayCount > 1)
            parts.push(entry.dayCount + " days");
        return parts.join(" • ");
    }
}
