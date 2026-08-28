#!/bin/bash
# lib/ui.sh
#
# Screen / prompt / menu primitives for the Alacritty configuration wizard.
# All functions are careful to degrade gracefully when `tput` or a real TTY
# are unavailable (e.g. when driven non-interactively for testing).

# Optional global set by callers before ask_choice to mark a recommended
# option (0-based index) and make it the initial highlight.
UI_RECOMMENDED_INDEX=""

# --- low level terminal helpers ------------------------------------------

_ui_tput() {
	# Run tput if available and connected to a terminal; otherwise no-op.
	if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
		tput "$@" 2>/dev/null
	fi
}

ui_init() {
	UI_COLS="$(_ui_tput cols)"
	UI_COLS="${UI_COLS:-80}"
	_ui_tput civis
}

ui_cleanup() {
	_ui_tput cnorm
	_ui_tput sgr0
}

ui_clear() {
	if [[ -t 1 ]]; then
		_ui_tput clear
	fi
}

ui_color() {
	# ui_color <sgr-name...> -- prints the escape sequence, empty if unsupported
	_ui_tput "$@"
}

ui_rule() {
	printf '%*s\n' "${UI_COLS:-80}" '' | tr ' ' '-'
}

ui_header() {
	# ui_header "Step N/17" "Title text"
	local step="$1" title="$2"
	ui_clear
	printf '%s\n' "$(ui_color bold)Alacritty Configuration Wizard$(ui_color sgr0)  —  $step"
	ui_rule
	printf '%s\n\n' "$(ui_color bold)$title$(ui_color sgr0)"
}

# ui_footer [n]
# If <n> is given, shows the valid numeric quick-select range.
# Always lists the navigation meta keys.
ui_footer() {
	local n="${1:-}"
	printf '\n'
	ui_rule
	if [[ -n "$n" ]]; then
		if ((n <= 9)); then
			printf '[1-%s] select   [j/k or up/down] move   [Enter] confirm   [b] back   [r] restart   [q] quit\n' "$n"
		else
			printf '[1-9] quick-select   [j/k or up/down] move   [Enter] confirm   [b] back   [r] restart   [q] quit\n'
		fi
	else
		printf '[b] back   [r] restart   [q] quit\n'
	fi
}

ui_info() {
	printf '%s\n' "$1"
}

ui_warn() {
	printf '%s%s%s\n' "$(ui_color setaf 3)" "$1" "$(ui_color sgr0)"
}

ui_error() {
	printf '%s%s%s\n' "$(ui_color setaf 1)" "$1" "$(ui_color sgr0)" >&2
}

ui_success() {
	printf '%s%s%s\n' "$(ui_color setaf 2)" "$1" "$(ui_color sgr0)"
}

# --- key reading -----------------------------------------------------------

# ui_read_key <var>
# Reads a single logical keypress into <var>. Recognizes arrow keys as
# UP/DOWN/LEFT/RIGHT, Enter as ENTER, and everything else literally.
ui_read_key() {
	local -n _out="$1"
	local k
	IFS= read -rsn1 k
	if [[ "$k" == $'\x1b' ]]; then
		local k2 k3
		IFS= read -rsn1 -t 0.01 k2
		IFS= read -rsn1 -t 0.01 k3
		case "$k2$k3" in
		"[A") _out="UP" ;;
		"[B") _out="DOWN" ;;
		"[C") _out="RIGHT" ;;
		"[D") _out="LEFT" ;;
		*) _out="ESC" ;;
		esac
	elif [[ -z "$k" ]]; then
		_out="ENTER"
	else
		_out="$k"
	fi
}

# --- menu / choice widgets -------------------------------------------------

# ask_choice <result_var> <preview_fn|-> <label1> <label2> ... -- <value1> <value2> ...
#
# Renders a numbered, arrow-navigable menu. <preview_fn> is called with the
# currently highlighted index (0-based) every time the highlight moves, or
# pass "-" to disable live preview. Returns via <result_var> the chosen
# *value* (not label). Caller is expected to have already printed a header
# and any body text above the menu via ui_header/ui_info.
ask_choice() {
	local -n _result="$1"
	local preview_fn="$2"
	shift 2

	local -a labels=()
	while [[ "$1" != "--" ]]; do
		labels+=("$1")
		shift
	done
	shift # consume --
	local -a values=("$@")

	local n="${#labels[@]}"
	# Consume and clear the global recommendation index so it does not
	# leak into later menus. Empty means "no recommendation".
	local rec="${UI_RECOMMENDED_INDEX-}"
	UI_RECOMMENDED_INDEX=""
	local idx=0
	if [[ -n "$rec" ]] && ((rec >= 0 && rec < n)); then
		idx="$rec"
	fi
	local key

	# Save the cursor position at the top of the menu area so we can
	# restore and clear below it on every redraw, keeping arrow-key
	# navigation crisp instead of scrolling the screen.
	_ui_tput sc

	while true; do
		# Restore to the saved menu top and clear everything below it.
		_ui_tput rc
		_ui_tput ed

		local i
		for i in "${!labels[@]}"; do
			local label="${labels[$i]}"
			[[ -n "$rec" && "$i" -eq "$rec" ]] && label="$label (recommended)"
			if [[ "$i" -eq "$idx" ]]; then
				printf '  %s> %2d) %s%s\n' "$(ui_color setaf 6)" "$((i + 1))" "$label" "$(ui_color sgr0)"
			else
				printf '    %2d) %s\n' "$((i + 1))" "$label"
			fi
		done

		if [[ "$preview_fn" != "-" ]]; then
			"$preview_fn" "$idx"
		fi

		ui_footer "$n"
		ui_read_key key

		case "$key" in
		UP | k)
			idx=$(((idx - 1 + n) % n))
			;;
		DOWN | j)
			idx=$(((idx + 1) % n))
			;;
		ENTER)
			_result="${values[$idx]}"
			return 0
			;;
		[0-9])
			if ((key >= 1 && key <= n)); then
				idx=$((key - 1))
				_result="${values[$idx]}"
				return 0
			fi
			# Invalid digit falls through and just redraws.
			;;
		b)
			return 2
			;;
		r)
			return 3
			;;
		q)
			return 4
			;;
		esac
	done
}

# ask_yn <result_var> <prompt> <default: y|n>
ask_yn() {
	local -n _result="$1"
	local prompt="$2" default="${3:-y}"
	local suffix="[y/n]"
	[[ "$default" == "y" ]] && suffix="[Y/n]"
	[[ "$default" == "n" ]] && suffix="[y/N]"

	local first=1
	while true; do
		if [[ "$first" -eq 1 ]]; then
			printf '%s %s: ' "$prompt" "$suffix"
			first=0
		else
			printf '\r%s %s: ' "$prompt" "$suffix"
		fi
		ui_footer
		local key
		ui_read_key key
		printf '\n'
		case "$key" in
		y | Y)
			_result="y"
			return 0
			;;
		n | N)
			_result="n"
			return 0
			;;
		ENTER)
			_result="$default"
			return 0
			;;
		b)
			return 2
			;;
		r)
			return 3
			;;
		q)
			return 4
			;;
		esac
	done
}

# ask_number <result_var> <preview_fn|-> <prompt> <min> <max> <step> <initial>
# +/- adjust, Enter accepts, numeric digits+Enter allow direct typed entry.
ask_number() {
	local -n _result="$1"
	local preview_fn="$2" prompt="$3" min="$4" max="$5" step="$6" val="$7"

	_ui_tput sc
	local first=1
	while true; do
		_ui_tput rc
		_ui_tput ed
		printf '%s: %s%*s\n' "$prompt" "$val" 10 ''
		if [[ "$first" -eq 1 ]]; then
			first=0
		fi

		if [[ "$preview_fn" != "-" ]]; then
			"$preview_fn" "$val"
		fi

		ui_footer
		ui_read_key key
		case "$key" in
		"+" | UP | k)
			val="$(awk -v v="$val" -v s="$step" -v mx="$max" 'BEGIN{r=v+s; if (r>mx) r=mx; printf "%g", r}')"
			;;
		"-" | DOWN | j)
			val="$(awk -v v="$val" -v s="$step" -v mn="$min" 'BEGIN{r=v-s; if (r<mn) r=mn; printf "%g", r}')"
			;;
		ENTER)
			printf '\n'
			_result="$val"
			return 0
			;;
		b)
			printf '\n'
			return 2
			;;
		r)
			printf '\n'
			return 3
			;;
		q)
			printf '\n'
			return 4
			;;
		esac
	done
}

# ui_pause "message"
ui_pause() {
	printf '%s ' "${1:-Press any key to continue...}"
	local key
	ui_read_key key
	printf '\n'
}

# ui_confirm_quit -- returns 0 if the user confirms quitting
ui_confirm_quit() {
	local ans
	ask_yn ans "Quit without saving?" "n"
	local rc=$?
	# If the user pressed 'q' at the confirmation prompt, treat it as
	# a firm quit request. Otherwise, only a 'y' confirms the quit.
	[[ "$rc" -eq 4 || "$ans" == "y" ]]
}
