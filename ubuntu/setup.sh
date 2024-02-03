#!/bin/bash
set -ex

TOOL_DIR="$HOME/src/tools"
DUMP_DIR="$HOME/dump"
SCRIPT_DIR="$(pwd)"

usage() {
	USAGE="$0 command [OPTIONS..]\n\n

	Helper scripts.\n

	command:\n\t
		alias		: Setup alias.\n\t
		nvim		: Update neovim.\n\t
		tmux		: Update tmux.\n\t
		date		: Update date and time.\n\t
		lei		: Update lei.\n\t
		help		: help.\n"
	echo $USAGE
}

create_dir() {
	if [ ! -d "${TOOL_DIR}" ]; then
		mkdir -p ${TOOL_DIR}
	fi
	if [ ! -d "${DUMP_DIR}" ]; then
		mkdir -p ${DUMP_DIR}
	fi
}

update_alias() {
	ln -s $SCRIPT_DIR/config_files/bash_aliases ~/.bash_aliases
}

update_npm() {
	sudo apt install npm -y
	sudo npm cache clean -f
	sudo npm install -g n
	sudo n stable
	sudo npm install npm@latest -g
}

check_create_link() {
	src_path="$1"
	dst_path="$2"

	if [[ -L "$dst_path" ]]; then
		if [[ -e "dst_path" ]]; then
			echo "A valid link already exist for $dst_path"
		else
			unlink "$dst_path"
			echo "Cleaned up broken link: $dst_path"
			ln -s $src_path $dst_path
		fi
	else
		ln -s $src_path $dst_path
	fi
}

update_nvim() {
	local nvim_config=~/.config/nvim

	if ! command -v nvim &> /dev/null ; then
		echo "neovim could not be found, installing now.."
		cd $TOOL_DIR
		sudo apt install git ninja-build gettext cmake -y
		sudo apt install unzip curl fonts-powerline ripgrep -y
	fi
	
	cd $TOOL_DIR
	if [ -d "${TOOL_DIR}/neovim" ]; then
		cd neovim
		git pull
	else
		git clone https://github.com/neovim/neovim
		cd neovim
	fi
	# git checkout stable
	make CMAKE_BUILD_TYPE=RelWithDebInfo
	sudo make install

	if [ -d "${nvim_config}" ]; then
		cd ${nvim_config}
		git pull
	else
		cd $TOOL_DIR
		git clone https://github.com/nvim-lua/kickstart.nvim.git ~/.config/nvim
	fi

	cd $TOOL_DIR
	if [ -d "${TOOL_DIR}/dotfiles" ]; then
		cd ${TOOL_DIR}/dotfiles
		git pull
	else
		cd ${TOOL_DIR}
		git clone https://github.com/nitesh-shetty/dotfiles.git
	fi
	
	sed -i "s|-- { import = 'custom.plugins' },|{ import = 'custom.plugins' },|g" ${HOME}/.config/nvim/init.lua
	check_create_link ${TOOL_DIR}/dotfiles/init.lua ~/.config/nvim/lua/custom/plugins/my.lua
	git config --global core.editor "nvim"
	sudo update-alternatives --install /usr/bin/editor editor $(which nvim) 10
	update_npm
}

update_tmux() {
	if ! command -v tmux &> /dev/null ; then
		sudo apt install tmux -y
	fi
	if [ -d "${HOME}/.tmux/plugins/tpm" ]; then
		cd ~/.tmux/plugins/tpm
		git pull
	else
		git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugin/tpm
	fi
	if [ -d "${TOOL_DIR}/dotfiles" ]; then
		cd ${TOOL_DIR}/dotfiles
		git pull
	else
		cd $TOOL_DIR
		git clone https://github.com/nitesh-shetty/dotfiles.git
	fi
	check_create_link ${TOOL_DIR}/dotfiles/.tmux.conf ~/.tmux.conf
}

update_date() {
	local date time
	echo "input date and time in below format: YYYY-MM-DD HH:MM:SS"
	read date time
	echo "date $date $time"
	sudo timedatectl set-timezone Asia/Kolkata
	sudo date --set="$date $time"
	sudo hwclock --systohc
}

setup() {
	if [[ $# -lt 1 ]]; then
		usage
		return 1
	fi	

	create_dir
	local subcmd="$1"; shift
	case "$subcmd" in
		alias )
			update_alias
			;;
		nvim )
			update_nvim
			;;
		tmux )
			update_tmux
			;;
		date )
			update_date
			;;
		* )
			usage
			;;
	esac
}

setup $@
