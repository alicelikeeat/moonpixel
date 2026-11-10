#!/usr/bin/env bash
# Run a headless Godot script with a hard timeout:  tools/gd.sh <seconds> <script.gd> [-- args]
# GODOT env var overrides the binary.
T="$1"; shift
S="$1"; shift
exec timeout "$T" "${GODOT:-godot}" --headless --path "$(dirname "$0")/.." -s "$S" "$@"
