#!/bin/bash
# lib/fonts.sh
#
# Font download/install helpers for the Alacritty + zsh + p10k setup wizard.

# Name of the most recently installed Nerd Font, used by the font menu.
NEWLY_INSTALLED_FONT=""

# install_nerd_font <name>
# Downloads the named Nerd Font (e.g. JetBrainsMono) from the official
# nerd-fonts release and installs it under ~/.local/share/fonts.
install_nerd_font() {
	local name="$1"
	if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
		ui_info "[dry-run] Would download and install ${name} Nerd Font."
		return 0
	fi
	if [[ "${HAS_NETWORK:-0}" -ne 1 ]]; then
		ui_error "No network connectivity detected; skipping font download."
		return 1
	fi

	local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${name}.zip"
	ui_info "Downloading ${url} ..."
	local tmp
	tmp="$(mktemp -d)"
	if ! curl -fsSL "$url" -o "$tmp/${name}.zip"; then
		ui_error "Download failed."
		rm -rf "$tmp"
		return 1
	fi
	mkdir -p "$HOME/.local/share/fonts"
	unzip -oq "$tmp/${name}.zip" -d "$HOME/.local/share/fonts/${name}NerdFont"
	rm -rf "$tmp"

	if command -v fc-cache >/dev/null 2>&1; then
		fc-cache -f >/dev/null 2>&1
	fi

	# Figure out the exact family name that appeared in fontconfig.
	if command -v fc-list >/dev/null 2>&1; then
		NEWLY_INSTALLED_FONT="$(fc-list -f "%{family}\n" | grep -i "${name}.*Nerd Font" | head -1 | cut -d',' -f1)"
		NEWLY_INSTALLED_FONT="${NEWLY_INSTALLED_FONT# }"
		NEWLY_INSTALLED_FONT="${NEWLY_INSTALLED_FONT% }"
	fi

	ui_success "Installed ${name} Nerd Font."
}

# install_font_awesome
# Optional helper that clones the Font Awesome repo and copies the OTF/TTF
# font files into ~/.local/share/fonts/FontAwesome. This is separate from the
# terminal font: the terminal uses a monospaced Nerd Font, which already
# bundles Font Awesome glyphs. The original Font Awesome fonts are useful for
# desktop/web apps, not as a terminal font.
install_font_awesome() {
	if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
		ui_info "[dry-run] Would install Font Awesome desktop font files."
		return 0
	fi
	if [[ "${HAS_NETWORK:-0}" -ne 1 ]]; then
		ui_error "No network connectivity detected; skipping Font Awesome download."
		return 1
	fi
	if ! command -v git >/dev/null 2>&1; then
		ui_error "git is required to clone Font Awesome."
		return 1
	fi

	local tmp
	tmp="$(mktemp -d)"
	ui_info "Cloning Font Awesome into ${tmp} ..."
	if ! git clone --depth 1 https://github.com/FortAwesome/Font-Awesome.git "$tmp/font-awesome"; then
		ui_error "Font Awesome clone failed."
		rm -rf "$tmp"
		return 1
	fi

	mkdir -p "$HOME/.local/share/fonts/FontAwesome"
	find "$tmp/font-awesome/otfs" "$tmp/font-awesome/webfonts" -maxdepth 1 -type f \( -iname "*.otf" -o -iname "*.ttf" \) -exec cp -t "$HOME/.local/share/fonts/FontAwesome" {} +
	rm -rf "$tmp"

	if command -v fc-cache >/dev/null 2>&1; then
		fc-cache -f >/dev/null 2>&1
	fi

	ui_success "Installed Font Awesome desktop/web font files."
}

# is_nerd_font <family>
# Returns 0 if the family looks like a Nerd Font.
is_nerd_font() {
	[[ "$1" == *"Nerd Font"* ]]
}
