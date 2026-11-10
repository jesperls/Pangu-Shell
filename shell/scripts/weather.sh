#!/usr/bin/env bash

LOCATION="${1:-}"
MAX_RETRIES=3
RETRY_DELAY=2
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pangu"
GEOIP_CACHE="$CACHE_DIR/geoip"
GEOCODE_CACHE_DIR="$CACHE_DIR/geocode"
GEOIP_TTL=86400
GEOCODE_TTL=604800

http_get() {
	local url="$1"
	local attempt=1
	local response=""

	while [[ $attempt -le $MAX_RETRIES ]]; do
		response=$(curl -sf --max-time 15 "$url" 2>/dev/null)
		if [[ -n "$response" && "$response" != "null" ]]; then
			printf '%s\n' "$response"
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
		printf '%s\n' '{"error": "GeoIP request failed"}'
		return 1
	fi

	local lat lon
	lat=$(printf '%s' "$response" | jq -r '.latitude // empty')
	lon=$(printf '%s' "$response" | jq -r '.longitude // empty')

	if [[ -z "$lat" || -z "$lon" ]]; then
		printf '%s\n' '{"error": "Could not determine location from GeoIP"}'
		return 1
	fi

	mkdir -p "$CACHE_DIR"
	printf '%s' "$lat,$lon" >"$GEOIP_CACHE"
	printf '%s\n' "$lat,$lon"
}

geocode_city() {
	local city="$1"
	local cache_key cache_file
	cache_key=$(printf '%s' "$city" | sha256sum | cut -d' ' -f1)
	cache_file="$GEOCODE_CACHE_DIR/$cache_key"

	if [[ -f "$cache_file" ]] && (($(date +%s) - $(stat -c %Y "$cache_file") < GEOCODE_TTL)); then
		cat "$cache_file"
		return 0
	fi

	local encoded_city
	encoded_city=$(printf '%s' "$city" | jq -sRr @uri)

	local response
	response=$(http_get "https://geocoding-api.open-meteo.com/v1/search?name=${encoded_city}")

	if [[ -z "$response" ]]; then
		printf '%s\n' '{"error": "Geocoding request failed"}'
		return 1
	fi

	local lat lon
	lat=$(printf '%s' "$response" | jq -r '.results[0].latitude // empty')
	lon=$(printf '%s' "$response" | jq -r '.results[0].longitude // empty')

	if [[ -z "$lat" || -z "$lon" ]]; then
		printf '%s\n' '{"error": "City not found"}'
		return 1
	fi

	mkdir -p "$GEOCODE_CACHE_DIR"
	printf '%s' "$lat,$lon" >"$cache_file"
	printf '%s\n' "$lat,$lon"
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
