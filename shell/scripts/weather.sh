#!/usr/bin/env bash

LOCATION="${1:-}"
MAX_RETRIES=3
RETRY_DELAY=2
GEOIP_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/pangu/geoip"
GEOIP_TTL=86400

http_get() {
	local url="$1"
	local attempt=1
	local response=""

	while [[ $attempt -le $MAX_RETRIES ]]; do
		response=$(curl -sf --max-time 15 "$url" 2>/dev/null)
		if [[ -n "$response" && "$response" != "null" ]]; then
			echo "$response"
			return 0
		fi
		attempt=$((attempt + 1))
		sleep $RETRY_DELAY
	done

	return 1
}

get_geoip_coords() {
	if [[ -f "$GEOIP_CACHE" ]] && (($(date +%s) - $(stat -c %Y "$GEOIP_CACHE") < GEOIP_TTL)); then
		cat "$GEOIP_CACHE"
		return 0
	fi

	local response
	response=$(http_get "https://ipapi.co/json/")

	if [[ -z "$response" ]]; then
		echo '{"error": "GeoIP request failed"}'
		return 1
	fi

	local lat lon
	lat=$(echo "$response" | jq -r '.latitude // empty')
	lon=$(echo "$response" | jq -r '.longitude // empty')

	if [[ -z "$lat" || -z "$lon" ]]; then
		echo '{"error": "Could not determine location from GeoIP"}'
		return 1
	fi

	mkdir -p "$(dirname "$GEOIP_CACHE")"
	printf '%s' "$lat,$lon" >"$GEOIP_CACHE"
	echo "$lat,$lon"
}

geocode_city() {
	local city="$1"
	local encoded_city
	encoded_city=$(echo -n "$city" | jq -sRr @uri)

	local response
	response=$(http_get "https://geocoding-api.open-meteo.com/v1/search?name=${encoded_city}")

	if [[ -z "$response" ]]; then
		echo '{"error": "Geocoding request failed"}'
		return 1
	fi

	local lat lon
	lat=$(echo "$response" | jq -r '.results[0].latitude // empty')
	lon=$(echo "$response" | jq -r '.results[0].longitude // empty')

	if [[ -z "$lat" || -z "$lon" ]]; then
		echo '{"error": "City not found"}'
		return 1
	fi

	echo "$lat,$lon"
}

fetch_weather() {
	local lat="$1"
	local lon="$2"

	local url="https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current_weather=true&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset,weathercode&timezone=auto&forecast_days=7"

	local response
	response=$(http_get "$url")

	if [[ -z "$response" ]]; then
		echo '{"error": "Weather API request failed"}'
		return 1
	fi

	local has_current has_daily
	has_current=$(echo "$response" | jq -r '.current_weather // empty')
	has_daily=$(echo "$response" | jq -r '.daily // empty')

	if [[ -z "$has_current" || -z "$has_daily" ]]; then
		echo '{"error": "Invalid weather API response"}'
		return 1
	fi

	echo "$response"
}

main() {
	local coords lat lon

	if [[ -z "$LOCATION" ]]; then
		coords=$(get_geoip_coords)
		if [[ "$coords" == "{"* ]]; then
			echo "$coords"
			exit 1
		fi
	elif [[ "$LOCATION" =~ ^-?[0-9]+\.?[0-9]*,-?[0-9]+\.?[0-9]*$ ]]; then
		coords="$LOCATION"
	else
		coords=$(geocode_city "$LOCATION")
		if [[ "$coords" == "{"* ]]; then
			echo "$coords"
			exit 1
		fi
	fi

	lat="${coords%,*}"
	lon="${coords#*,}"

	fetch_weather "$lat" "$lon"
}

main
