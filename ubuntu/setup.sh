#!/bin/bash
set -eu

TOOL_DIR="$HOME/src/tools"
DUMP_DIR="$HOME/dump"
SCRIPT_DIR="$(pwd)"
UBUNTU_VM_DIR="${HOME}/ubuntu_vm"
SRC_DIR="$HOME/src"

usage() {
	USAGE="$0 command [OPTIONS..]\n\n

	Helper scripts.\n

	command:\n\t
		alias		: Update alias.\n\t
		nvim		: Update neovim.\n\t
		tmux		: Update tmux.\n\t
		fio		: Update fio.\n\t
		date		: Update date and time.\n\t
		lei		: Update lei.\n\t
		ubuntu_vm	: Create a ubuntu vm.\n\t
		get_src		: Get source code for Linux, fio.\n\t
		revealjs	: revealjs setup.\n\t
		help		: help.\n\n
	Sample: usage\n\t
	$0 nvim\n\t
	$0 nvme -v\n"
	echo -ne $USAGE
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

update_latex() {
	if ! command -v zathura &> /dev/null ; then
		echo "zathura could not be found, installing now.."
		sudo apt install texlive latexmk texlive-latex-extra -y
		sudo apt install texlive-fonts-extra default-jre zathura -y
	fi
	if [ ! -d "~/.config/zathura" ]; then
		mkdir -p ~/.config/zathura/
	fi

	check_create_link ${SCRIPT_DIR}/config_files/zathurarc ~/.config/zathura/zathurarc
}

update_nvim() {
	local nvim_config=~/.config/nvim

	if ! command -v nvim &> /dev/null ; then
		echo "neovim could not be found, installing now.."
		cd $TOOL_DIR
		sudo apt install git ninja-build gettext cmake -y
		sudo apt install unzip curl fonts-powerline ripgrep -y
		sudo apt install locales-all -y
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
		git stash
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
	
	sed -i "s|-- { import = 'custom.plugins' },|{ import = 'custom.plugins' },|g" \
		${HOME}/.config/nvim/init.lua
			sed -i "s|nmap('<C-k>', vim.lsp.buf.signature_help, 'Signature Documnetation')|-- nmap('<C-K>', vim.lsp.vuf.signature_help, 'Signature Documentation')|g" \
				${HOME}/.config/nvim/init.lua

	check_create_link ${TOOL_DIR}/dotfiles/vim_options.lua ~/.config/nvim/lua/custom/plugins/vim_options.lua
	check_create_link ${TOOL_DIR}/dotfiles/tmux_navigator.lua ~/.config/nvim/lua/custom/plugins/tmux_navigator.lua
	check_create_link ${TOOL_DIR}/dotfiles/vimtex.lua ~/.config/nvim/lua/custom/plugins/vimtex.lua
	git config --global core.editor "nvim"
	sudo update-alternatives --install /usr/bin/editor editor $(which nvim) 10
	update_npm
	update_latex
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
	check_create_link ${TOOL_DIR}/dotfiles/tmux.conf ~/.tmux.conf
}

update_fio() {
	if [ -d "${HOME}/src/fio" ]; then
		cd ${HOME}/src/fio
		git pull
	else
		mkdir -p ${HOME}/src
		cd ${HOME}/src
		git clone https://github.com/axboe/fio.git
		cd fio
	fi
	make -j$(nproc)
	sudo make install
	fio --version
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

update_lei() {
	local lkml_dir=${HOME}/.lkml
	local user_email first_name second_name smtp_secret

	if ! command -v lei &> /dev/null ; then
		echo "lei could not be found"
		sudo apt install -y liburi-perl libdbd-sqlite3-perl \
			libsearch-xapian-perl libplack-perl \
			libinline-c-perl libemail-address-xs-perl \
			libparse-recdescent-perl libmail-imapclient-perl \
			libbsd-resource-perl \
			libplack-middleware-reverseproxy-perl \
			libhighlight-perl xapian-tools libxapian-dev \
			curl liblinux-inotify2-perl libnet-server-perl \
			libdbi-perl libsocket6-perl libcrypt-cbc-perl \
			libtimedate-perl
		sudo apt install libsearch-xapian-perl python3-pip gnome-keyring -y
		sudo apt install procmail -y
		# pip install keyring
		sudo apt install python3-keyring
		cd ${TOOL_DIR}
		# git clone https://public-inbox.org/public-inbox.git
		cd public-inbox
		perl Makefile.PL
		make
		sudo make install
	fi
	if ! command -v neomutt &> /dev/null ; then
		echo "neomutt could not be found"
		sudo apt install neomutt -y
	fi
	if ! command -v notmuch &> /dev/null ; then
		echo "notmuch could not be found"
		sudo apt install notmuch -y
	fi

	if [ ! -d "${lkml_dir}/mail" ]; then
		mkdir -p ${lkml_dir}/mail
	fi
	echo "input user email and name name in below format: email first_name second_name smtp_secret"
	read user_email first_name second_name smtp_secret
	echo "$user_email $first_name $second_name $smtp_secret"

	cd ${SCRIPT_DIR}
	cp config_files/muttrc ${lkml_dir}/
	sed -i "s|lkml_dir|${lkml_dir}|g" $lkml_dir/muttrc
	sed -i -e "s/user_email/${user_email}/g" $lkml_dir/muttrc
	sed -i -e "s/first_name/${first_name}/g" $lkml_dir/muttrc
	sed -i -e "s/second_name/${second_name}/g" $lkml_dir/muttrc
	sed -i -e "s/smtp_secret/${smtp_secret}/g" $lkml_dir/muttrc

	cp config_files/vim-keys.rc ${lkml_dir}/
	sed -i "s|lkml_dir|${lkml_dir}|g" $lkml_dir/vim-keys.rc

	if [ ! -d "${lkml_dir}/patches" ]; then
		mkdir -p ${lkml_dir}/patches
	fi
	if [ ! -d "${lkml_dir}/bin" ]; then
		mkdir -p ${lkml_dir}/bin
	fi
	cp config_files/from-mutt ${lkml_dir}/

	cp config_files/notmuch.rc ${lkml_dir}/
	sed -i "s|lkml_dir|${lkml_dir}|g" $lkml_dir/notmuch.rc
	sed -i -e "s/user_email/${user_email}/g" $lkml_dir/notmuch.rc
	sed -i -e "s/first_name/${first_name}/g" $lkml_dir/notmuch.rc
	sed -i -e "s/second_name/${second_name}/g" $lkml_dir/notmuch.rc
	check_create_link ${lkml_dir}/notmuch.rc ~/.notmuch-config
	cp config_files/notmuch-tag-rules ${lkml_dir}/notmuch-tag-rules
	sed -i -e "s/user_email/${user_email}/g" $lkml_dir/notmuch-tag-rules

	cp config_files/sync.sh ${lkml_dir}/
	sed -i "s|lkml_dir|${lkml_dir}|g" ${lkml_dir}/sync.sh
	chmod a+x ${lkml_dir}/sync.sh

	lei q -I https://lore.kernel.org/all -o ${lkml_dir}/mail --threads \
		--dedupe=mid \
		'(tc:linux-nvme OR tc:linux-block OR tc:linux-fsdevel OR tc:io-uring) AND rt:1.days.ago..'
	#if you get aborted error, kill the previous daemon using lei daemon-kill
	# this usually happens if some dependency tool is not installed
	lei up ${lkml_dir}/mail


	# if ! command -v getmail &> /dev/null ; then
	# 	echo "getmail could not be found"
	# 	sudo apt install getmail6 -y
	# fi
	#
	# if [ ! -d "${HOME}/.getmail" ]; then
	# 	mkdir -m 700 ${HOME}/.getmail
	# fi
	# cp config_files/getmailrc ${lkml_dir}/
	# sed -i "s|lkml_dir|${lkml_dir}|g" $lkml_dir/getmailrc
	# sed -i -e "s/user_email/${email}/g" $lkml_dir/getmailrc
	# check_create_link ${lkml_dir}/getmailrc ${HOME}/.getmail/getmail
	# getmail

	notmuch new
	notmuch tag --batch --input=${lkml_dir}/notmuch-tag-rules
	notmuch tag --remove-all +deleted tag:deleted

	echo "Please append below in bashrc alias mymutt=\"neomutt -F $lkml_dir/muttrc\""
}

setup_ubuntu_vm() {
	local ubuntu_image=ubuntu-24.04-minimal-cloudimg-amd64.img

	if [ ! -d "${UBUNTU_VM_DIR}" ]; then
		mkdir -p ${UBUNTU_VM_DIR}
	fi
	cd ${UBUNTU_VM_DIR}

	if [ ! -f "$ubuntu_image}" ]; then
		wget --no-check-certificate https://cloud-images.ubuntu.com/minimal/releases/noble/release/${ubuntu_image}
	fi

	if ! command -v cloud-localds &> /dev/null ; then
		sudo apt install -y cloud-image-utils -y
	fi
	cloud-localds ${UBUNTU_VM_DIR}/user-seed.img ${SCRIPT_DIR}/config_files/vm_user_data -d qcow2

	if ! command -v qemu-img &> /dev/null ; then
		sudo apt install -y qemu-utils -y
	fi
	qemu-img create -f qcow2 -b ${UBUNTU_VM_DIR}/${ubuntu_image} -F qcow2 ${UBUNTU_VM_DIR}/backing.qcow2
	qemu-img resize ${UBUNTU_VM_DIR}/backing.qcow2 32G
	#this can be reused for resizeing as well in future

	qemu-img create -f qcow2 ${UBUNTU_VM_DIR}/nvm.qcow2 5G
	cp ${SCRIPT_DIR}/config_files/vm-nvme.cfg ${UBUNTU_VM_DIR}/nvme.cfg
	sed -i "s|UBUNTU_VM_DIR|${UBUNTU_VM_DIR}|g" ${UBUNTU_VM_DIR}/nvme.cfg
	sudo usermod -aG kvm "$(whoami)"
	sudo chmod +666 /dev/kvm
	# sudo usermod -aG libvirtd "$(whoami)"
}

get_src_linux() {
	cd $SRC_DIR
	if [ ! -d "$SRC_DIR/linux-block" ]; then
		echo "Cloning Linux"
		git clone https://git.kernel.org/pub/scm/linux/kernel/git/axboe/linux-block.git
		sudo apt install -y libncurses5-dev gcc make exuberant-ctags git bc flex bison libssl-dev pahole libelf-dev rsync
	fi
}

get_src_fio() {
	cd $SRC_DIR
	if [ ! -d "$SRC_DIR/fio" ]; then
		echo "Cloning Fio"
		git clone https://github.com/axboe/fio.git
	fi
}

get_src() {
	get_src_linux
	get_src_fio
}

get_revealjs() {
	if [ ! -d "$TOOL_DIR/reveal.js" ]; then
		cd $TOOL_DIR
		echo "Cloning revealjs"
		git clone https://github.com/hakimel/reveal.js.git
		sudo apt install -y gulp
	fi
	cd $TOOL_DIR/reveal.js
	npm install
	npm start
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
		fio )
			update_fio
			;;
		date )
			update_date
			;;
		lei )
			update_lei
			;;
		ubuntu_vm )
			setup_ubuntu_vm
			;;
		get_src )
			get_src
			;;
		revealjs )
			get_revealjs
			;;
		test )
			local lkml_dir=${HOME}/.lkml
			lei q -I https://lore.kernel.org/all -o ${lkml_dir}/mail --threads \
				--dedupe=mid \
				'(tc:linux-nvme OR tc:linux-block OR tc:linux-fsdevel OR tc:io-uring) AND rt:1.days.ago..'
			;;
		* )
			usage
			;;
	esac
}

setup $@
