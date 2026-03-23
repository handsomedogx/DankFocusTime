.pragma library

function cloneValue(value) {
    if (value === undefined)
        return undefined;
    return JSON.parse(JSON.stringify(value));
}

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function pad2(value) {
    return value < 10 ? "0" + value : "" + value;
}

function dayKeyFromMs(ms) {
    const date = new Date(ms);
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate());
}

function nextDayStartMs(ms) {
    const date = new Date(ms);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1, 0, 0, 0, 0).getTime();
}

function retentionThresholdKey(retentionDays, nowMs) {
    const date = new Date(nowMs);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() - (retentionDays - 1));
    return dayKeyFromMs(date.getTime());
}

function pruneDays(days, retentionDays, nowMs) {
    const source = isPlainObject(days) ? days : {};
    const thresholdKey = retentionThresholdKey(retentionDays, nowMs);
    const result = {};
    const keys = Object.keys(source).sort();

    for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const day = source[key];

        if (key < thresholdKey || !isPlainObject(day))
            continue;

        const items = isPlainObject(day.items) ? cloneValue(day.items) : {};
        result[key] = {
            totalMs: Number(day.totalMs || 0),
            items: items
        };
    }

    return result;
}

function formatDuration(ms) {
    let totalSeconds = Math.floor(Math.max(0, Number(ms || 0)) / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    totalSeconds -= hours * 3600;
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds - minutes * 60;
    const parts = [];

    if (hours > 0)
        parts.push(hours + "h");

    if (minutes > 0 || hours > 0)
        parts.push(minutes + "m");

    if (hours === 0 && minutes === 0)
        parts.push(seconds + "s");

    return parts.join(" ");
}
