.pragma library

function keys(value) {
    return Object.keys(value).filter(key => key !== "objectName" && !key.endsWith("Changed")
        && typeof value[key] !== "function");
}

function isList(value) {
    return Array.isArray(value) || (value !== null && typeof value === "object"
        && typeof value.slice === "function" && typeof value.length === "number");
}

function copy(value) {
    if (isList(value)) {
        const result = [];
        for (let i = 0; i < value.length; i++) result.push(copy(value[i]));
        return result;
    }
    if (value !== null && typeof value === "object") {
        const result = {};
        for (const key of keys(value)) result[key] = copy(value[key]);
        return result;
    }
    return value;
}

function assign(source, target) {
    if (!source || !target) return;
    const allowed = keys(target);
    for (const key of keys(source)) {
        const value = source[key];
        if (!allowed.includes(key) || value === undefined) continue;
        if (value !== null && typeof value === "object" && !isList(value)
            && target[key] !== null && typeof target[key] === "object" && !isList(target[key])) {
            assign(value, target[key]);
        } else {
            target[key] = copy(value);
        }
    }
}
