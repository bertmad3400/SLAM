#!/bin/sh

set -a

error() {
	echo "Script error: $*" | tee -a logs/errorLog 1>&2
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
	drive="$(dialog --title "Select a drive" --no-items --menu "Which drive do you want the installation to procced on?" 0 0 0 $( for drive in $(lsblk -dno NAME); do echo /dev/"$drive"; done) 3>&2 2>&1 1>&3 || error "User exited" )"
}

getCredentials(){
	rootPass=$(dialog --no-cancel --passwordbox "Enter password for the root user." 12 65 3>&1 1>&2 2>&3 3>&1)
	rootPass2=$(dialog --no-cancel --passwordbox "Retype the password for the root user" 12 65 3>&1 1>&2 2>&3 3>&1)
	while [ "$rootPass" != "$rootPass2" ] || [ "$rootPass" = "" ]
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

	while ! [ "$userPass" = "$userPass2" ] || [ "$userPass" = "" ]
	do
		userPass="$(dialog --no-cancel --passwordbox "The passwords apparently didn't matchor you entered an empty password which is not allowed. Please try and re-enter them" 12 65 3>&1 1>&2 2>&3 3>&1)"
		userPass2="$(dialog --no-cancel --passwordbox "Retype the password for the new user" 12 65 3>&1 1>&2 2>&3 3>&1)"
	done

	hostname=$(dialog --no-cancel --inputbox "Enter a hostname for the computer" 12 65 3>&1 1>&2 2>&3 3>&1)

	while [ "$(expr "$hostname" : ^[a-z][-a-z0-9]*\$)" = 0 ]
	do
		hostname="$(dialog --no-cancel --inputbox "The hostname contained illegal characthers. It should start with lower case letters and only contain lower case letters and numbers, fitting the following regex: : ^[a-z][-a-z0-9]*\\$ " 14 70 3>&1 1>&2 2>&3 3>&1)"
	done

}

# SLAMGraphical is able to parse any of the CSV files in the repo to install the contents of them. This function chooses which should be used
chooseSoftwareBundles(){
	bundles="$(dialog --title "Bundle install" --no-items --checklist "Choose which software bundles you want to install:" 0 0 0 $(ls | grep -i "csv" | sed -e 's/\.csv//g' | awk '{sum +=1; print $1" " sum}') 3>&1 1>&2 2>&3 3>&1 || error "User exited")"
}

# Determine needed size of swap file based on RAM size + 2 GB
getSwapSize(){
	# Converting the output from KB to B and adding 2 GB
	swapSize="$(( $(grep MemTotal /proc/meminfo | sed 's/[^0-9]*//g') * 1024 + 2147483648 ))"
}

# For verifying the size of the drive, and wiping in and thereby preparing it for formating
verifyAndProcced() {
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
	dialog --title "WARNING!" --defaultno --yes-label "NUKE IT!" --no-label "Please don't..." --yesno "This script is readying to NUKE $drive. ARE YOU SURE YOU WANT TO CONTINUE?"  10 60 || error "User apparently didn't wan't to massacre $drive"
}

main(){
 checkLaptop; checkBootMode; locateInstallDrive; getCredentials; chooseSoftwareBundles; getSwapSize; verifyAndProcced && ./SLAMMinimal.sh
}

main
