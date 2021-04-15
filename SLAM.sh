#!/bin/sh

# For when encountering problems
error() {
	echo "Error: $@" 1>&2
	exit 1
}

# Function for checking if the device is a laptop
checkLaptop() {
	[ -d /sys/module/battery ] && { dialog --title "Laptop?" --yesno "The device has been detected to be a laptop. Is that right?" 0 0 && deviceType="Laptop" || deviceType="Desktop"; } || { dialog --title "Desktop?" --yesno "The device has been detected to be a desktop. Is that right?" 0 0 && deviceType="Desktop" || deviceType="Laptop"; }

	dialog --title "$deviceType" --msgbox "The device has been registrered as a $deviceType" 6 39
}

# Function for checking whether it's booted as UEFI or BIOS
checkBootMode() {
	ls /sys/firmware/efi/efivars && { dialog --title "Boot-mode" --yesno "The detected boot mode is UEFI. Is that right?" 0 0 && bootMode="UEFI" || bootMode="BIOS"; } || { dialog --title "Boot-mode" --yesno "The detected boot-mode is BIOS. Is that right?" 0 0 && bootMode="BIOS" || bootMode="UEFI"; }

	dialog --title "Boot-mode" --msgbox "The boot-mode has been set to $bootMode" 6 39
}

# Function for choosing which drive to install on
locateInstallDrive() {
	drive=$(dialog --title "Select a drive" --no-items --menu "Which drive do you want the installation to procced on?" 24 80 17 $( for drive in $(lsblk -dno NAME); do echo /dev/$drive; done) 3>&2 2>&1 1>&3)
}

# For verifying the size of the drive, and wiping in and thereby preparing it for formating
prepareDrive() {
	driveSize="$(lsblk -b --output SIZE -n -d "$drive")"

	# Making sure the drive is the right size
	# Completly aborting if there isn't enough space
	if [ "$driveSize" -le 1073741824 ];
	then
		dialog --title "Too small" --msgbox "The selected drive, $drive, seem to be less than 1 GiB in size. This is simply to little space for the installation to continue, and as such, it will not end" 8 50; error "too little space on $drive"
	
	# Warning the user if there's less than 4 GiB available on the drive
	elif [ "$driveSize" -le 4294967296 ];
	then
		dialog --title "Very little space" --yes-label "I know what I'm doing" --no-label "Whoops, MB, abort!" --yesno "The selected drive, $drive, seem to be less than 4 GiB in size. This may be enough, but is very much an unsupported use-case for this script as there's a good chance that it's not. Are you sure you want to continue?" 8 60 || error "User exited as there is less than 4 GiB on the drive"
	fi


	# Given no errors, the program will no go onto warning the user that it's going to wipe the drive, and then wipe it
	dialog --title "WARNING!" --defaultno --yes-label "NUKE IT!" --no-label "Please don't..." --yesno "This script is readying to NUKE $drive. ARE YOU SURE YOU WANT TO CONTINUE?"  10 60 && dialog --title "Deploying Nuke" --infobox "Currently in the procces of cleaning $drive ..." 5 60 && dd if=/dev/zero of=$drive bs=1M count=1000 1> /dev/null 2> ErrorLog || error "User apparently didn't wan't to massacre $drive"
}

getCredentials(){
	rootPass=$(dialog --no-cancel --passwordbox "Enter password for the root user." 12 65 3>&1 1>&2 2>&3 3>&1)
	rootPass2=$(dialog --no-cancel --passwordbox "Retype the password for the root user" 12 65 3>&1 1>&2 2>&3 3>&1)
	while [ "$rootPass" != "$rootPass2" -o "$rootPass" = "" ]
	do
		rootPass="$(dialog --no-cancel --passwordbox "The passwords apparently didn't matchor you entered an empty password which is not allowed. Please try and re-enter them" 12 65 3>&1 1>&2 2>&3 3>&1)"
		rootPass2="$(dialog --no-cancel --passwordbox "Retype the password for the root user" 12 65 3>&1 1>&2 2>&3 3>&1)"
	done

	username=$(dialog --no-cancel --inputbox "Enter username for the new user" 12 65 3>&1 1>&2 2>&3 3>&1)

	while [ "$(expr "$username" : ^[a-z][-a-z0-9]*\$)" = 0 ]
	do
		username="$(dialog --no-cancel --inputbox "The username contained illegal characthers. It should start with lower case letters and only contain lower case letters and numbers, fitting the following regex: : ^[a-z][-a-z0-9]*\\$ " 14 70 3>&1 1>&2 2>&3 3>&1)"
	done

	userPass="$(dialog --no-cancel --passwordbox "Enter password for the new user." 12 65 3>&1 1>&2 2>&3 3>&1)"
	userPass2="$(dialog --no-cancel --passwordbox "Retype the password for the new user" 12 65 3>&1 1>&2 2>&3 3>&1)"

	while ! [ "$userPass" = "$userPass2" ]
	do
		userPass="$(dialog --no-cancel --passwordbox "The passwords apparently didn't match. Please try and re-enter them" 12 65 3>&1 1>&2 2>&3 3>&1)"
		userPass2="$(dialog --no-cancel --passwordbox "Retype the password for the new user" 12 65 3>&1 1>&2 2>&3 3>&1)"
	done

	hostname=$(dialog --no-cancel --inputbox "Enter a hostname for the computer" 12 65 3>&1 1>&2 2>&3 3>&1)

	while [ "$(expr "$hostname" : ^[a-z][-a-z0-9]*\$)" = 0 ]
	do
		hostname="$(dialog --no-cancel --inputbox "The hostname contained illegal characthers. It should start with lower case letters and only contain lower case letters and numbers, fitting the following regex: : ^[a-z][-a-z0-9]*\\$ " 14 70 3>&1 1>&2 2>&3 3>&1)"
	done

}

# Function for getting all the needed user input. Will be run in the very start of the script.
getUserInput(){

	checkLaptop
	checkBootMode
	locateInstallDrive
	prepareDrive
	getCredentials

}

# Determine needed size of swap file based on RAM size + 2 GB
getSwapSize(){
	# Converting the output from KB to B and adding 2 GB
	swapSize="$(expr "$(grep MemTotal /proc/meminfo | sed 's/[^0-9]*//g')" \* 1024 + 2147483648)"
}

# For properly formating the newly cleared drive
# Will create on boot partition (based on the result from checkBootMode) and then one big root partition. Swap is in a swapfile
formatDrive(){
	# For creating the boot partition and setting the disklabel to GPT for UEFI boot
	if [ "$bootMode" = "UEFI" ]
	then
		partitionScheme="	g 	# For making sure the drive has a GPT disklabel instead of DOS/MBR
					n 	# Create the boot partition
						# Chosing the default partition number
						# Default first sector, let it start at the start of the disk
					+512M	# Make the boot partition 512 MB in size
					t	# Change the type of the partition
					1	# Set it to type 1, or EFI System
					n	# Create the root partition
						# Chosing the default partition number
						# Default first sector, let it start at the of free space on disk
						# Default last sector, letting it take the rest of the space
					w	# Write changes to disk "

	# For setting the disklabel to DOS for BIOS booting
	elif [ "$bootMode" = "BIOS" ]
	then
		partitionScheme="	o	# For creating DOS disklabel
					n	# Create the partition
						# Chosing the default partition type
						# Chosing the default partition number
						# Default first sector, let it start at the start of free space on disk
						# Default last sector, letting it take the rest of the space
					w	# Write the changes to the drive "
	fi

	sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<-EOF | fdisk $drive
	$partitionScheme
	EOF
}

createFS(){

	dialog --title "Creating FS" --infobox "Creating the filesystem for $drive ..." 5 60
	if [ "$bootMode" = "UEFI" ]
	then
		yes | mkfs.fat -F32 "${drive}1"
		yes | mkfs.ext4 "${drive}2"

	elif [ "$bootMode" = "BIOS" ]
	then
		yes | mkfs.ext4 "${drive}1"
	fi

}

mountDrive(){

	if [ "$bootMode" = "UEFI" ]
	then
		mount "${drive}2" /mnt

	elif ["$bootMode" = "BIOS"]
	then
		mount "${drive}1" /mnt
	fi
}

# Function for collecting all the functions for install arch on the selected drive
finishDrive () {
	getSwapSize
	formatDrive
	createFS
	mountDrive

	dialog --title "Using pacstrap" --infobox "Installing base, base-devel, linux, linux-firmware, dialog, git and doas" 5 60
	pacstrap /mnt base base-devel linux linux-firmware dialog git doas
}

# Function for creating the swap file on the new system
createSwapFile(){
	fallocate -l "$swapSize" /swapfile
	chmod 600 /swapfile
	mkswap /swapfile
	swapon /swapfile
	cp /etc/fstab /etc/fstab.back
	echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
}

# Function for configuring all these small things that don't really fit elsewhere
piecesConfig() {
	# Setting the local timezone
	ln -sf /usr/share/zoneinfo/Europe/Copenhagen /etc/localtime

	# Generate /etc/adjtime
	hwclock --systohc

	# Set the systemclock to be accurate. Using sed for removing leading whitespace needed for proper indention
	timedatectl set-ntp true

	echo "da_DK.UTF-8 UTF-8
		da_DK ISO-8859-1" | sed -e 's/^\s*//' >> /etc/local.gen

	# Generate needed locales
	locale-gen

	# Set the system locale
	echo "LANG=da_DK.UTF-8" > /etc/local.conf

	# Set the keyboard layout permanently
	echo "KEYMAP=dk" > /etc/vconsole.conf

	# Set the hostname
	echo "$hostname" > /etc/hostname

	# Set entries for hosts file for localhost ip's
	echo "	127.0.0.1	localhost
		::1		localhost
		127.0.1.1	$hostname.local	$hostname" | sed -e 's/^\s*//' >> /etc/hosts

	# Configuring network
	systemctl enable dhcpcd
	pacman -S networkmanager
	systemctl enable NetworkManager
}

# Only used for debugging, will maybe remove
main() {
	echo "Refreshing keyrings..."
	pacman --noconfirm -S archlinux-keyring 2> ErrorLog || error "Make sure to run this script as root, with an internet connection."
	pacman --noconfirm --needed -S dialog 2> ErrorLog || error "Make sure to run this script as root, with an internet connection."

	dialog --title "LET'S GO!" --yesno "With refreshed keyrings and dialog installed we're are ready to take this script for a spin. Please, DO NOT run it unless you fully understand the risk! This was developed by me for me only, and as such there might be errors that worst case could wipe entire drives. You sure you want to continue?" 10 60 || error "User exited"

	getUserInput
}

main
