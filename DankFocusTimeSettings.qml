import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "dankFocusTime"

    property string languageMode: "system"
    property bool settingsSyncScheduled: false
    readonly property bool idleMonitorAvailable: {
        try {
            return typeof IdleMonitor !== "undefined";
        } catch (error) {
            return false;
        }
    }

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
            title: "Focus Time Settings",
            subtitle: "Adjust popout defaults, local history retention, and which low-quality focus segments should be ignored.",
            behavior_title: "Display Behavior",
            behavior_subtitle: "Choose how the widget opens and which language the popout uses.",
            storage_title: "History Retention",
            storage_subtitle: "Retention affects runtime state only. Older retained days are pruned on the next save.",
            filters_title: "Tracking Filters",
            filters_subtitle: "Ignore very short focus slices and stop counting after you have been idle for a while.",
            language_mode: "Language",
            language_mode_desc: "Use the system locale or force the widget UI to English or Chinese.",
            language_system: "Follow System",
            language_en: "English",
            language_zh: "Chinese",
            default_view: "Default View",
            default_view_desc: "Choose which popout section opens first before you switch manually.",
            view_overall: "Overall",
            view_history: "History",
            view_yesterday: "Yesterday",
            view_today: "Today",
            retention_days: "Retention Days",
            retention_days_desc: "Keep between 7 and 90 days of retained focus history in plugin state.",
            minimum_focus_seconds: "Minimum Focus Seconds",
            minimum_focus_seconds_desc: "Focus changes shorter than this are ignored. Set to 0 to record everything.",
            idle_timeout_seconds: "Idle Timeout",
            idle_timeout_seconds_desc: "After this many seconds without input, focus timing pauses from the last active moment. Set to 0 to disable idle filtering.",
            idle_monitor_unavailable: "Idle filtering is unavailable on this system because the current Quickshell build does not expose IdleMonitor."
        },
        zh: {
            title: "专注时长设置",
            subtitle: "调整弹窗默认行为、本地历史保留时长，以及需要忽略的低质量聚焦片段。",
            behavior_title: "显示行为",
            behavior_subtitle: "设置弹窗默认打开的视图，以及使用哪种语言显示。",
            storage_title: "历史保留",
            storage_subtitle: "这个设置只影响运行时统计数据。更早的数据会在下一次保存时被裁剪。",
            filters_title: "统计过滤",
            filters_subtitle: "忽略非常短的聚焦片段，并在长时间无输入后暂停计时。",
            language_mode: "语言",
            language_mode_desc: "可以跟随系统语言，或者强制使用中文/英文。",
            language_system: "跟随系统",
            language_en: "英文",
            language_zh: "中文",
            default_view: "默认视图",
            default_view_desc: "设置弹窗首次打开时默认显示哪个区域，之后仍可手动切换。",
            view_overall: "总计",
            view_history: "历史",
            view_yesterday: "昨天",
            view_today: "今天",
            retention_days: "保留天数",
            retention_days_desc: "在插件 state 中保留 7 到 90 天的专注历史。",
            minimum_focus_seconds: "最短记录秒数",
            minimum_focus_seconds_desc: "比这个更短的聚焦切换会被忽略。设置为 0 表示全部记录。",
            idle_timeout_seconds: "空闲超时",
            idle_timeout_seconds_desc: "无输入达到这个秒数后，会从最后活跃时刻起暂停专注计时。设置为 0 可关闭空闲过滤。",
            idle_monitor_unavailable: "当前系统上的 Quickshell 没有暴露 IdleMonitor，因此无法启用空闲过滤。"
        }
    })

    readonly property var languageOptions: ([
        { label: translateText("language_system"), value: "system" },
        { label: translateText("language_en"), value: "en" },
        { label: translateText("language_zh"), value: "zh" }
    ])

    readonly property var defaultViewOptions: ([
        { label: translateText("view_overall"), value: "overall" },
        { label: translateText("view_history"), value: "history" },
        { label: translateText("view_yesterday"), value: "yesterday" },
        { label: translateText("view_today"), value: "today" }
    ])

    Component.onCompleted: scheduleSettingsSync()
    onPluginServiceChanged: scheduleSettingsSync()
    onPluginIdChanged: scheduleSettingsSync()
    onSettingChanged: scheduleSettingsSync()

    function refreshLanguageMode() {
        languageMode = loadValue("languageMode", "system");
    }

    function syncStoredSettings() {
        refreshLanguageMode();
        reloadNestedSettingValues(settingsColumn);
    }

    function runScheduledSettingsSync() {
        settingsSyncScheduled = false;
        syncStoredSettings();
    }

    function scheduleSettingsSync() {
        if (settingsSyncScheduled)
            return;

        settingsSyncScheduled = true;
        Qt.callLater(runScheduledSettingsSync);
    }

    function reloadNestedSettingValues(item) {
        if (!item)
            return;

        const childItems = item.children || [];
        for (let i = 0; i < childItems.length; i++) {
            const child = childItems[i];
            if (child && typeof child.loadValue === "function")
                child.loadValue();
            reloadNestedSettingValues(child);
        }
    }

    function translateText(key) {
        const languageCatalog = i18nCatalog[uiLanguageCode] || i18nCatalog.en;
        return languageCatalog[key] || i18nCatalog.en[key] || key;
    }

    Connections {
        target: root.pluginService
        enabled: root.pluginService !== null

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.scheduleSettingsSync();
        }
    }

    StyledText {
        width: parent.width
        text: root.translateText("title")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: root.translateText("subtitle")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        implicitHeight: behaviorColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: behaviorColumn
            x: Theme.spacingL
            y: Theme.spacingL
            width: parent.width - Theme.spacingL * 2
            spacing: Theme.spacingM

            StyledText {
                width: parent.width
                text: root.translateText("behavior_title")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: root.translateText("behavior_subtitle")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            SelectionSetting {
                settingKey: "languageMode"
                label: root.translateText("language_mode")
                description: root.translateText("language_mode_desc")
                options: root.languageOptions
                defaultValue: "system"
            }

            SelectionSetting {
                settingKey: "defaultView"
                label: root.translateText("default_view")
                description: root.translateText("default_view_desc")
                options: root.defaultViewOptions
                defaultValue: "overall"
            }
        }
    }

    StyledRect {
        width: parent.width
        implicitHeight: storageColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: storageColumn
            x: Theme.spacingL
            y: Theme.spacingL
            width: parent.width - Theme.spacingL * 2
            spacing: Theme.spacingM

            StyledText {
                width: parent.width
                text: root.translateText("storage_title")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: root.translateText("storage_subtitle")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            SliderSetting {
                settingKey: "retentionDays"
                label: root.translateText("retention_days")
                description: root.translateText("retention_days_desc")
                defaultValue: 30
                minimum: 7
                maximum: 90
                unit: root.uiLanguageCode === "zh" ? "天" : "d"
            }
        }
    }

    StyledRect {
        width: parent.width
        implicitHeight: filtersColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: filtersColumn
            x: Theme.spacingL
            y: Theme.spacingL
            width: parent.width - Theme.spacingL * 2
            spacing: Theme.spacingM

            StyledText {
                width: parent.width
                text: root.translateText("filters_title")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: root.translateText("filters_subtitle")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            SliderSetting {
                settingKey: "minimumFocusSeconds"
                label: root.translateText("minimum_focus_seconds")
                description: root.translateText("minimum_focus_seconds_desc")
                defaultValue: 2
                minimum: 0
                maximum: 10
                unit: root.uiLanguageCode === "zh" ? "秒" : "s"
            }

            SliderSetting {
                settingKey: "idleThresholdSeconds"
                label: root.translateText("idle_timeout_seconds")
                description: root.translateText("idle_timeout_seconds_desc")
                defaultValue: 60
                minimum: 0
                maximum: 300
                unit: root.uiLanguageCode === "zh" ? "秒" : "s"
            }

            StyledText {
                width: parent.width
                visible: !root.idleMonitorAvailable
                text: root.translateText("idle_monitor_unavailable")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                wrapMode: Text.WordWrap
            }
        }
    }
}
