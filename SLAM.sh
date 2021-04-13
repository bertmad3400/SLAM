#!/bin/sh

# For when encountering problems
error() {

	echo "Error: $@" 1>&2
	exit 1

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

# Only used for debugging, will maybe remove
main() {
	echo "Refreshing keyrings..."
	pacman --noconfirm -S archlinux-keyring 2> ErrorLog || error "Make sure to run this script as root, with an internet connection."
	pacman --noconfirm --needed -S dialog 2> ErrorLog || error "Make sure to run this script as root, with an internet connection."

	dialog --title "LET'S GO!" --yesno "With refreshed keyrings and dialog installed we're are ready to take this script for a spin. Please, DO NOT run it unless you fully understand the risk! This was developed by me for me only, and as such there might be errors that worst case could wipe entire drives. You sure you want to continue?" 10 60 || error "User exited"

	checkBootMode
	locateInstallDrive
}

