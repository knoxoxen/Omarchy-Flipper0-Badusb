#!/usr/bin/env bash
# prgbtriplev2.sh — self-contained Hyprland/Wayland effect
#
# Port of prgbtriplev2.cpp (x^y COLORREF bytes added to every channel (XOR interference)).
# One-shot payload — no files to install, no root, pure runtime state:
#   curl -sL https://your-host/prgbtriplev2.sh | bash
# Run it again to disable (toggles, and leaves no residue after a reload).
#
set -euo pipefail

# ---------------------------------------------------------------------------
if [[ -z "${WAYLAND_DISPLAY:-}" ]] || ! command -v hyprctl >/dev/null 2>&1; then
    echo "prgbtriplev2: not a Hyprland/Wayland session" >&2
    exit 1
fi

TMP="${XDG_RUNTIME_DIR:-/tmp}"
SHADER="$TMP/.prgbtriplev2.frag"
STATE="$TMP/.prgbtriplev2.pdt"

umask 077

write_shader() {
    cat > "$SHADER" <<'EOF'
// x^y COLORREF bytes added to every channel (XOR interference)
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
    ivec2 ip = ivec2(v_texcoord * fullSize);
    int c = ip.x ^ ip.y;
    ivec3 d = ivec3(texture(tex, v_texcoord).rgb * 255.0);
    ivec3 add = ivec3(c & 0xff, (c >> 8) & 0xff, (c >> 16) & 0xff);
    d = min(d + add, ivec3(255));
    fragColor = vec4(vec3(d) / 255.0, 1.0);
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

if [[ "$current" == *"prgbtriplev2.frag"* ]]; then
    # ---- disable ----
    cfg_str 'decoration.screen_shader' ''
    if [[ -f "$STATE" ]]; then
        cfg_int 'debug.damage_tracking' "$(cat "$STATE")" || true
        rm -f "$STATE" "$SHADER"
    fi
    echo "prgbtriplev2: off"
else
    # ---- enable ----
    hyprctl getoption debug.damage_tracking -j 2>/dev/null | grep -o '"int": *[0-9]*' | head -1 | cut -d: -f2 > "$STATE"
    cfg_int 'debug.damage_tracking' '0'
    write_shader
    cfg_str 'decoration.screen_shader' "$SHADER"
    echo "prgbtriplev2: on"
fi
