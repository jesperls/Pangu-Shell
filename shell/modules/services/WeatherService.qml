pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.theme

Singleton {
    id: root

    property string weatherSymbol: ""
    property string weatherIcon: Icons.cloud
    property real currentTemp: 0
    property real maxTemp: 0
    property real minTemp: 0
    property int weatherCode: 0
    property real windSpeed: 0
    property bool dataAvailable: false
    property bool isLoading: false
    property bool hasFailed: false

    property var forecast: []

    property string sunrise: ""
    property string sunset: ""
    property real sunProgress: 0.0
    property bool isDay: true
    property string timeOfDay: "Day"
    property string weatherDescription: ""

    property bool debugMode: false
    property real debugHour: 12.0
    property int debugWeatherCode: 0

    property real _rawCurrentTempC: 0
    property real _rawMaxTempC: 0
    property real _rawMinTempC: 0
    property var _rawForecastC: []

    readonly property string scriptPath: Paths.script("weather.sh")
    property GeneratedFile weatherSnapshotFile: GeneratedFile {
        path: Paths.cachePath("weather.json")
    }

    property int retryCount: 0
    readonly property int maxRetries: 3
    property bool wasCancelled: false
    property bool pendingRefresh: false

    property var suspendConnections: Connections {
        target: SuspendManager
        function onPreparingForSleep() {
            if (weatherProcess.running) {
                root.wasCancelled = true;
                weatherProcess.running = false;
            }
            root.pendingRefresh = false;
            root.isLoading = false;
            if (retryTimer) retryTimer.stop();
        }
        function onWakingUp() {
            if (wakeRefreshTimer) wakeRefreshTimer.restart();
        }
    }

    property var wakeRefreshTimer: Timer {
        id: wakeRefreshTimer
        interval: 5000
        repeat: false
        onTriggered: root.updateWeather()
    }

    property Timer refreshTimer: Timer {
        interval: 600000
        running: !SuspendManager.isSuspending
        repeat: true
        onTriggered: root.updateWeather()
    }

    property Timer sunPositionTimer: Timer {
        interval: 60000
        running: !SuspendManager.isSuspending && (GlobalStates.dashboardOpen || GlobalStates.launcherOpen || GlobalStates.overviewOpen)
        repeat: true
        onTriggered: root.calculateSunPosition()
    }

    property Timer retryTimer: Timer {
        interval: 3000
        repeat: false
        onTriggered: root.updateWeather()
    }

    function parseTime(timeStr) {
        if (!timeStr)
            return 0;
        var parts = timeStr.split(":");
        if (parts.length < 2)
            return 0;
        var h = parseInt(parts[0], 10);
        var m = parseInt(parts[1], 10);
        if (isNaN(h) || isNaN(m))
            return 0;
        return h + m / 60;
    }

    readonly property real visualSunriseHour: 6.0
    readonly property real visualSunsetHour: 18.0

    function calculateSunProgress(hour, sunriseH, sunsetH) {
        var dayDuration = sunsetH - sunriseH;
        if (dayDuration <= 0 || dayDuration >= 24)
            return 0.5;
        if (hour >= sunriseH && hour <= sunsetH) {
            return (hour - sunriseH) / dayDuration;
        }
        var nightDuration = 24 - dayDuration;
        if (hour > sunsetH) {
            return (hour - sunsetH) / nightDuration;
        }
        return (hour + (24 - sunsetH)) / nightDuration;
    }

    readonly property real debugSunProgress: calculateSunProgress(debugHour, visualSunriseHour, visualSunsetHour)
    readonly property bool debugIsDay: debugHour >= visualSunriseHour && debugHour <= visualSunsetHour

    function calculateTimeBlend(hour) {
        var day = 0, evening = 0, night = 0;

        if (hour >= 9 && hour <= 17) {
            day = 1.0;
        } else if (hour > 8 && hour < 9) {
            var t = hour - 8;
            evening = 1.0 - t;
            day = t;
        } else if (hour > 17 && hour < 18) {
            var t = hour - 17;
            day = 1.0 - t;
            evening = t;
        } else if (hour >= 6 && hour <= 8) {
            evening = 1.0;
        } else if (hour >= 18 && hour <= 20) {
            evening = 1.0;
        } else if (hour > 5 && hour < 6) {
            var t = hour - 5;
            night = 1.0 - t;
            evening = t;
        } else if (hour > 20 && hour < 21) {
            var t = hour - 20;
            evening = 1.0 - t;
            night = t;
        } else {
            night = 1.0;
        }

        return {
            day: day,
            evening: evening,
            night: night
        };
    }

    readonly property var debugTimeBlend: calculateTimeBlend(debugHour)
    property real currentHour: 12.0
    readonly property var realTimeBlend: calculateTimeBlend(currentHour)
    readonly property real realSunProgress: calculateSunProgress(currentHour, visualSunriseHour, visualSunsetHour)
    readonly property real realSunriseHour: sunrise.length > 0 ? parseTime(sunrise) : 6.0
    readonly property real realSunsetHour: sunset.length > 0 ? parseTime(sunset) : 18.0
    readonly property bool realIsDay: currentHour >= realSunriseHour && currentHour <= realSunsetHour

    readonly property var effectiveTimeBlend: debugMode ? debugTimeBlend : realTimeBlend

    readonly property string debugTimeOfDay: {
        var blend = debugTimeBlend;
        if (blend.day >= blend.evening && blend.day >= blend.night)
            return "Day";
        if (blend.evening >= blend.night)
            return "Evening";
        return "Night";
    }

    readonly property real effectiveSunProgress: debugMode ? debugSunProgress : realSunProgress
    readonly property bool effectiveIsDay: debugMode ? debugIsDay : realIsDay
    readonly property int effectiveWeatherCode: debugMode ? debugWeatherCode : weatherCode
    readonly property string effectiveWeatherDescription: debugMode ? getWeatherDescription(debugWeatherCode) : weatherDescription

    readonly property string effectiveWeatherEffect: getWeatherEffect(effectiveWeatherCode)
    readonly property real effectiveWeatherIntensity: getWeatherIntensity(effectiveWeatherCode)
    readonly property string effectiveWeatherIcon: getWeatherCodeIcon(effectiveWeatherCode, effectiveIsDay)

    function getWeatherEffect(code) {
        if (code === 0 || code === 1)
            return "clear";
        if (code === 2 || code === 3)
            return "clouds";
        if (code === 45 || code === 48)
            return "fog";
        if (code >= 51 && code <= 57)
            return "drizzle";
        if (code >= 61 && code <= 67)
            return "rain";
        if (code >= 71 && code <= 77)
            return "snow";
        if (code >= 80 && code <= 82)
            return "rain";
        if (code >= 85 && code <= 86)
            return "snow";
        if (code === 95)
            return "thunderstorm";
        if (code >= 96 && code <= 99)
            return "thunderstorm";
        return "clear";
    }

    function getWeatherIntensity(code) {
        if (code === 0 || code === 1)
            return 0.0;
        if (code === 2)
            return 0.5;
        if (code === 3)
            return 1.0;
        if (code === 45)
            return 0.5;
        if (code === 48)
            return 0.7;
        if (code === 51 || code === 56)
            return 0.3;
        if (code === 53)
            return 0.5;
        if (code === 55 || code === 57)
            return 0.7;
        if (code === 61)
            return 0.4;
        if (code === 63 || code === 66)
            return 0.6;
        if (code === 65 || code === 67)
            return 0.9;
        if (code === 71)
            return 0.3;
        if (code === 73)
            return 0.5;
        if (code === 75 || code === 77)
            return 0.8;
        if (code === 80)
            return 0.5;
        if (code === 81)
            return 0.7;
        if (code === 82)
            return 1.0;
        if (code === 85)
            return 0.6;
        if (code === 86)
            return 0.9;
        if (code === 95)
            return 0.8;
        if (code >= 96)
            return 1.0;
        return 0.0;
    }

    function getWeatherDescription(code) {
        if (code === 0)
            return "Clear sky";
        if (code === 1)
            return "Mainly clear";
        if (code === 2)
            return "Partly cloudy";
        if (code === 3)
            return "Overcast";
        if (code === 45)
            return "Foggy";
        if (code === 48)
            return "Rime fog";
        if (code >= 51 && code <= 53)
            return "Light drizzle";
        if (code === 55)
            return "Dense drizzle";
        if (code >= 56 && code <= 57)
            return "Freezing drizzle";
        if (code === 61)
            return "Light rain";
        if (code === 63)
            return "Moderate rain";
        if (code === 65)
            return "Heavy rain";
        if (code >= 66 && code <= 67)
            return "Freezing rain";
        if (code === 71)
            return "Light snow";
        if (code === 73)
            return "Moderate snow";
        if (code === 75)
            return "Heavy snow";
        if (code === 77)
            return "Snow grains";
        if (code >= 80 && code <= 81)
            return "Rain showers";
        if (code === 82)
            return "Heavy showers";
        if (code >= 85 && code <= 86)
            return "Snow showers";
        if (code === 95)
            return "Thunderstorm";
        if (code >= 96 && code <= 99)
            return "Thunderstorm with hail";
        return "Unknown";
    }

    function calculateSunPosition() {
        var now = new Date();
        var hour = now.getHours() + now.getMinutes() / 60;

        root.currentHour = hour;

        var sunriseH = sunrise.length > 0 ? parseTime(sunrise) : 6.0;
        var sunsetH = sunset.length > 0 ? parseTime(sunset) : 18.0;

        root.isDay = (hour >= sunriseH && hour <= sunsetH);
        root.sunProgress = calculateSunProgress(hour, sunriseH, sunsetH);

        var blend = calculateTimeBlend(hour);
        if (blend.day >= blend.evening && blend.day >= blend.night) {
            root.timeOfDay = "Day";
        } else if (blend.evening >= blend.night) {
            root.timeOfDay = "Evening";
        } else {
            root.timeOfDay = "Night";
        }
    }

    function getWeatherCodeEmoji(code) {
        if (code === 0)
            return "☀️";
        if (code === 1)
            return "🌤️";
        if (code === 2)
            return "⛅";
        if (code === 3)
            return "☁️";
        if (code === 45)
            return "🌫️";
        if (code === 48)
            return "🌨️";
        if (code >= 51 && code <= 53)
            return "🌦️";
        if (code === 55)
            return "🌧️";
        if (code >= 56 && code <= 57)
            return "🧊";
        if (code >= 61 && code <= 65)
            return "🌧️";
        if (code >= 66 && code <= 67)
            return "🧊";
        if (code >= 71 && code <= 77)
            return "❄️";
        if (code >= 80 && code <= 81)
            return "🌦️";
        if (code === 82)
            return "🌧️";
        if (code >= 85 && code <= 86)
            return "🌨️";
        if (code === 95)
            return "⛈️";
        if (code >= 96 && code <= 99)
            return "🌩️";
        return "❓";
    }

    function getWeatherCodeIcon(code, day = true) {
        if (code === 0)
            return day ? Icons.sun : Icons.moonStars;
        if (code === 1)
            return day ? Icons.sunDim : Icons.moonStars;
        if (code === 2)
            return day ? Icons.cloudSun : Icons.cloudMoon;
        if (code === 3)
            return Icons.cloud;
        if (code === 45 || code === 48)
            return Icons.cloudFog;
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
            return Icons.cloudRain;
        if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86))
            return Icons.cloudSnow;
        if (code >= 95 && code <= 99)
            return Icons.cloudLightning;
        return Icons.cloud;
    }

    function convertTemp(temp) {
        if (Config.weather?.unit === "F") {
            return (temp * 9 / 5) + 32;
        }
        return temp;
    }

    function applyConvertedTemps() {
        root.currentTemp = convertTemp(root._rawCurrentTempC);
        root.maxTemp = convertTemp(root._rawMaxTempC);
        root.minTemp = convertTemp(root._rawMinTempC);
        root.forecast = root._rawForecastC.map(entry => ({
            date: entry.date,
            dayName: entry.dayName,
            weatherCode: entry.weatherCode,
            emoji: entry.emoji,
            icon: entry.icon,
            maxTemp: convertTemp(entry.maxTempC),
            minTemp: convertTemp(entry.minTempC)
        }));
    }

    function handleError() {
        if (retryCount < maxRetries) {
            retryCount++;
            retryTimer.start();
        } else {
            root.isLoading = false;
            root.hasFailed = true;
            retryCount = 0;
        }
    }

    function handleResponse(text) {
        var raw = text.trim();
        if (raw.length > 0) {
            try {
                var data = JSON.parse(raw);

                if (data.error) {
                    console.warn("WeatherService:", data.error);
                    root.dataAvailable = false;
                    root.handleError();
                    return;
                }

                if (data.current_weather && data.daily) {
                    var weather = data.current_weather;
                    var daily = data.daily;

                    root.weatherCode = parseInt(weather.weathercode, 10) || 0;
                    root._rawCurrentTempC = parseFloat(weather.temperature) || 0;
                    root.windSpeed = parseFloat(weather.windspeed) || 0;

                    if (daily.temperature_2m_max && daily.temperature_2m_max.length > 0) {
                        root._rawMaxTempC = parseFloat(daily.temperature_2m_max[0]) || 0;
                    }
                    if (daily.temperature_2m_min && daily.temperature_2m_min.length > 0) {
                        root._rawMinTempC = parseFloat(daily.temperature_2m_min[0]) || 0;
                    }

                    if (daily.sunrise && daily.sunrise.length > 0) {
                        root.sunrise = daily.sunrise[0].split("T")[1] || "";
                    }
                    if (daily.sunset && daily.sunset.length > 0) {
                        root.sunset = daily.sunset[0].split("T")[1] || "";
                    }

                    var rawForecast = [];
                    var dayCount = Math.min(7, daily.time ? daily.time.length : 0);
                    for (var i = 0; i < dayCount; i++) {
                        var dateParts = daily.time[i].split("-");
                        var year = parseInt(dateParts[0], 10);
                        var month = parseInt(dateParts[1], 10) - 1;
                        var day = parseInt(dateParts[2], 10);

                        var dayDate = new Date(year, month, day);
                        var rawDayName = i === 0 ? "Today" : dayDate.toLocaleDateString(Qt.locale(), "ddd");
                        var dayName = rawDayName.charAt(0).toUpperCase() + rawDayName.slice(1);
                        var code = daily.weathercode ? daily.weathercode[i] : 0;
                        rawForecast.push({
                            date: daily.time[i],
                            dayName: dayName,
                            weatherCode: code,
                            emoji: getWeatherCodeEmoji(code),
                            icon: getWeatherCodeIcon(code, true),
                            maxTempC: daily.temperature_2m_max ? (parseFloat(daily.temperature_2m_max[i]) || 0) : 0,
                            minTempC: daily.temperature_2m_min ? (parseFloat(daily.temperature_2m_min[i]) || 0) : 0
                        });
                    }
                    root._rawForecastC = rawForecast;
                    root.applyConvertedTemps();

                    root.calculateSunPosition();
                    root.weatherSymbol = getWeatherCodeEmoji(root.weatherCode);
                    root.weatherIcon = getWeatherCodeIcon(root.weatherCode, root.isDay);
                    root.weatherDescription = getWeatherDescription(root.weatherCode);
                    root.dataAvailable = true;
                    root.isLoading = false;
                    root.hasFailed = false;
                    root.retryCount = 0;
                    root.weatherSnapshotFile.write(JSON.stringify({
                        weatherCode: root.weatherCode,
                        tempC: root._rawCurrentTempC,
                        isDay: root.isDay,
                        sunrise: root.sunrise,
                        sunset: root.sunset,
                        updatedAt: Date.now()
                    }));
                } else {
                    console.warn("WeatherService: Invalid response structure");
                    root.dataAvailable = false;
                    root.handleError();
                }
            } catch (e) {
                console.warn("WeatherService: JSON parse error:", e);
                root.dataAvailable = false;
                root.handleError();
            }
        } else {
            console.warn("WeatherService: Empty response");
            root.handleError();
        }
    }

    function finishRequest(code, text) {
        if (root.wasCancelled || SuspendManager.isSuspending) {
            root.wasCancelled = false;
            root.isLoading = false;
            return;
        }
        if (root.pendingRefresh) {
            root.pendingRefresh = false;
            Qt.callLater(root.updateWeather);
            return;
        }
        if (code === 0) {
            root.handleResponse(text);
        } else {
            root.dataAvailable = false;
            root.handleError();
        }
    }

    property Process weatherProcess: Process {
        running: false
        command: []
        stdout: StdioCollector { id: weatherOutput; waitForEnd: true }
        onExited: code => root.finishRequest(code, weatherOutput.text)
    }

    property var weatherConfig: Config.weather
    readonly property string configLocation: weatherConfig ? weatherConfig.location : ""
    readonly property string configUnit: weatherConfig ? weatherConfig.unit : "C"
    property bool _initialized: false

    onConfigLocationChanged: {
        if (!_initialized || !Config.initialLoadComplete) return;
        Qt.callLater(root.updateWeather);
    }
    onConfigUnitChanged: {
        if (!_initialized) return;
        if (root.dataAvailable)
            root.applyConvertedTemps();
        else if (Config.initialLoadComplete)
            Qt.callLater(root.updateWeather);
    }

    function updateWeather() {
        if (SuspendManager.isSuspending) return;
        if (weatherProcess.running) {
            root.pendingRefresh = true;
            return;
        }
        retryTimer.stop();
        root.wasCancelled = false;

        if (!Config.weather) {
            return;
        }

        root.isLoading = true;
        root.hasFailed = false;

        var location = String(Config.weather.location || "").trim();
        weatherProcess.command = ["timeout", "-k", "5s", "60s", scriptPath, location];
        weatherProcess.running = true;
    }

    Timer {
        id: startupDelay
        interval: 1500
        running: Config.initialLoadComplete
        repeat: false
        onTriggered: root.updateWeather()
    }

    Component.onCompleted: {
        var now = new Date();
        currentHour = now.getHours() + now.getMinutes() / 60;
        _initialized = true;
    }
}
