#!/usr/bin/env sh
set -eu

root_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
godot_bin=${GODOT_BIN:-godot}
run_dir=$(mktemp -d)
trap 'rm -rf "$run_dir"' EXIT
cd "$root_dir"
export XDG_CACHE_HOME="$run_dir/cache"
export XDG_CONFIG_HOME="$run_dir/config"
export XDG_DATA_HOME="$run_dir/data"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"

verify() {
	if ! timeout 60s "$godot_bin" "$@" > "$run_dir/output" 2>&1; then
		cat "$run_dir/output"
		return 1
	fi
	cat "$run_dir/output"
	# The Godot executable may exit zero after a script or shader error.
	if grep -Eq '(^|[[:space:]])(SCRIPT |SHADER )?ERROR:' "$run_dir/output"; then
		return 1
	fi
}

verify --headless --editor --import
verify --headless --quit-after 20
verify --headless --script res://tests/survival_smoke.gd
grep -Eq '^Survival smoke: [1-9][0-9]* passed, 0 failed\.$' "$run_dir/output"
