
function generateUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        var r = Math.random() * 16 | 0;
        var v = c === 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

function getCurrentTimestamp() {
    return new Date().toISOString();
}

function formatTimestamp(isoTimestamp) {
    if (!isoTimestamp) return "";
    try {
        var date = new Date(isoTimestamp);
        var now = new Date();
        var diffMs = now - date;
        var diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
        
        if (diffDays === 0) {
            return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        } else if (diffDays === 1) {
            return "Yesterday";
        } else if (diffDays < 7) {
            return diffDays + " days ago";
        } else {
            return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
        }
    } catch (e) {
        return "";
    }
}

function parseIndex(jsonString) {
    try {
        var data = JSON.parse(jsonString);
        return {
            order: data.order || [],
            notes: data.notes || {}
        };
    } catch (e) {
        return {
            order: [],
            notes: {}
        };
    }
}

function serializeIndex(indexData) {
    return JSON.stringify(indexData, null, 2);
}

function filterNotes(notes, searchText) {
    if (!searchText || searchText.length === 0) {
        return notes;
    }
    
    var query = searchText.toLowerCase();
    return notes.filter(function(note) {
        var title = (note.title || "").toLowerCase();
        var content = (note.content || "").toLowerCase();
        return title.indexOf(query) !== -1 || content.indexOf(query) !== -1;
    });
}

function moveArrayItem(arr, fromIndex, toIndex) {
    if (fromIndex < 0 || fromIndex >= arr.length) return arr;
    if (toIndex < 0 || toIndex >= arr.length) return arr;
    if (fromIndex === toIndex) return arr;
    
    var newArr = arr.slice();
    var item = newArr.splice(fromIndex, 1)[0];
    newArr.splice(toIndex, 0, item);
    return newArr;
}
