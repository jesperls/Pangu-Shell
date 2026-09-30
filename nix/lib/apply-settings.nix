{
  pkgs,
  lib,
  configDir,
  dataDir,
  settings,
}:
pkgs.writeShellApplication {
  name = "pangu-apply-settings";
  excludeShellChecks = [ "SC2016" ]; # Generated settings and paths are literal shell arguments.
  runtimeInputs = [
    pkgs.jq
    pkgs.coreutils
  ];
  text = ''
    temporary=""
    trap 'if [[ -n "$temporary" ]]; then rm -f -- "$temporary"; fi' EXIT

    apply() {
      local file="$1" overrides="$2" source=/dev/null
      mkdir -p -- "$(dirname -- "$file")"
      if [[ -e "$file" ]]; then source="$file"; fi
      temporary=$(mktemp -- "$file.XXXXXXXX")
      jq -s --argjson overrides "$overrides" '
        if length == 0 then {}
        elif length == 1 and (.[0] | type) == "object" then .[0]
        else error("settings must contain one JSON object") end
        | . * $overrides
      ' "$source" > "$temporary"
      if [[ -e "$file" ]]; then
        if cmp -s -- "$file" "$temporary"; then
          rm -- "$temporary"
          temporary=""
          return
        fi
        chmod --reference="$file" -- "$temporary"
      fi
      mv -- "$temporary" "$file"
      temporary=""
    }

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: value:
        "apply ${lib.escapeShellArg "${if name == "pinnedapps" then dataDir else configDir}/${name}.json"} ${lib.escapeShellArg (builtins.toJSON value)}"
      ) settings
    )}
  '';
}
