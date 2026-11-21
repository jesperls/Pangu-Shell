.pragma library

function clamp(v, lo, hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

// QML passes QVariantList/sequence values whose Array.isArray() is false.
function asList(value) {
    if (!value || typeof value === "string")
        return [];
    if (Array.isArray(value))
        return value;
    if (typeof value.length === "number") {
        const out = [];
        for (let i = 0; i < value.length; i++)
            out.push(value[i]);
        return out;
    }
    return [];
}

function pairOf(value) {
    if (!value || typeof value === "string" || typeof value.length !== "number" || value.length < 2)
        return null;
    const a = Number(value[0]);
    const b = Number(value[1]);
    if (!Number.isFinite(a) || !Number.isFinite(b))
        return null;
    return [a, b];
}

function luaQuote(value) {
    return '"' + String(value || "").replace(/["\\\u0000-\u001f\u007f]/g, c => {
        if (c === '"' || c === "\\")
            return "\\" + c;
        return "\\" + String(c.charCodeAt(0)).padStart(3, "0");
    }) + '"';
}

function effectiveTabletAspect(maxX, maxY, rotation) {
    const w = maxX > 0 ? maxX : 20832;
    const h = maxY > 0 ? maxY : 15624;
    const rot = ((Number(rotation) || 0) % 360 + 360) % 360;
    return (rot === 90 || rot === 270) ? (h / w) : (w / h);
}

function findMonitor(monitors, name, focusedMonitor) {
    const list = asList(monitors);
    if (name) {
        const hit = list.find(m => m && m.name === name);
        if (hit)
            return hit;
    }
    if (focusedMonitor) {
        const hit = list.find(m => m && m.name === focusedMonitor.name);
        if (hit)
            return hit;
        if (focusedMonitor.name)
            return focusedMonitor;
    }
    return list.length > 0 ? list[0] : null;
}

function monitorDimensions(mon) {
    if (!mon)
        return { x: 0, y: 0, w: 1920, h: 1080 };
    const w = Number(mon.logicalWidth || mon.width || 1920);
    const h = Number(mon.logicalHeight || mon.height || 1080);
    return { x: Number(mon.x || 0), y: Number(mon.y || 0), w: Math.max(1, w), h: Math.max(1, h) };
}

function monitorContainingPoint(monitors, px, py) {
    const list = asList(monitors);
    for (let i = 0; i < list.length; i++) {
        const m = list[i];
        const d = monitorDimensions(m);
        if (px >= d.x && px < d.x + d.w && py >= d.y && py < d.y + d.h)
            return m;
    }
    return null;
}

function findTrackedWindow(cfg, clients, focusedClient) {
    const list = asList(clients);
    const addr = String(cfg?.windowAddress || "");
    const cls = String(cfg?.windowClass || "");

    if (!addr && !cls) {
        if (focusedClient && focusedClient.mapped !== false && !focusedClient.hidden && focusedClient.title !== "Pangu Settings")
            return focusedClient;
        const focused = list.find(c => c && c.is_focused && c.mapped !== false && !c.hidden && c.title !== "Pangu Settings");
        if (focused)
            return focused;
        return null;
    }

    if (addr) {
        const exact = list.find(c => c && String(c.address || "") === addr && c.mapped !== false && !c.hidden);
        if (exact)
            return exact;
    }
    if (cls && cfg?.followWindow !== false) {
        const byClass = list.find(c => c && String(c["class"] || "") === cls && c.mapped !== false && !c.hidden);
        if (byClass)
            return byClass;
    }
    return null;
}

function finiteOr(value, fallback) {
    if (value === undefined || value === null || value === "")
        return fallback;
    const n = Number(value);
    return Number.isFinite(n) ? n : fallback;
}

function resolveTargetRegion(cfg, monitors, clients, focusedMonitor, gaps, tabletAspect, focusedClient) {
    const monitorList = asList(monitors);
    const mode = String(cfg?.targetMode || "centered");
    const baseMon = findMonitor(monitorList, cfg?.monitor || "", focusedMonitor);
    const baseDim = monitorDimensions(baseMon);

    let gx = baseDim.x;
    let gy = baseDim.y;
    let gw = baseDim.w;
    let gh = baseDim.h;
    let boundMon = baseMon;
    let windowFound = false;
    let label = baseMon ? baseMon.name : "Desktop";

    if (mode === "screen") {
        label = (baseMon ? baseMon.name : "Screen") + " · Full";
    } else if (mode === "centered") {
        const gap = (cfg?.centeredMatchLayout && baseMon && gaps && gaps[baseMon.name]) ? gaps[baseMon.name] : null;
        if (gap && Number(gap.width) > 0) {
            gw = Math.min(baseDim.w, Math.max(64, Math.round(Number(gap.width))));
            gh = baseDim.h;
            gx = baseDim.x + Math.round(finiteOr(gap.x, 0));
            gy = baseDim.y;
            label = (baseMon ? baseMon.name : "Screen") + " · Centered Layout";
        } else {
            gw = Math.min(baseDim.w, Math.max(64, Math.round(finiteOr(cfg?.centeredWidth, 2560))));
            gh = Math.min(baseDim.h, Math.max(64, Math.round(finiteOr(cfg?.centeredHeight, 1440))));
            gx = baseDim.x + Math.round((baseDim.w - gw) / 2);
            gy = baseDim.y + Math.round((baseDim.h - gh) / 2);
            label = (baseMon ? baseMon.name : "Screen") + " · Centered";
        }
    } else if (mode === "area") {
        gx = Math.round(finiteOr(cfg?.areaX, 0));
        gy = Math.round(finiteOr(cfg?.areaY, 0));
        gw = Math.max(32, Math.round(finiteOr(cfg?.areaWidth, 2560)));
        gh = Math.max(32, Math.round(finiteOr(cfg?.areaHeight, 1440)));
        boundMon = monitorContainingPoint(monitorList, gx + gw / 2, gy + gh / 2) || baseMon;
        label = "Custom Area";
    } else if (mode === "window") {
        const win = findTrackedWindow(cfg, clients, focusedClient);
        const at = win ? pairOf(win.at) : null;
        const size = win ? pairOf(win.size) : null;
        if (win && at && size && size[0] > 0 && size[1] > 0) {
            windowFound = true;
            gx = Math.round(at[0]);
            gy = Math.round(at[1]);
            gw = Math.max(32, Math.round(size[0]));
            gh = Math.max(32, Math.round(size[1]));
            boundMon = monitorContainingPoint(monitorList, gx + gw / 2, gy + gh / 2) || baseMon;
            label = win.title || win["class"] || "Window";
        } else {
            gx = Math.round(finiteOr(cfg?.areaX, baseDim.x));
            gy = Math.round(finiteOr(cfg?.areaY, baseDim.y));
            gw = Math.max(32, Math.round(finiteOr(cfg?.areaWidth, Math.min(baseDim.w, 2560))));
            gh = Math.max(32, Math.round(finiteOr(cfg?.areaHeight, Math.min(baseDim.h, 1440))));
            boundMon = monitorContainingPoint(monitorList, gx + gw / 2, gy + gh / 2) || baseMon;
            const followFocus = !cfg?.windowAddress && !cfg?.windowClass;
            label = followFocus ? "Focused Window" : ((cfg?.windowTitle || cfg?.windowClass || "Window") + " (not open)");
        }
    }

    const aspectMode = String(cfg?.aspectMode || "fit-tablet");
    const tAspect = Number(tabletAspect) > 0 ? Number(tabletAspect) : (4 / 3);
    if (aspectMode === "fit-screen" && gw > 0 && gh > 0) {
        const curAspect = gw / gh;
        if (curAspect > tAspect) {
            const nextW = Math.max(32, Math.round(gh * tAspect));
            gx = gx + Math.round((gw - nextW) / 2);
            gw = nextW;
        } else if (curAspect < tAspect) {
            const nextH = Math.max(32, Math.round(gw / tAspect));
            gy = gy + Math.round((gh - nextH) / 2);
            gh = nextH;
        }
    }

    const monDim = monitorDimensions(boundMon);
    const fitsSingleMonitor = boundMon !== null
        && gx >= monDim.x - 2
        && gy >= monDim.y - 2
        && (gx + gw) <= (monDim.x + monDim.w + 2)
        && (gy + gh) <= (monDim.y + monDim.h + 2);

    const output = fitsSingleMonitor ? boundMon.name : "";
    const absolutePosition = !fitsSingleMonitor;
    const regionX = fitsSingleMonitor ? Math.max(0, Math.round(gx - monDim.x)) : Math.round(gx);
    const regionY = fitsSingleMonitor ? Math.max(0, Math.round(gy - monDim.y)) : Math.round(gy);
    const regionWidth = Math.max(1, Math.round(gw));
    const regionHeight = Math.max(1, Math.round(gh));

    return {
        valid: baseMon !== null || monitorList.length === 0,
        mode: mode,
        output: output,
        absolutePosition: absolutePosition,
        regionX: regionX,
        regionY: regionY,
        regionWidth: regionWidth,
        regionHeight: regionHeight,
        globalX: Math.round(gx),
        globalY: Math.round(gy),
        width: regionWidth,
        height: regionHeight,
        targetAspect: regionWidth / regionHeight,
        monitorName: boundMon ? boundMon.name : "",
        monitorX: monDim.x,
        monitorY: monDim.y,
        monitorWidth: monDim.w,
        monitorHeight: monDim.h,
        windowFound: windowFound,
        label: label
    };
}

function buildHyprlandLua(region, relativeMode) {
    if (!region)
        return "";
    const out = luaQuote(region.output || "");
    const absPos = region.absolutePosition ? "true" : "false";
    const rel = relativeMode ? "true" : "false";
    const rx = Math.round(region.regionX || 0);
    const ry = Math.round(region.regionY || 0);
    const rw = Math.max(0, Math.round(region.regionWidth || 0));
    const rh = Math.max(0, Math.round(region.regionHeight || 0));
    return `hl.config({ input = { tablet = { output = ${out}, absolute_region_position = ${absPos}, region_position = { ${rx}, ${ry} }, region_size = { ${rw}, ${rh} }, relative_input = ${rel} } } })`;
}

function buildHyprlandTouchpadLua(cfg) {
    if (!cfg)
        return "";
    const accel = cfg.touchpadAccelProfile === "flat" ? "flat" : "adaptive";
    const naturalScroll = cfg.touchpadNaturalScroll !== false ? "true" : "false";
    const tapToClick = cfg.touchpadTapToClick !== false ? "true" : "false";
    const tapAndDrag = cfg.touchpadTapAndDrag !== false ? "true" : "false";
    const dwt = Boolean(cfg.touchpadDisableWhileTyping) ? "true" : "false";
    const scrollFactor = clamp(finiteOr(cfg.touchpadScrollFactor, 1.0), 0.2, 3.0).toFixed(2);
    const drag3fg = Math.max(0, Math.min(2, Math.round(finiteOr(cfg.touchpadDrag3fg, 0))));
    return `hl.device({ name = "pangu-android-tablet-touchpad", accel_profile = ${luaQuote(accel)}, natural_scroll = ${naturalScroll}, tap_to_click = ${tapToClick}, tap_and_drag = ${tapAndDrag}, scroll_factor = ${scrollFactor}, drag_3fg = ${drag3fg}, disable_while_typing = ${dwt} })`;
}

function computeActiveRect(tabletAspect, areaScale, offsetX, offsetY, aspectMode, targetAspect) {
    const effAspect = Number(tabletAspect) > 0 ? Number(tabletAspect) : (4 / 3);
    let boxW = 1.0;
    let boxH = 1.0;
    if (aspectMode === "fit-tablet" && Number(targetAspect) > 0) {
        if (targetAspect > effAspect)
            boxH = effAspect / targetAspect;
        else if (targetAspect < effAspect)
            boxW = targetAspect / effAspect;
    }
    const scale = clamp(Number(areaScale) || 1.0, 0.25, 1.0);
    boxW = clamp(boxW * scale, 0.05, 1.0);
    boxH = clamp(boxH * scale, 0.05, 1.0);
    const cx = clamp(0.5 + clamp(Number(offsetX) || 0, -0.5, 0.5), boxW * 0.5, 1.0 - boxW * 0.5);
    const cy = clamp(0.5 + clamp(Number(offsetY) || 0, -0.5, 0.5), boxH * 0.5, 1.0 - boxH * 0.5);
    return {
        x: cx - boxW * 0.5,
        y: cy - boxH * 0.5,
        width: boxW,
        height: boxH
    };
}

function evaluatePressure(raw, enabled, gamma, minP, maxP) {
    const p = clamp(Number(raw) || 0, 0, 1);
    if (!enabled)
        return p > 0 ? 1 : 0;
    const lo = clamp(Number(minP) || 0, 0, 0.45);
    const hi = Math.max(lo + 0.05, clamp(Number(maxP) || 1, 0.3, 1.0));
    if (p <= lo)
        return 0;
    const norm = clamp((p - lo) / (hi - lo), 0, 1);
    return Math.pow(norm, clamp(Number(gamma) || 1, 0.25, 3.0));
}
