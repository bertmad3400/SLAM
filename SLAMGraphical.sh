#!/bin/sh

# For when encountering problems
error() {
	echo "Script error: $@"
	exit 1
}

pacIn(){
	pacman --noconfirm --needed -S $*
}

# Function for creating the swap file on the new system
createSwapFile(){
	# Making sure the size of the swap file is bigger than 1 byte. Would be 0 bytes if disabled due to drive size in SLAMInput.sh
	if [ 1 -le "$swapSize" ]
	then
		dialog --title "Swapfile" --infobox "Creating and setting up swapfile" 0 0
		fallocate -l "$swapSize" /swapfile
		chmod 600 /swapfile
		mkswap /swapfile
		swapon /swapfile
		cp /etc/fstab /etc/fstab.back
		echo '/swapfile none swap sw 0 0' >> /etc/fstab
	fi
}

# Function for configuring all these small things that don't really fit elsewhere
piecesConfig() {
	
	dialog --title "Configuring communcation" --infobox "Installing and enabling dhcpcd, NetworkManager and bluez" 0 0

	# Configuring network
	pacIn dhcpcd networkmanager bluez
	systemctl enable dhcpcd NetworkManager bluetooth

	dialog --title "Configuring..." --infobox "Configuring some beeps and boops. Shouldn't take long" 0 0

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

	# Create a few folders needed for a couple of things
	createFolders
}

# Some things like ZSH history won't work if the needed folders aren't available to store the needed files. Therefore this function creates those folders.
createFolders () {
	# Folder needed for ZSH command history
	mkdir -p "/home/$username/.cache/zsh"

	# Folders needed to store screenshots
	mkdir -p "/home/$username/Screenshots/Full" "/home/$username/Screenshots/Selection" "/home/$username/Screenshots/Focused"
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
	dialog --title "YAY install" --infobox "Currently in the proccess of making and installing YAY.." 0 0
	mkdir /tmp/yay
	cd /tmp/yay || error "Newly created folder /tmp/yay didn't exist. This is probably a problem with the script, please report it to the developer"
	git clone https://aur.archlinux.org/yay-git.git
	chown -R "$username" ./yay-git
	cd yay-git || error "Newly created yay-git folder didn't exist. This is probably a problem with the script, please report it to the developer"
	doas -u "$username" -- makepkg -si --noconfirm
}

deployDotFiles(){
	doas -u "$username" -- git clone --bare https://github.com/bertmad3400/dootfiles.git "/home/$username/.dootfiles.git"

	# Overwrite any existing file
	doas -u "$username" -- /usr/bin/git --git-dir="/home/$username/.dootfiles.git" --work-tree="/home/$username/" reset --hard

	# Deploy the dotfiles
	doas -u "$username" -- /usr/bin/git --git-dir="/home/$username/.dootfiles.git" --work-tree="/home/$username/" checkout
}

gitIn(){

	echo "$1" | grep -q "https:.*\/" || error "The git package $1 doesn't seem to be a url"
	packageName="$(echo "$1" | sed "s/^.*\///g;s/\..*//g" )"

	programPath="${gitPath}/${packageName}/"

	# Making sure the user has write perms to the folder used for git source code
	chown "$username" "$gitPath"

	doas -u "$username" -- git clone "$1" "$programPath"

	cd "$programPath"

	make
	make install
}

installPackages(){
	# $1 is the csv file containing packages to install
	[ -f "$1" ] || error "$1 was not found. This seems to be an error with the script, please report it to the developers"

	# Create directory for installing git
	mkdir -p "/home/$username/.local/src/"

	# Reset count of numbers of packages
	currentPackageCount=0

	totalPackageCount="$(wc -l < "$1")"
	while IFS=, read -r tag package purpose
	do
		currentPackageCount=$(( $currentPackageCount + 1 ))

		dialog --title "Installing..." --infobox "Installing $package from $TAG ($currentPackageCount out of $totalPackageCount from $1). $package is $purpose" 0 0

		case $tag in
			M ) pacIn $package;;
			A ) doas -u "$username" -- yay -S --noconfirm "$package";;
			G ) gitIn "$package" ;;
			L ) [ "$deviceType" = "Laptop" ] && doas -u "$username" -- yay -S --noconfirm $package;;
			D ) dialog --title "Dependencies" --infobox "Installing $package which is ${purpose}."; installPackages "$(echo "$package" | sed "s/^.*\///g")" ;;
			* ) dialog --title "What??" --infobox "It seems that $package didn't have a tag, or it weren't recognized. Did you use the official files? If so please contact the developers. Skipping it for now" 0 0; echo "Error with following: \n package: $package \n tag: $tag \n purpose: $purpose \n" 1>> missingPackages; sleep 10 ;;
		esac
	done < "$1"
}

installSoftware(){
	installYAY
	deployDotFiles

	# The path in which git will clone repos
	gitPath="/home/$username/.local/src"
	mkdir -p "$gitPath"
	for bundle in $bundles; do installPackages "${SLAMDir}/CSVFiles/${bundle}.*"; done
}

configureFirefox(){
	dialog --title "Firefox profile" --infobox "Creating new default firefox profile optimized for a private browsing experience" 5 30

	# Make sure the script is in the right folder
	cd "/home/$username/.mozilla/firefox/"

	# Create the new firefox profile
	firefox -CreateProfile privacy

	# Move the needed files into the folder
	cp -r "/firefoxProfile/*" "/home/$username/.mozilla/firefox/*.privacy"

	# Make the new profile the default by replacing the name of the default entry in profiles with the one ending in .privacy and create a backup with the i option
	sed -i.bak "s/Default=.*\..*/$(grep '[a-zA-Z0-9]*\.privacy$' profiles.ini)/" profiles.ini


}

configureBootloader(){
	if [ "$bootMode" = "UEFI" ]
	then
		dialog --title "Bootloader" --infobox "Creating UEFI bootloader using GRUB..." 0 0
		pacIn efibootmgr grub
		mkdir /boot/efi
		mount "${drive}1" /boot/efi
		grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi
		grub-mkconfig -o /boot/grub/grub.cfg

	elif [ "$bootMode" = "BIOS" ]
	then
		dialog --title "Bootloader" --infobox "Creating BIOS bootloader using GRUB..." 0 0
		pacIn grub
		grub-install "$drive"
		grub-mkconfig -o /boot/grub/grub.cfg
	fi
}

dialog --title "Refreshing keyrings..." --infobox "Refreshing the keyrings on the new system. This is probably no needed, but is done to make sure that everything is going to go smoothly" 0 0
pacman --noconfirm -S archlinux-keyring || error "Somehow the keyrings couldn't be refreshed. You unfortunatly probably need to run the script again"

configureInstall
installSoftware
pacman -Qs firefox > /dev/null && configureFirefox
configureBootloader
