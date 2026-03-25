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
    readonly property int retentionDays: normalizedRetentionDays(pluginData.retentionDays)
    readonly property int leaseIntervalMs: 2000
    readonly property int leaseTtlMs: 5000
    readonly property int flushIntervalMs: 15000
    readonly property string leaseVarName: "collectorLease"
    readonly property string liveSessionVarName: "liveSession"
    readonly property string ignoredAppId: "org.quickshell"
    readonly property string instanceId: "dft-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    readonly property string languageMode: normalizedLanguageMode(pluginData.languageMode)
    readonly property string uiLanguageCode: {
        if (languageMode === "zh" || languageMode === "en")
            return languageMode;

        const localeName = (Qt.locale().name || "").toLowerCase();
        if (localeName.indexOf("zh") === 0)
            return "zh";
        return "en";
    }
    readonly property var i18nCatalog: ({
        en: {
            focus_time: "Focus Time",
            popout_details: "Switch between overall, history, yesterday, and today. Locked time is excluded from timing.",
            overall: "Overall",
            history: "History",
            yesterday: "Yesterday",
            today: "Today",
            tracked_days: "Tracked Days",
            leaderboard: "Leaderboard",
            leaderboard_overall_hint: "App totals across the last {days} days. Click an app to expand window and tab titles.",
            leaderboard_period_hint: "App totals for {period}. Click an app to expand window and tab titles.",
            top_app_overall: "Top app overall: {app} • {duration}",
            top_app: "Top app in {period}: {app} • {duration}",
            no_focus_time: "No focused-window time has been recorded yet.",
            no_focus_time_period: "No focused-window time has been recorded for {period} yet.",
            nothing_to_show: "Nothing to show yet",
            empty_hint: "Keep the widget on a bar and focus an app window to start building the overall history.",
            nothing_to_show_period: "No data for {period} yet",
            empty_hint_period: "Focus app windows and check back later.",
            browse_date: "Browse Date",
            collapse: "Collapse",
            expand: "Expand",
            live: "Live",
            untitled_window: "Untitled Window",
            unknown_app: "Unknown App",
            one_title: "1 title",
            many_titles: "{count} titles",
            one_day: "1 day",
            many_days: "{count} days"
        },
        zh: {
            focus_time: "专注时长",
            popout_details: "可在总计、历史、昨天、今天之间切换查看，锁屏时间不会计入。",
            overall: "总计",
            history: "历史",
            yesterday: "昨天",
            today: "今天",
            tracked_days: "统计天数",
            leaderboard: "排行",
            leaderboard_overall_hint: "按应用汇总展示最近 {days} 天的时长，点击应用可展开窗口和标签标题。",
            leaderboard_period_hint: "按应用汇总展示 {period} 的时长，点击应用可展开窗口和标签标题。",
            top_app_overall: "总计最高应用：{app} • {duration}",
            top_app: "{period} 最高应用：{app} • {duration}",
            no_focus_time: "还没有记录到聚焦时长。",
            no_focus_time_period: "{period} 还没有记录到聚焦时长。",
            nothing_to_show: "暂时没有数据",
            empty_hint: "把这个部件放在栏上并聚焦应用窗口后，这里就会开始累计总体历史。",
            nothing_to_show_period: "{period} 暂时没有数据",
            empty_hint_period: "继续使用应用一段时间后再回来查看。",
            browse_date: "浏览日期",
            collapse: "收起",
            expand: "展开",
            live: "实时",
            untitled_window: "未命名窗口",
            unknown_app: "未知应用",
            one_title: "1 个标题",
            many_titles: "{count} 个标题",
            one_day: "1 天",
            many_days: "{count} 天"
        }
    })

    property bool initialized: false
    property bool isMaster: false
    property real liveNowMs: Date.now()
    property real statsNowMs: Date.now()
    property string selectedPeriod: normalizedDefaultView(pluginData.defaultView)
    property string historyDayKey: suggestedHistoryDayKey()
    property var daysState: ({})
    property var expandedApps: ({})
    property var collectorLease: null
    property var liveSession: null
    property var activeSession: null

    readonly property string todayKey: TimeUtils.dayKeyFromMs(statsNowMs)
    readonly property string yesterdayKey: previousDayKey(statsNowMs)
    readonly property string historyMinDayKey: TimeUtils.retentionThresholdKey(retentionDays, statsNowMs)
    readonly property string clampedHistoryDayKey: clampHistoryDayKey(historyDayKey)
    readonly property var mergedTodayEntries: buildEntriesForDay(todayKey, statsNowMs)
    readonly property var mergedYesterdayEntries: buildEntriesForDay(yesterdayKey, statsNowMs)
    readonly property var mergedHistoryEntries: buildEntriesForDay(clampedHistoryDayKey, statsNowMs)
    readonly property var retainedDayKeys: buildRetainedDayKeys()
    readonly property int trackedDaysCount: buildTrackedDaysCount()
    readonly property var periodTabs: ([
        { key: "overall", label: translateText("overall") },
        { key: "history", label: translateText("history") },
        { key: "yesterday", label: translateText("yesterday") },
        { key: "today", label: translateText("today") }
    ])
    readonly property real todayPersistedMs: {
        const day = daysState[todayKey];
        return TimeUtils.isPlainObject(day) ? Number(day.totalMs || 0) : 0;
    }
    readonly property real retainedPersistedMs: calculatePersistedTotalMs()
    readonly property bool hasFreshLease: leaseIsFresh(collectorLease, liveNowMs)
    readonly property bool hasFreshStatsLease: leaseIsFresh(collectorLease, statsNowMs)
    readonly property bool hasFreshLiveSession: {
        return TimeUtils.isPlainObject(liveSession)
            && hasFreshLease
            && collectorLease.ownerInstanceId === liveSession.ownerInstanceId;
    }
    readonly property bool hasFreshStatsLiveSession: {
        return TimeUtils.isPlainObject(liveSession)
            && hasFreshStatsLease
            && collectorLease.ownerInstanceId === liveSession.ownerInstanceId;
    }
    readonly property real todayLiveDeltaMs: {
        if (!hasFreshLiveSession || liveSession.dayKey !== todayKey)
            return 0;
        return Math.max(0, liveNowMs - Number(liveSession.startedAt || liveNowMs));
    }
    readonly property real todayTotalMs: todayPersistedMs + todayLiveDeltaMs
    readonly property real yesterdayTotalMs: calculateEntriesTotalMs(mergedYesterdayEntries)
    readonly property real overallTotalMs: retainedPersistedMs + todayLiveDeltaMs
    readonly property var overallEntries: buildOverallEntries(statsNowMs)
    readonly property var overallAppGroups: buildAppGroupsFromEntries(overallEntries)
    readonly property var yesterdayAppGroups: buildAppGroupsFromEntries(mergedYesterdayEntries)
    readonly property var todayAppGroups: buildAppGroupsFromEntries(mergedTodayEntries)
    readonly property var historyAppGroups: buildAppGroupsFromEntries(mergedHistoryEntries)
    readonly property var currentPeriodAppGroups: {
        if (selectedPeriod === "history")
            return historyAppGroups;
        if (selectedPeriod === "yesterday")
            return yesterdayAppGroups;
        if (selectedPeriod === "today")
            return todayAppGroups;
        return overallAppGroups;
    }
    readonly property var currentTopEntry: currentPeriodAppGroups.length > 0 ? currentPeriodAppGroups[0] : null
    readonly property bool canNavigateHistoryBack: clampedHistoryDayKey > historyMinDayKey
    readonly property bool canNavigateHistoryForward: clampedHistoryDayKey < todayKey

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
            headerText: root.translateText("focus_time")
            detailsText: root.translateText("popout_details")
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
                                    text: root.translateText("overall")
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
                                    text: root.translateText("yesterday")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    text: TimeUtils.formatDuration(root.yesterdayTotalMs)
                                    font.pixelSize: Theme.fontSizeLarge + 2
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                }
                            }

                            Column {
                                width: (parent.width - Theme.spacingM * 2) / 3
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: root.translateText("today")
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
                        }

                        Row {
                            id: periodTabsRow
                            width: parent.width
                            spacing: Theme.spacingS

                            Repeater {
                                model: root.periodTabs
                                delegate: StyledRect {
                                    property var tabData: modelData
                                    readonly property bool selected: root.selectedPeriod === tabData.key

                                    width: (periodTabsRow.width - periodTabsRow.spacing * Math.max(0, root.periodTabs.length - 1)) / root.periodTabs.length
                                    implicitHeight: tabLabel.implicitHeight + Theme.spacingS * 2
                                    radius: Theme.cornerRadius
                                    color: selected ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                                    StyledText {
                                        id: tabLabel
                                        anchors.centerIn: parent
                                        text: tabData.label
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: selected ? Font.DemiBold : Font.Normal
                                        color: selected ? Theme.primary : Theme.surfaceVariantText
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.setSelectedPeriod(tabData.key)
                                    }
                                }
                            }
                        }

                        StyledRect {
                            width: parent.width
                            visible: root.selectedPeriod === "history"
                            implicitHeight: historyNavRow.implicitHeight + Theme.spacingS * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainer

                            Row {
                                id: historyNavRow
                                x: Theme.spacingS
                                y: Theme.spacingS
                                width: parent.width - Theme.spacingS * 2
                                spacing: Theme.spacingS

                                StyledRect {
                                    width: 36
                                    height: 36
                                    radius: Theme.cornerRadius
                                    color: root.canNavigateHistoryBack ? Theme.surfaceContainerHigh : Theme.surfaceContainerHighest
                                    opacity: root.canNavigateHistoryBack ? 1 : 0.55

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: "<"
                                        font.pixelSize: Theme.fontSizeLarge
                                        font.weight: Font.DemiBold
                                        color: Theme.surfaceText
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: root.canNavigateHistoryBack
                                        onClicked: root.stepHistoryDay(-1)
                                    }
                                }

                                Column {
                                    width: Math.max(0, historyNavRow.width - 36 - 36 - historyNavRow.spacing * 2)
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        width: parent.width
                                        text: root.translateText("browse_date")
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: root.clampedHistoryDayKey
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.DemiBold
                                        color: Theme.surfaceText
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }

                                StyledRect {
                                    width: 36
                                    height: 36
                                    radius: Theme.cornerRadius
                                    color: root.canNavigateHistoryForward ? Theme.surfaceContainerHigh : Theme.surfaceContainerHighest
                                    opacity: root.canNavigateHistoryForward ? 1 : 0.55

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: ">"
                                        font.pixelSize: Theme.fontSizeLarge
                                        font.weight: Font.DemiBold
                                        color: Theme.surfaceText
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: root.canNavigateHistoryForward
                                        onClicked: root.stepHistoryDay(1)
                                    }
                                }
                            }
                        }

                        StyledText {
                            text: root.topPeriodSummaryText()
                            width: parent.width
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            maximumLineCount: 1
                            elide: Text.ElideRight
                        }
                    }
                }

                Loader {
                    width: parent.width
                    sourceComponent: root.currentPeriodAppGroups.length > 0 ? entriesListComponent : emptyStateComponent
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
                    text: root.currentEmptyTitleText()
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }

                StyledText {
                    text: root.currentEmptyHintText()
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
                    text: root.translateText("leaderboard")
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }

                StyledText {
                    text: root.currentLeaderboardHintText()
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
                            model: root.currentPeriodAppGroups
                            delegate: appGroupComponent
                        }
                    }
                }
            }
        }
    }

    Component {
        id: appGroupComponent

        Item {
            property var groupData: modelData

            width: parent ? parent.width : 0
            implicitHeight: groupColumn.implicitHeight

            Column {
                id: groupColumn
                width: parent.width
                spacing: Theme.spacingXS

                StyledRect {
                    width: parent.width
                    implicitHeight: contentRow.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: root.isAppGroupLive(groupData) ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

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
                                source: root.iconSourceForEntry(groupData)
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
                                    text: root.initialForEntry(groupData)
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
                                text: root.displayNameForAppGroup(groupData)
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                                maximumLineCount: 1
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            StyledText {
                                text: root.subtitleForAppGroup(groupData)
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
                            width: Math.max(durationText.implicitWidth, actionText.implicitWidth)
                            spacing: Theme.spacingXS

                            StyledText {
                                id: durationText
                                text: TimeUtils.formatDuration(groupData.totalMs)
                                font.pixelSize: Theme.fontSizeSmall + 1
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                                horizontalAlignment: Text.AlignRight
                                width: parent.width
                            }

                            StyledText {
                                id: actionText
                                text: root.isAppExpanded(groupData.appKey) ? root.translateText("collapse") : root.translateText("expand")
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.isAppGroupLive(groupData) ? Theme.primary : Theme.surfaceVariantText
                                horizontalAlignment: Text.AlignRight
                                width: parent.width
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.toggleAppExpanded(groupData.appKey)
                    }
                }

                Column {
                    width: parent.width - Theme.spacingL
                    x: Theme.spacingL
                    spacing: Theme.spacingXS

                    Repeater {
                        model: root.isAppExpanded(groupData.appKey) ? groupData.titles : []
                        delegate: titleDetailComponent
                    }
                }
            }
        }
    }

    Component {
        id: titleDetailComponent

        StyledRect {
            property var entryData: modelData

            width: parent ? parent.width : 0
            implicitHeight: detailRow.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: root.isLiveEntry(entryData) ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

            Row {
                id: detailRow
                x: Theme.spacingM
                y: Theme.spacingS
                width: parent.width - Theme.spacingM * 2
                spacing: Theme.spacingM

                StyledRect {
                    width: 10
                    height: 10
                    radius: 5
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.isLiveEntry(entryData) ? Theme.primary : Theme.outlineButton
                }

                Column {
                    width: Math.max(0, detailRow.width - 10 - detailDurationColumn.width - detailRow.spacing * 2)
                    spacing: Theme.spacingXS

                    StyledText {
                        text: root.displayTitleForEntry(entryData)
                        font.pixelSize: Theme.fontSizeSmall + 1
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    StyledText {
                        text: root.subtitleForTitleEntry(entryData)
                        visible: text.length > 0
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                Column {
                    id: detailDurationColumn
                    width: Math.max(detailDurationText.implicitWidth, detailLiveText.implicitWidth)
                    spacing: Theme.spacingXS

                    StyledText {
                        id: detailDurationText
                        text: TimeUtils.formatDuration(entryData.totalMs)
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignRight
                        width: parent.width
                    }

                    StyledText {
                        id: detailLiveText
                        text: root.isLiveEntry(entryData) ? root.translateText("live") : ""
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
    onSelectedPeriodChanged: {
        expandedApps = ({});
        if (selectedPeriod === "history")
            ensureHistoryDayKey();
    }
    onHistoryDayKeyChanged: {
        if (selectedPeriod === "history")
            expandedApps = ({});
    }
    onTodayKeyChanged: ensureHistoryDayKey()
    onRetentionDaysChanged: {
        daysState = TimeUtils.pruneDays(daysState, retentionDays, Date.now());
        ensureHistoryDayKey();
        if (isMaster)
            persistState("retention-change");
    }

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
        onTriggered: root.liveNowMs = Date.now()
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

    function touchStatsClock(referenceNow) {
        statsNowMs = Number(referenceNow || Date.now());
    }

    function refreshLeaseFromGlobal() {
        collectorLease = TimeUtils.cloneValue(PluginService.getGlobalVar(pluginId, leaseVarName, null));
    }

    function refreshLiveSessionFromGlobal() {
        liveSession = TimeUtils.cloneValue(PluginService.getGlobalVar(pluginId, liveSessionVarName, null));
        touchStatsClock();
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
        const currentSchemaVersion = PluginService.loadPluginState(pluginId, "schemaVersion", 0);
        if (currentSchemaVersion === stateSchemaVersion)
            return;

        const snapshotDays = TimeUtils.pruneDays(daysState, retentionDays, Date.now());
        daysState = snapshotDays;
        PluginService.savePluginState(pluginId, "days", snapshotDays);
        PluginService.savePluginState(pluginId, "schemaVersion", stateSchemaVersion);
    }

    function loadStateFromService() {
        if (!pluginId)
            return;

        const schemaVersion = PluginService.loadPluginState(pluginId, "schemaVersion", 0);
        const loadedDays = PluginService.loadPluginState(pluginId, "days", {});

        if (schemaVersion !== stateSchemaVersion || !TimeUtils.isPlainObject(loadedDays)) {
            daysState = ({});
            touchStatsClock();
            return;
        }

        daysState = TimeUtils.pruneDays(TimeUtils.cloneValue(loadedDays), retentionDays, Date.now());
        touchStatsClock();
    }

    function persistState(reason) {
        if (!pluginId || !isMaster)
            return;

        const snapshotDays = TimeUtils.pruneDays(daysState, retentionDays, Date.now());
        daysState = snapshotDays;
        PluginService.savePluginState(pluginId, "days", snapshotDays);
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
        touchStatsClock(endMs);
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
        touchStatsClock(referenceNow);
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

    function buildEntriesForDay(dayKey, referenceNow) {
        const day = TimeUtils.isPlainObject(daysState[dayKey]) ? TimeUtils.cloneValue(daysState[dayKey]) : {
            totalMs: 0,
            items: {}
        };
        const items = TimeUtils.isPlainObject(day.items) ? day.items : {};

        if (hasFreshStatsLiveSession && liveSession.dayKey === dayKey && liveSession.bucketKey) {
            const liveEntry = TimeUtils.isPlainObject(items[liveSession.bucketKey]) ? items[liveSession.bucketKey] : {
                appId: liveSession.appId,
                appName: liveSession.appName,
                title: liveSession.title,
                desktopEntryId: liveSession.desktopEntryId,
                totalMs: 0,
                lastSeenAt: referenceNow
            };

            liveEntry.appId = liveSession.appId;
            liveEntry.appName = liveSession.appName;
            liveEntry.title = liveSession.title;
            liveEntry.desktopEntryId = liveSession.desktopEntryId;
            liveEntry.totalMs = Number(liveEntry.totalMs || 0) + Math.max(0, referenceNow - Number(liveSession.startedAt || referenceNow));
            liveEntry.lastSeenAt = referenceNow;
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
        if (hasFreshStatsLiveSession && keys.indexOf(todayKey) === -1)
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

    function buildOverallEntries(referenceNow) {
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

        if (hasFreshStatsLiveSession && liveSession.bucketKey) {
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
            aggregate[liveSession.bucketKey].totalMs += Math.max(0, referenceNow - Number(liveSession.startedAt || referenceNow));
            aggregate[liveSession.bucketKey].lastSeenAt = Math.max(aggregate[liveSession.bucketKey].lastSeenAt, referenceNow);
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

    function normalizedLanguageMode(value) {
        return value === "zh" || value === "en" ? value : "system";
    }

    function normalizedDefaultView(value) {
        return value === "history" || value === "yesterday" || value === "today" ? value : "overall";
    }

    function normalizedRetentionDays(value) {
        const numericValue = Math.round(Number(value || 30));
        if (!isFinite(numericValue))
            return 30;
        return Math.max(7, Math.min(90, numericValue));
    }

    function previousDayKey(referenceMs) {
        const date = new Date(referenceMs);
        date.setHours(0, 0, 0, 0);
        date.setDate(date.getDate() - 1);
        return TimeUtils.dayKeyFromMs(date.getTime());
    }

    function dayKeyToDate(dayKey) {
        const parts = (dayKey || "").split("-");
        if (parts.length !== 3)
            return new Date();

        return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 0, 0, 0, 0);
    }

    function shiftDayKey(dayKey, offsetDays) {
        const date = dayKeyToDate(dayKey);
        date.setDate(date.getDate() + offsetDays);
        return TimeUtils.dayKeyFromMs(date.getTime());
    }

    function suggestedHistoryDayKey() {
        const keys = retainedDayKeys;
        if (keys.indexOf(yesterdayKey) !== -1)
            return yesterdayKey;
        if (keys.length > 0)
            return keys[keys.length - 1];
        return yesterdayKey;
    }

    function clampHistoryDayKey(dayKey) {
        let key = dayKey || suggestedHistoryDayKey();
        if (key < historyMinDayKey)
            key = historyMinDayKey;
        if (key > todayKey)
            key = todayKey;
        return key;
    }

    function ensureHistoryDayKey() {
        const normalized = clampHistoryDayKey(historyDayKey);
        if (normalized !== historyDayKey)
            historyDayKey = normalized;
    }

    function setSelectedPeriod(periodKey) {
        if (selectedPeriod === periodKey)
            return;
        if (periodKey === "history")
            ensureHistoryDayKey();
        selectedPeriod = periodKey;
    }

    function stepHistoryDay(offsetDays) {
        const nextKey = clampHistoryDayKey(shiftDayKey(clampedHistoryDayKey, offsetDays));
        if (nextKey === clampedHistoryDayKey)
            return;
        historyDayKey = nextKey;
    }

    function calculateEntriesTotalMs(entries) {
        let total = 0;
        const source = Array.isArray(entries) ? entries : [];

        for (let i = 0; i < source.length; i++)
            total += Number(source[i].totalMs || 0);

        return total;
    }

    function buildAppGroupsFromEntries(entries) {
        const aggregate = {};
        const source = Array.isArray(entries) ? entries : [];

        for (let i = 0; i < source.length; i++) {
            const entry = source[i];
            const appKey = entry.appId || entry.appName || entry.title || entry.bucketKey;

            if (!TimeUtils.isPlainObject(aggregate[appKey])) {
                aggregate[appKey] = {
                    appKey: appKey,
                    appId: entry.appId || "",
                    appName: entry.appName || "",
                    title: entry.title || entry.appName || "Untitled Window",
                    desktopEntryId: entry.desktopEntryId || "",
                    totalMs: 0,
                    lastSeenAt: 0,
                    titleCount: 0,
                    titles: []
                };
            }

            aggregate[appKey].appId = entry.appId || aggregate[appKey].appId;
            aggregate[appKey].appName = entry.appName || aggregate[appKey].appName;
            aggregate[appKey].title = aggregate[appKey].title || entry.title || entry.appName || "Untitled Window";
            aggregate[appKey].desktopEntryId = entry.desktopEntryId || aggregate[appKey].desktopEntryId;
            aggregate[appKey].totalMs += Number(entry.totalMs || 0);
            aggregate[appKey].lastSeenAt = Math.max(aggregate[appKey].lastSeenAt, Number(entry.lastSeenAt || 0));
            aggregate[appKey].titles.push(entry);
        }

        const groups = [];
        for (const appKey in aggregate) {
            const group = aggregate[appKey];
            if (group.totalMs <= 0)
                continue;

            group.titles.sort(function (left, right) {
                if (left.totalMs !== right.totalMs)
                    return right.totalMs - left.totalMs;
                if (left.lastSeenAt !== right.lastSeenAt)
                    return right.lastSeenAt - left.lastSeenAt;
                return left.title.localeCompare(right.title);
            });
            group.titleCount = group.titles.length;
            groups.push(group);
        }

        groups.sort(function (left, right) {
            if (left.totalMs !== right.totalMs)
                return right.totalMs - left.totalMs;
            if (left.lastSeenAt !== right.lastSeenAt)
                return right.lastSeenAt - left.lastSeenAt;
            return root.displayNameForAppGroup(left).localeCompare(root.displayNameForAppGroup(right));
        });

        return groups;
    }

    function translateText(key, params) {
        const languageCatalog = TimeUtils.isPlainObject(i18nCatalog[uiLanguageCode]) ? i18nCatalog[uiLanguageCode] : i18nCatalog.en;
        let text = languageCatalog[key];
        if (text === undefined && TimeUtils.isPlainObject(i18nCatalog.en))
            text = i18nCatalog.en[key];
        if (text === undefined)
            return key;

        if (!TimeUtils.isPlainObject(params))
            return text;

        let rendered = text;
        for (const name in params)
            rendered = rendered.replace("{" + name + "}", String(params[name]));
        return rendered;
    }

    function currentPeriodLabel() {
        if (selectedPeriod === "history")
            return clampedHistoryDayKey;
        if (selectedPeriod === "yesterday")
            return translateText("yesterday");
        if (selectedPeriod === "today")
            return translateText("today");
        return translateText("overall");
    }

    function currentLeaderboardHintText() {
        if (selectedPeriod === "overall") {
            return translateText("leaderboard_overall_hint", {
                days: retentionDays
            });
        }

        return translateText("leaderboard_period_hint", {
            period: currentPeriodLabel()
        });
    }

    function currentEmptyTitleText() {
        if (selectedPeriod === "overall")
            return translateText("nothing_to_show");

        return translateText("nothing_to_show_period", {
            period: currentPeriodLabel()
        });
    }

    function currentEmptyHintText() {
        if (selectedPeriod === "overall")
            return translateText("empty_hint");

        return translateText("empty_hint_period");
    }

    function topPeriodSummaryText() {
        if (!currentTopEntry) {
            if (selectedPeriod === "overall")
                return translateText("no_focus_time");
            return translateText("no_focus_time_period", {
                period: currentPeriodLabel()
            });
        }

        if (selectedPeriod === "overall") {
            return translateText("top_app_overall", {
                app: displayNameForAppGroup(currentTopEntry),
                duration: TimeUtils.formatDuration(currentTopEntry.totalMs)
            });
        }

        return translateText("top_app", {
            period: currentPeriodLabel(),
            app: displayNameForAppGroup(currentTopEntry),
            duration: TimeUtils.formatDuration(currentTopEntry.totalMs)
        });
    }

    function formatTitlesLabel(count) {
        if (count === 1)
            return translateText("one_title");
        return translateText("many_titles", {
            count: count
        });
    }

    function formatDaysLabel(count) {
        if (count === 1)
            return translateText("one_day");
        return translateText("many_days", {
            count: count
        });
    }

    function isLiveEntry(entry) {
        return hasFreshLiveSession
            && TimeUtils.isPlainObject(entry)
            && entry.bucketKey === liveSession.bucketKey;
    }

    function isAppGroupLive(group) {
        if (!hasFreshLiveSession || !TimeUtils.isPlainObject(group) || !group.titles)
            return false;

        for (let i = 0; i < group.titles.length; i++) {
            if (isLiveEntry(group.titles[i]))
                return true;
        }

        return false;
    }

    function isAppExpanded(appKey) {
        return !!(expandedApps && expandedApps[appKey]);
    }

    function toggleAppExpanded(appKey) {
        const nextExpanded = TimeUtils.cloneValue(expandedApps) || {};
        nextExpanded[appKey] = !nextExpanded[appKey];
        expandedApps = nextExpanded;
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
        const appName = displayAppNameForEntry(entry);
        if (appName.length > 0)
            return appName.charAt(0).toUpperCase();
        const title = displayTitleForEntry(entry);
        return title.length > 0 ? title.charAt(0).toUpperCase() : "?";
    }

    function displayTitleForEntry(entry) {
        if (!entry)
            return translateText("untitled_window");

        const title = entry.title ? entry.title.toString().trim() : "";
        if (title.length > 0 && title !== "Untitled Window" && title !== "Unknown Window")
            return title;

        const appName = entry.appName ? entry.appName.toString().trim() : "";
        if (appName.length > 0 && appName !== "Unknown App")
            return appName;

        return translateText("untitled_window");
    }

    function displayAppNameForEntry(entry) {
        if (!entry)
            return translateText("unknown_app");

        const appName = entry.appName ? entry.appName.toString().trim() : "";
        if (appName.length > 0 && appName !== "Unknown App")
            return appName;

        const title = entry.title ? entry.title.toString().trim() : "";
        if (title.length > 0 && title !== "Untitled Window" && title !== "Unknown Window")
            return title;

        if (entry.appId)
            return entry.appId;

        return translateText("unknown_app");
    }

    function displayNameForAppGroup(group) {
        if (!group)
            return translateText("unknown_app");
        return displayAppNameForEntry(group);
    }

    function subtitleForAppGroup(group) {
        if (!group)
            return "";

        const parts = [];
        if (group.titleCount > 0)
            parts.push(formatTitlesLabel(group.titleCount));
        if (group.appId && group.appId !== group.appName)
            parts.push(group.appId);
        return parts.join(" • ");
    }

    function subtitleForTitleEntry(entry) {
        if (!entry)
            return "";

        const parts = [];
        if (entry.dayCount && entry.dayCount > 1)
            parts.push(formatDaysLabel(entry.dayCount));
        if (entry.appName && entry.appName !== entry.title)
            parts.push(displayAppNameForEntry(entry));
        return parts.join(" • ");
    }

    function subtitleForEntry(entry) {
        if (!entry)
            return "";
        const parts = [];
        if (entry.appName && entry.appName !== entry.title)
            parts.push(displayAppNameForEntry(entry));
        if (entry.dayCount && entry.dayCount > 1)
            parts.push(formatDaysLabel(entry.dayCount));
        return parts.join(" • ");
    }
}
