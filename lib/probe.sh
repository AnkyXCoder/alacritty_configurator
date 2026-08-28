#!/bin/bash
# tools/alacritty/lib/probe.sh
#
# Environment / capability detection for the wizard: Alacritty version,
# live-preview availability, existing config, Nerd Font / unicode support,
# and installed monospace font families.

# probe_alacritty -- sets ALACRITTY_BIN, ALACRITTY_VERSION; aborts if missing
# or too old for TOML config (< 0.13).
probe_alacritty() {
	ALACRITTY_BIN="$(command -v alacritty || true)"
	if [[ -z "$ALACRITTY_BIN" ]]; then
		ui_error "alacritty is not installed or not on PATH."
		exit 1
	fi

	local raw
	raw="$("$ALACRITTY_BIN" --version 2>/dev/null)"
	ALACRITTY_VERSION="$(printf '%s' "$raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
	if [[ -z "$ALACRITTY_VERSION" ]]; then
		ui_warn "Could not determine alacritty version; proceeding cautiously."
		ALACRITTY_VERSION="0.0.0"
	fi

	local major minor
	major="$(cut -d. -f1 <<<"$ALACRITTY_VERSION")"
	minor="$(cut -d. -f2 <<<"$ALACRITTY_VERSION")"
	if ((major == 0 && minor < 13)); then
		ui_error "Alacritty $ALACRITTY_VERSION does not support TOML configuration (needs >= 0.13). Aborting."
		exit 1
	fi
	SUPPORTS_IMPORT=1
	if ((major == 0 && minor < 14)); then
		SUPPORTS_IMPORT=0
	fi
}

# probe_live -- sets LIVE=1 if we can push runtime config to a real window.
probe_live() {
	LIVE=0
	if [[ -n "${ALACRITTY_WINDOW_ID:-}" ]] && "$ALACRITTY_BIN" msg get-config -w -1 >/dev/null 2>&1; then
		LIVE=1
	fi

	if [[ "$LIVE" -eq 1 ]]; then
		ui_success "Live preview enabled (running inside Alacritty)."
	else
		ui_warn "Live preview unavailable (not running inside Alacritty, or IPC socket disabled)."
		ui_warn "Falling back to static preview panels."
	fi
}

# probe_existing_config -- sets EXISTING_CONFIG_PATH if one of the documented
# search locations has a file.
probe_existing_config() {
	EXISTING_CONFIG_PATH=""
	local candidates=(
		"${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
		"${XDG_CONFIG_HOME:-$HOME/.config}/alacritty.toml"
		"$HOME/.config/alacritty/alacritty.toml"
		"$HOME/.alacritty.toml"
		"/etc/alacritty/alacritty.toml"
	)
	local c
	for c in "${candidates[@]}"; do
		if [[ -f "$c" ]]; then
			EXISTING_CONFIG_PATH="$c"
			return 0
		fi
	done
}

# probe_unicode -- interactively asks whether box-drawing/block glyphs render.
probe_unicode() {
	ui_header "Preflight" "Terminal capability check"
	ui_info "The following characters should render as a box, blocks, and shades:"
	printf '\n  %s\n  %s\n\n' "╭──────╮ ▁▂▃▄▅▆▇█ ░▒▓" "╰──────╯"
	local ans
	ask_yn ans "Did that render correctly (no boxes/question marks)?" "y"
	local rc=$?
	[[ "$rc" -ne 0 ]] && exit "$rc"
	UNICODE_OK="$ans"
}

# probe_nerdfont -- interactively asks whether powerline/icon glyphs render,
# cross-checked against installed fonts.
probe_nerdfont() {
	local fc_hits=0
	if command -v fc-list >/dev/null 2>&1; then
		fc_hits="$(fc-list 2>/dev/null | grep -ic 'nerd font' || true)"
	fi

	ui_header "Preflight" "Nerd Font glyph check"
	ui_info "The following powerline separators and icons need a Nerd Font to render as symbols:"
	printf '\n  \ue0b0 \ue0b2  \uf015 \ue0a0 \uf1d3\n\n'
	if [[ "$fc_hits" -eq 0 ]]; then
		ui_warn "No Nerd Font detected via fc-list on this system."
	fi
	local ans
	ask_yn ans "Did those render as solid triangles/icons (not boxes)?" "n"
	local rc=$?
	[[ "$rc" -ne 0 ]] && exit "$rc"
	NERDFONT_OK="$ans"
	NERDFONT_INSTALLED_COUNT="$fc_hits"
}

# probe_fonts -- populates FONT_FAMILIES (Nerd Fonts first) from fc-list.
probe_fonts() {
	FONT_FAMILIES=()
	if ! command -v fc-list >/dev/null 2>&1; then
		FONT_FAMILIES=("monospace")
		return
	fi

	local -a nerd=() mono=()
	local family spacing
	while IFS=':' read -r family spacing; do
		family="${family#" "}"
		family="${family%%,*}"
		[[ -z "$family" ]] && continue
		[[ "$spacing" != *"spacing=100"* ]] && continue
		# Skip Noto/CJK/emoji fonts: they are rarely desirable as terminal fonts.
		if [[ "$family" == *"Noto"* || "$family" == *"CJK"* || "$family" == *"SignWriting"* ]]; then
			continue
		fi
		if [[ "$family" == *"Nerd Font"* ]]; then
			nerd+=("$family")
		else
			mono+=("$family")
		fi
	done < <(fc-list : family spacing 2>/dev/null)

	# de-dup while preserving order
	local -a nerd_u=() mono_u=()
	local seen=""
	for family in "${nerd[@]}"; do
		[[ "$seen" == *"|$family|"* ]] && continue
		seen+="|$family|"
		nerd_u+=("$family")
	done
	for family in "${mono[@]}"; do
		[[ "$seen" == *"|$family|"* ]] && continue
		seen+="|$family|"
		mono_u+=("$family")
	done

	FONT_FAMILIES=("${nerd_u[@]}" "${mono_u[@]}")
	if [[ "${#FONT_FAMILIES[@]}" -eq 0 ]]; then
		FONT_FAMILIES=("monospace")
	fi
}

# probe_shells -- populates SHELL_PATHS with every installed login shell,
# deduplicated by real path and with common interactive shells
# (zsh/bash/fish) sorted first.
probe_shells() {
	local -a candidates=()

	if [[ -r /etc/shells ]]; then
		while IFS= read -r line; do
			[[ "$line" == \#* || -z "$line" ]] && continue
			candidates+=("$line")
		done </etc/shells
	fi

	# Fallback / supplement: also look on PATH in case /etc/shells is stale
	# or missing (e.g. a shell installed via a package manager that never
	# registered itself there).
	local extra
	for extra in bash zsh fish dash ksh tcsh csh; do
		local found
		found="$(command -v "$extra" 2>/dev/null || true)"
		[[ -n "$found" ]] && candidates+=("$found")
	done

	# Exclude entries that are listed in /etc/shells but aren't interactive
	# login shells (multiplexers, restricted variants).
	local -a exclude_names=(tmux screen rbash)

	local -A seen=()
	SHELL_PATHS=()
	local c resolved base skip name
	for c in "${candidates[@]}"; do
		[[ -x "$c" ]] || continue
		resolved="$(readlink -f "$c" 2>/dev/null || echo "$c")"
		base="$(basename "$resolved")"

		skip=0
		for name in "${exclude_names[@]}"; do
			[[ "$base" == "$name" ]] && skip=1
		done
		[[ "$skip" -eq 1 ]] && continue

		[[ -n "${seen[$resolved]:-}" ]] && continue
		seen[$resolved]=1
		SHELL_PATHS+=("$resolved")
	done

	# Sort: zsh, bash, fish first (in that order), then everything else
	# alphabetically.
	local -a priority=() rest=()
	local p
	for p in zsh bash fish; do
		for c in "${SHELL_PATHS[@]}"; do
			[[ "$(basename "$c")" == "$p" ]] && priority+=("$c")
		done
	done
	for c in "${SHELL_PATHS[@]}"; do
		local already=0
		for p in "${priority[@]}"; do
			[[ "$c" == "$p" ]] && already=1
		done
		[[ "$already" -eq 0 ]] && rest+=("$c")
	done
	mapfile -t rest < <(printf '%s\n' "${rest[@]}" | sort)
	SHELL_PATHS=("${priority[@]}" "${rest[@]}")
}

# probe_env -- misc environment facts used to skip irrelevant questions.
probe_env() {
	IS_KDE_WAYLAND=0
	if [[ "${XDG_SESSION_TYPE:-}" == "wayland" && -n "${KDE_FULL_SESSION:-}" ]]; then
		IS_KDE_WAYLAND=1
	fi
	IS_MACOS=0
	[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=1

	HAS_XDG_OPEN=0
	command -v xdg-open >/dev/null 2>&1 && HAS_XDG_OPEN=1

	HAS_GIT=0
	command -v git >/dev/null 2>&1 && HAS_GIT=1

	HAS_CURL=0
	command -v curl >/dev/null 2>&1 && HAS_CURL=1

	HAS_FZF=0
	command -v fzf >/dev/null 2>&1 && HAS_FZF=1

	HAS_NETWORK=0
	if [[ "$HAS_CURL" -eq 1 ]]; then
		curl -s --max-time 2 -o /dev/null -I https://github.com && HAS_NETWORK=1
	fi
}
