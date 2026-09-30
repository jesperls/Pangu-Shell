
function isUrl(text) {
    if (!text) return false;
    var trimmed = text.trim();
    return /^https?:\/\/[^\s]+/.test(trimmed);
}

function getGoogleFaviconUrl(domain) {
    if (!domain) return "";
    return "https://www.google.com/s2/favicons?domain=" + encodeURIComponent(domain) + "&sz=64";
}

function getFaviconUrl(text) {
    if (!text) return "";
    try {
        var trimmed = text.trim();
        var url = new URL(trimmed);
        return url.origin + "/favicon.ico";
    } catch (e) {
        return "";
    }
}

function getFaviconFallbackUrl(text) {
    if (!text) return "";
    try {
        var trimmed = text.trim();
        var url = new URL(trimmed);
        return getGoogleFaviconUrl(url.hostname);
    } catch (e) {
        return "";
    }
}

function escapeShellArg(arg) {
    if (arg === null || arg === undefined) return "''";
    return "'" + arg.toString().replace(/'/g, "'\\''") + "'";
}
