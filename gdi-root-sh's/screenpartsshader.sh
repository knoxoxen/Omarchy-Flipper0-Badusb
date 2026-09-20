#!/usr/bin/env bash
# screenpartsshader.sh — self-contained Hyprland/Wayland effect
#
# Port of screenpartsshader.cpp (Random screen rectangles stretched and copied to random spots).
# One-shot payload — no files to install, no root, pure runtime state:
#   curl -sL https://your-host/screenpartsshader.sh | bash
# Run it again to disable (toggles, and leaves no residue after a reload).
#
set -euo pipefail

# ---------------------------------------------------------------------------
if [[ -z "${WAYLAND_DISPLAY:-}" ]] || ! command -v hyprctl >/dev/null 2>&1; then
    echo "screenpartsshader: not a Hyprland/Wayland session" >&2
    exit 1
fi

TMP="${XDG_RUNTIME_DIR:-/tmp}"
SHADER="$TMP/.screenpartsshader.frag"
STATE="$TMP/.screenpartsshader.pdt"

umask 077

write_shader() {
    cat > "$SHADER" <<'EOF'
// Random screen rectangles stretched and copied to random spots
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
    vec3 res = texture(tex, v_texcoord).rgb;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        vec2 s0 = vec2(hash(time * 3.0 + fi) * fullSize.x, hash(time * 5.0 + fi) * fullSize.y);
        vec2 s1 = s0 + vec2(50.0 + hash(time * 7.0 + fi) * 600.0, 50.0 + hash(time * 9.0 + fi) * 300.0);
        vec2 d0 = vec2(hash(time * 11.0 + fi) * fullSize.x, hash(time * 13.0 + fi) * fullSize.y);
        vec2 d1 = d0 + vec2(50.0 + hash(time * 17.0 + fi) * 600.0, 50.0 + hash(time * 19.0 + fi) * 300.0);
        vec2 span = max(d1 - d0, vec2(1.0));
        float inRect = step(d0.x, pt.x) * step(pt.x, d1.x) *
                       step(d0.y, pt.y) * step(pt.y, d1.y);
        vec2 rel = clamp((pt - d0) / span, 0.0, 1.0);
        vec3 c = texture(tex, clamp((s0 + rel * (s1 - s0)) / fullSize, 0.0, 1.0)).rgb;
        res = mix(res, c, inRect);
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

if [[ "$current" == *"screenpartsshader.frag"* ]]; then
    # ---- disable ----
    cfg_str 'decoration.screen_shader' ''
    if [[ -f "$STATE" ]]; then
        cfg_int 'debug.damage_tracking' "$(cat "$STATE")" || true
        rm -f "$STATE" "$SHADER"
    fi
    echo "screenpartsshader: off"
else
    # ---- enable ----
    hyprctl getoption debug.damage_tracking -j 2>/dev/null | grep -o '"int": *[0-9]*' | head -1 | cut -d: -f2 > "$STATE"
    cfg_int 'debug.damage_tracking' '0'
    write_shader
    cfg_str 'decoration.screen_shader' "$SHADER"
    echo "screenpartsshader: on"
fi
