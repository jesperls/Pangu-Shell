#include "WallpaperEngine/WebBrowser/CEF/WebProperties.h"
#include <cassert>
#include <iostream>

using namespace WallpaperEngine::WebBrowser::CEF;

int main () {
    const auto definitions = nlohmann::json::parse (R"JSON({
        "paused": {"type": "bool", "value": false},
        "speed": {"type": "slider", "value": 5, "min": 1, "max": 10},
        "bgcolor": {"type": "color", "value": "0 0 0"},
        "numberchoice": {"type": "combo", "value": 1, "options": [{"value": 1}, {"value": 2}]},
        "stringchoice": {"type": "combo", "value": "day", "options": [{"value": "day"}, {"value": "night"}]},
        "text": {"type": "textinput", "value": "default"},
        "empty": {"type": "file", "value": ""},
        "heading": {"type": "group", "text": "Heading"}
    })JSON");
    const auto defaults = webProperties (definitions, {});
    assert (defaults["paused"]["value"] == false);
    assert (defaults["speed"]["value"] == 5);
    assert (defaults["text"]["value"] == "default");
    assert (!defaults.contains ("heading"));
    const auto properties = webProperties (definitions, {
        {"paused", "1"}, {"speed", "1"}, {"bgcolor", "1 0 0"},
        {"numberchoice", "2"}, {"stringchoice", "night"},
        {"text", "quote\" newline\n U+2028:\xe2\x80\xa8"}, {"empty", ""}, {"unknown", "ignored"}
    });
    assert (properties["paused"]["value"].is_boolean ());
    assert (properties["paused"]["value"] == true);
    assert (properties["speed"]["value"].is_number ());
    assert (properties["speed"]["value"] == 1);
    assert (properties["bgcolor"]["value"] == "1 0 0");
    assert (properties["numberchoice"]["value"].is_number ());
    assert (properties["numberchoice"]["value"] == 2);
    assert (properties["stringchoice"]["value"] == "night");
    assert (properties["empty"]["value"] == "");
    assert (!properties.contains ("unknown"));
    assert (webProperties (definitions, {{"paused", "0"}})["paused"]["value"] == false);
    std::cout << webPropertyScript (properties);
}
