#!/bin/sh

# For when encountering problems
error() {
	echo "Script error: $@"
	exit 1
}

pacIn(){
	pacman --noconfirm --needed -S "$*" 1>> logs/installLogs/pacman
}

# Function for creating the swap file on the new system
createSwapFile(){
	dialog --title "Swapfile" --infobox "Creating and setting up swapfile" 0 0
	fallocate -l "$swapSize" /swapfile
	chmod 600 /swapfile
	mkswap /swapfile
	swapon /swapfile
	cp /etc/fstab /etc/fstab.back
	echo '/swapfile none swap sw 0 0' >> /etc/fstab
}

# Function for configuring all these small things that don't really fit elsewhere
piecesConfig() {
	
	dialog --title "Configuring communcation" --infobox "Installing and enabling dhcpcd, NetworkManager and bluez" 0 0
	# Configuring network
	pacIn dhcpcd
	systemctl enable dhcpcd
	pacIn networkmanager
	systemctl enable NetworkManager
	pacIn bluez
	systemctl enable bluetooth

	dialog --title "Configuring..." --infobox "Configuring some beeps and boops. Shouldn't take long"

	# Setting the local timezone
	ln -sf /usr/share/zoneinfo/Europe/Copenhagen /etc/localtime

	# Generate /etc/adjtime
	hwclock --systohc

	# Set the systemclock to be accurate. Using sed for removing leading whitespace needed for proper indention
	timedatectl set-ntp true

	echo "da_DK.UTF-8 UTF-8
		da_DK ISO-8859-1" | sed -e 's/^\s*//' 1>> /etc/local.gen

	# Generate needed locales
	locale-gen

	# Set the system locale
	echo "LANG=da_DK.UTF-8" 1> /etc/local.conf

	# Set the keyboard layout permanently
	echo "KEYMAP=dk" 1> /etc/vconsole.conf

	# Set the hostname
	echo "$hostname" 1> /etc/hostname

	# Set entries for hosts file for localhost ip's
	echo "	127.0.0.1	localhost
		::1		localhost
		127.0.1.1	$hostname.local	$hostname" | sed -e 's/^\s*//' 1>> /etc/hosts


	# Make pacman and yay colorful and adds eye candy on the progress bar because why not.
	grep -q "^Color" /etc/pacman.conf || sed -i "s/^#Color$/Color/" /etc/pacman.conf
	grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
}

configureUsers(){
	# Set the root-password
	echo "root:$rootPass" | chpasswd

	# Create new user and add it to needed/wanted groups
	useradd -m -s /bin/zsh -g users -G wheel,audio,input,optical,storage,video "$username"

	echo "${username}:${userPass}" | chpasswd
}

# Give the user permission to run any command as root without password and the root user permissions to run any command as the user, which is needed to run YAY. Will change to normal perms at script exit
configurePerms(){
	echo "permit nopass root as $username" 1> /etc/doas.conf
	echo "%wheel ALL=(ALL) NOPASSWD: ALL #SLAM" 1>> /etc/sudoers
	trap 'echo "permit persist :wheel" > /etc/doas.conf; sed -i "/#SLAM/d" /etc/sudoers; echo "%wheel ALL=(ALL) ALL #LARBS" >> /etc/sudoers' INT TERM EXIT
}

# Collection function used for configuring new install
configureInstall(){
	createSwapFile
	piecesConfig
	configureUsers
	configurePerms
}

installYAY(){
	dialog --infobox "Installing YAY..." 4 50
	cd /opt || error "/Opt apparently didn't exist"
	git clone https://aur.archlinux.org/yay-git.git
	chown -R "$username" ./yay-git
	cd yay-git || error "Newly created yay-git folder didn't exist. This is probably a problem with the script, please report it to the developer"
	doas -u "$username" -- makepkg -si
}

deployDotFiles(){
	doas -u "$username" -- git clone --bare https://github.com/bertmad3400/dootfiles.git "/home/$username/.dootfiles.git"

	# Overwrite any existing file
	doas -u "$username" -- /usr/bin/git --git-dir="$HOME/.dotfiles/" --work-tree="$HOME" reset --hard

	# Deploy the dotfiles
	doas -u "$username" -- /usr/bin/git --git-dir="$HOME/.dotfiles/" --work-tree="$HOME" checkout
}

# The next 3 functions are used for installing software from arch repos, AUR and git. $1 is the package name, $2 is the purpose of the program, $3 is what csv file the package name has been sourced from and $4 is the url of the package for git
mainRepoIn(){
	dialog --title "Installing..." --infobox "Installing $1 from main repo ($currentPackageCount out of $totalPackageCount from $3). $1 is $2" 0 0
	pacIn "$1"
}

AURIn(){
	dialog --title "Installing..." --infobox "Installing $1 from main repo ($currentPackageCount out of $totalPackageCount from $3). $1 is $2" 0 0
	doas -u "$username" -- yay -S --noconfirm "$1"
}

gitIn(){
	dialog --title "Installing..." --infobox "Installing $1 from git ($currentPackageCount out of $totalPackageCount from $3). $1 is $2" 0 0

	programPath="home/$username/.local/src/$1"

	doas -u "$username" -- git clone "$4" "$programPath"

	make
	make install
}

installPackages(){
	# $1 is the csv file containing packages to install
	[ -f "$1" ] || error "$1 was not found. This seems to be an error with the script, please report it to the developers"

	# Create directory for installing git
	mkdir -p "/home/$username/.local/src/"

	totalPackageCount="$(wc -l < "$1")"
	while IFS=, read -r tag package purpose
	do
		# Used for removing the url part from git package name
		echo "$package" | grep -q "https:.*\/" && gitName="$(echo "$package" | sed "s/\(^\"\|\"$\)//g")"
		currentPackageCount=$(( $currentPackageCount + 1 ))

		case $tag in
			M ) mainRepoIn "$package" "$purpose" "$1" ;;
			A ) AURIn "$package" "$purpose" "$1" ;;
			G ) gitIn "$gitName" "$purpose" "$1" "$package" ;;
			L ) [ "$deviceType" = "Laptop" ] && AURIn "$package" "$purpose" "$1" ;;
			* ) dialog --title "What??" --infobox "It seems that $package didn't have a tag, or it weren't recognized. Did you use the official files? If so please contact the developers. Skipping it for now" 0 0; echo "Error with following: \n package: $package \n tag: $tag \n purpose: $purpose \n" 1>> logs/installLogs/missingPackage; sleep 10 ;;
		esac
	done < "$1"
}

installSoftware(){
	installYAY
	deployDotFiles
	for bundle in bundles; do installPackages $bundle; done
}

configureBootloader(){
	if [ "$bootMode" = "UEFI" ]
	then
		echo "Creating BIOS bootloader"
		pacIn efibootmgr grub
		mkdir /boot/efi
		mount "${drive}1" /boot/efi
		grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi
		grub-mkconfig -o /boot/grub/grub.cfg

	elif [ "$bootMode" = "BIOS" ]
	then
		echo "Creating BIOS bootloader"
		pacIn grub
		grub-install "$drive"
		grub-mkconfig -o /boot/grub/grub.cfg
	fi
}

echo "Refreshing the keyrings for the new system. Probably not needed, but better safe than sorry"
pacman --noconfirm -S archlinux-keyring || error "Somehow the keyrings couldn't be refreshed. You unfortunatly probably need to run the script again"

configureInstall
installSoftware
