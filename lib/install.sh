#!/bin/bash
# lib/install.sh
#
# Installer phase for the Alacritty + zsh + p10k setup wizard.

# install_log <desc> -- wrapper that respects DRY_RUN.
install_log() {
	if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
		ui_info "[dry-run] would run: $1"
	else
		ui_info "$1"
	fi
}

# install_eval <desc> <cmd> -- runs a shell command unless in dry-run.
install_eval() {
	local desc="$1" cmd="$2"
	if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
		ui_info "[dry-run] $ ${cmd}"
		return 0
	fi
	ui_info "$desc"
	ui_info "  $ ${cmd}"
	eval "$cmd" || return 1
}

# install_sudo <desc> <cmd> -- runs a command with sudo unless in dry-run.
install_sudo() {
	local desc="$1" cmd="$2"
	if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
		ui_info "[dry-run] $ sudo ${cmd}"
		return 0
	fi
	ui_info "$desc"
	ui_info "  $ sudo ${cmd}"
	if ! sudo -n true 2>/dev/null; then
		ui_warn "The next step requires sudo: $desc"
	fi
	sudo sh -c "$cmd" || return 1
}

# install_packages
# Installs the apt packages the wizard needs for Alacritty, zsh, and font handling.
install_packages() {
	if ! command -v apt-get >/dev/null 2>&1; then
		ui_warn "apt-get not found. Please install alacritty, zsh, git, curl, unzip, and fontconfig manually."
		return 0
	fi

	install_sudo "Update apt package list" "apt-get update"
	install_sudo "Install base packages" "apt-get install -y alacritty zsh git curl unzip fontconfig"
}

# install_ohmyzsh
# Downloads and installs Oh My Zsh unattended (does not launch zsh or run chsh).
install_ohmyzsh() {
	if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
		ui_info "[dry-run] Would install Oh My Zsh."
		return 0
	fi
	if [[ -d "$HOME/.oh-my-zsh" ]]; then
		ui_info "Oh My Zsh is already installed at ~/.oh-my-zsh; skipping."
		return 0
	fi
	if [[ "${HAS_NETWORK:-0}" -ne 1 ]]; then
		ui_error "No network connectivity; cannot install Oh My Zsh."
		return 1
	fi

	local installer
	installer="$(mktemp)"
	if ! curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$installer"; then
		ui_error "Failed to download the Oh My Zsh installer."
		rm -f "$installer"
		return 1
	fi

	install_eval "Install Oh My Zsh" "RUNZSH=no CHSH=no sh \"$installer\" --unattended"
	rm -f "$installer"
}

# install_powerlevel10k
# Clones the powerlevel10k theme into the Oh My Zsh custom themes directory.
install_powerlevel10k() {
	if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
		ui_info "[dry-run] Would clone Powerlevel10k."
		return 0
	fi
	local p10k_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
	if [[ -d "$p10k_dir" ]]; then
		ui_info "Powerlevel10k is already installed; skipping."
		return 0
	fi
	if [[ "${HAS_NETWORK:-0}" -ne 1 ]]; then
		ui_error "No network connectivity; cannot clone Powerlevel10k."
		return 1
	fi
	if ! command -v git >/dev/null 2>&1; then
		ui_error "git is required to install Powerlevel10k."
		return 1
	fi

	install_eval "Clone Powerlevel10k" "mkdir -p \"$HOME/.oh-my-zsh/custom/themes\" && git clone --depth 1 https://github.com/romkatv/powerlevel10k.git \"$p10k_dir\""
}

# set_zsh_default
# Changes the user's default shell to zsh, if they confirm.
set_zsh_default() {
	local zsh_bin
	zsh_bin="$(command -v zsh 2>/dev/null || true)"
	[[ -z "$zsh_bin" ]] && return 0

	local ans
	ask_yn ans "Make zsh the default login shell?" "n"
	local rc=$?
	[[ "$rc" -ne 0 ]] && return "$rc"
	if [[ "$ans" != "y" ]]; then
		return 0
	fi

	if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
		ui_info "[dry-run] chsh -s ${zsh_bin}"
		return 0
	fi
	ui_info "Changing default shell to zsh ..."
	chsh -s "$zsh_bin" || ui_warn "chsh failed; please run 'chsh -s $(command -v zsh)' manually."
}
