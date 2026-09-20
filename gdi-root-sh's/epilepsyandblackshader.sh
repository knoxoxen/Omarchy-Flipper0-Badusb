#!/usr/bin/env bash
# epilepsyandblackshader.sh — self-contained Hyprland/Wayland effect
#
# Port of epilepsyandblackshader.cpp (Random gray-code ROP scramble + PatBlt white flashes).
# One-shot payload — no files to install, no root, pure runtime state:
#   curl -sL https://your-host/epilepsyandblackshader.sh | bash
# Run it again to disable (toggles, and leaves no residue after a reload).
#
set -euo pipefail

# ---------------------------------------------------------------------------
if [[ -z "${WAYLAND_DISPLAY:-}" ]] || ! command -v hyprctl >/dev/null 2>&1; then
    echo "epilepsyandblackshader: not a Hyprland/Wayland session" >&2
    exit 1
fi

TMP="${XDG_RUNTIME_DIR:-/tmp}"
SHADER="$TMP/.epilepsyandblackshader.frag"
STATE="$TMP/.epilepsyandblackshader.pdt"

umask 077

write_shader() {
    cat > "$SHADER" <<'EOF'
// Random gray-code ROP scramble + PatBlt white flashes
#version 300 es

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
uniform vec2 fullSize;

layout(location = 0) out vec4 fragColor;

float hash(float t) { return fract(sin(t * 127.1) * 43758.5453); }
float hash2(vec2 v) { return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453); }
vec3 hsv2rgb(float h, float s, float v) {
    vec3 p = abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return v * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}


void main() {
    vec2 pt = v_texcoord * fullSize;
    vec2 shift = vec2(floor(hash(time * 3.0) * 2000.0) - 1000.0,
                      floor(hash(time * 5.0) * 2000.0) - 1000.0);
    vec3 res = texture(tex, clamp(v_texcoord + shift / fullSize, 0.0, 1.0)).rgb;
    res *= 0.75 + 0.5 * hash(floor(time * 20.0));
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        vec2 s = vec2(hash(time * 11.0 + fi) * fullSize.x,
                      hash(time * 13.0 + fi) * fullSize.y);
        vec2 d = vec2(40.0 + hash(time * 17.0 + fi) * 600.0,
                      40.0 + hash(time * 19.0 + fi) * 600.0);
        float inRect = step(s.x, pt.x) * step(pt.x, s.x + d.x) *
                       step(s.y, pt.y) * step(pt.y, s.y + d.y);
        res = mix(res, vec3(1.0), inRect);
    }
    fragColor = vec4(res, 1.0);
}


EOF
}

# Set a config option at runtime. Prefers the modern lua config path
# (decoration.screen_shader / debug.damage_tracking), falls back to the
# legacy hyprlang keyword for pre-0.55 Hyprland.
cfg_str() {
    # string-typed option: $1 = dotted path, $2 = value
    if hyprctl -r eval "hl.config({ [\"$1\"] = \"$2\" })" >/dev/null 2>&1; then
        return 0
    fi
    hyprctl keyword "${1//./:}" "$2" >/dev/null 2>&1
}
cfg_int() {
    # integer-typed option: $1 = dotted path, $2 = number
    if hyprctl -r eval "hl.config({ [\"$1\"] = $2 })" >/dev/null 2>&1; then
        return 0
    fi
    hyprctl keyword "${1//./:}" "$2" >/dev/null 2>&1
}

current="$(hyprctl getoption decoration.screen_shader -j 2>/dev/null | grep -o '"str": *"[^"]*"' | cut -d'"' -f4 || true)"

if [[ "$current" == *"epilepsyandblackshader.frag"* ]]; then
    # ---- disable ----
    cfg_str 'decoration.screen_shader' ''
    if [[ -f "$STATE" ]]; then
        cfg_int 'debug.damage_tracking' "$(cat "$STATE")" || true
        rm -f "$STATE" "$SHADER"
    fi
    echo "epilepsyandblackshader: off"
else
    # ---- enable ----
    hyprctl getoption debug.damage_tracking -j 2>/dev/null | grep -o '"int": *[0-9]*' | head -1 | cut -d: -f2 > "$STATE"
    cfg_int 'debug.damage_tracking' '0'
    write_shader
    cfg_str 'decoration.screen_shader' "$SHADER"
    echo "epilepsyandblackshader: on"
fi
