#!/usr/bin/env bash
# darkr.sh — self-contained Hyprland/Wayland screen-corruptor
#
# Port of the Win32 BitBlt(SRCAND) hack to a Hyprland screen shader:
# every frame is bitwise-ANDed with a 1px-shifted copy of itself using a
# random global offset, exactly like the original rand()%2 BitBlt loop.
#
# One-shot payload — no files to install, no root, pure runtime state:
#   curl -sL https://your-host/darkr.sh | bash
# Run it again to disable (toggles, and leaves no residue after a reload).
#
set -euo pipefail

# ---------------------------------------------------------------------------
if [[ -z "${WAYLAND_DISPLAY:-}" ]] || ! command -v hyprctl >/dev/null 2>&1; then
    echo "darkr: not a Hyprland/Wayland session" >&2
    exit 1
fi

TMP="${XDG_RUNTIME_DIR:-/tmp}"
SHADER="$TMP/.darkr.frag"
STATE="$TMP/.darkr.pdt"

umask 077

write_shader() {
    cat > "$SHADER" <<'EOF'
#version 300 es

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
uniform vec2 fullSize;

layout(location = 0) out vec4 fragColor;

float hash(float t) {
    return fract(sin(t * 127.1) * 43758.5453);
}

void main() {
    vec2 shift = vec2(floor(hash(time * 33.0) * 2.0),
                      floor(hash(time * 57.0) * 2.0));

    vec4 cur = texture(tex, v_texcoord);
    vec4 ref = texture(tex, clamp(v_texcoord + shift / fullSize, 0.0, 1.0));

    // BitBlt SRCAND: dest = dest AND source, in 8-bit integer space.
    ivec3 dst = ivec3(cur.rgb * 255.0);
    ivec3 src = ivec3(ref.rgb * 255.0);
    vec3 res = vec3(dst & src) / 255.0;

    fragColor = vec4(res, 1.0);
}
EOF
}

# Set a config option at runtime. Prefers the modern lua config path
# (decoration.screen_shader / debug.damage_tracking), falls back to the
# legacy hyprlang keyword for pre-0.55 Hyprland.
cfg() {
    local name="$1" value="$2"
    if hyprctl -r eval "hl.config({ [\"$name\"] = $value })" >/dev/null 2>&1; then
        return 0
    fi
    hyprctl keyword "${name//./:}" "$value" >/dev/null 2>&1
}

current="$(hyprctl getoption decoration.screen_shader -j 2>/dev/null | grep -o '"str": *"[^"]*"' | cut -d'"' -f4 || true)"

if [[ "$current" == *.darkr.frag ]] || [[ "$current" == *darkr* ]]; then
    # ---- disable ----
    cfg 'decoration.screen_shader' '""'
    if [[ -f "$STATE" ]]; then
        cfg 'debug.damage_tracking' "$(cat "$STATE")" || true
        rm -f "$STATE" "$SHADER"
    fi
    echo "darkr: off"
else
    # ---- enable ----
    hyprctl getoption debug.damage_tracking -j 2>/dev/null \
        | grep -o '"int": *[0-9]*' | head -1 | cut -d: -f2 > "$STATE"
    cfg 'debug.damage_tracking' '0'
    write_shader
    cfg 'decoration.screen_shader' "\"$SHADER\""
    echo "darkr: on"
fi