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
	dialog --title "WARNING!" --yes-label "NUKE IT!" --no-label "Please don't..." --yesno "This script is readying to NUKE $drive. ARE YOU SURE YOU WANT TO CONTINUE?"  10 60 && dialog --title "Nuke deploying" --infobox "Currently in the procces of cleaning $drive ..." 5 60 && dd if=/dev/zero of="$drive" bs=512 count=1 1> /dev/null 2> ErrorLog || error "User apparently didn't wan't to massacre $drive"
}

getCredentials(){
	rootPass=$(dialog --no-cancel --passwordbox "Enter password for the root user." 12 65 3>&1 1>&2 2>&3 3>&1)
	rootPass2=$(dialog --no-cancel --passwordbox "Retype the password for the root user" 12 65 3>&1 1>&2 2>&3 3>&1)
	while [ "$rootPass" != "$rootPass2" ]
	do
		rootPass="$(dialog --no-cancel --passwordbox "The passwords apparently didn't match. Please try and re-enter them" 12 65 3>&1 1>&2 2>&3 3>&1)"
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
}


}

# Only used for debugging, will maybe remove
main() {
	echo "Refreshing keyrings..."
	pacman --noconfirm -S archlinux-keyring 2> ErrorLog || error "Make sure to run this script as root, with an internet connection."
	pacman --noconfirm --needed -S dialog 2> ErrorLog || error "Make sure to run this script as root, with an internet connection."

	dialog --title "LET'S GO!" --yesno "With refreshed keyrings and dialog installed we're are ready to take this script for a spin. Please, DO NOT run it unless you fully understand the risk! This was developed by me for me only, and as such there might be errors that worst case could wipe entire drives. You sure you want to continue?" 10 60 || error "User exited"

	checkBootMode
	locateInstallDrive
	prepareDrive
}

main
