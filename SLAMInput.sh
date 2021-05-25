#!/bin/sh

set -a

error() {
	echo "Script error: $@"
	exit 1
}

# Function for checking if the device is a laptop
checkLaptop() {
	[ -d /sys/module/battery ] && { dialog --title "Laptop?" --yesno "The device has been detected to be a laptop. Is that right?" 0 0 && deviceType="Laptop" || deviceType="Desktop"; } || { dialog --title "Desktop?" --yesno "The device has been detected to be a desktop. Is that right?" 0 0 && deviceType="Desktop" || deviceType="Laptop"; }

	dialog --title "$deviceType" --msgbox "The device has been registrered as a $deviceType" 6 39
}

# Function for checking whether it's booted as UEFI or BIOS
checkBootMode() {
	ls /sys/firmware/efi/efivars && { dialog --title "Boot-mode" --yesno "The detected boot mode is UEFI. Do you want the system to be installed as UEFI?" 0 0 && bootMode="UEFI" || bootMode="BIOS"; } || { dialog --title "Boot-mode" --yesno "The detected boot-mode is BIOS. Do you want the system to be install as BIOS?" 0 0 && bootMode="BIOS" || bootMode="UEFI"; }

	dialog --title "Boot-mode" --msgbox "The system will be installed as $bootMode" 6 39
}

# Function for choosing which drive to install on
locateInstallDrive() {
	drive="$(dialog --title "Select a drive" --no-items --menu "Which drive do you want the installation to procced on?" 0 0 0 $( for drive in $(lsblk -dno NAME); do echo /dev/"$drive"; done) 3>&2 2>&1 1>&3 || error "User exited" )"
}

# Function for taking an input and checking that it matches a regex and max length
verifyCredential(){

	credential=$(dialog --no-cancel --inputbox "Enter $1 for $2" 12 65 3>&1 1>&2 2>&3 3>&1)

	while [ "$(expr "$credential" : "$3")" = 0 ] || [ ${#credential} -gt $4 ]
	do
		credential="$(dialog --no-cancel --inputbox "The $1 contained illegal characthers or was too long. It shouldn't be longer than $4 and should fit the following regex: $3 " 14 70 3>&1 1>&2 2>&3 3>&1)"
	done

	echo $credential
}

# Function for making the user enter a password twice, and checking that they're the same to avoid misstyping it
getPass(){
	pass=$(dialog --no-cancel --passwordbox "Enter password for $1." 12 65 3>&1 1>&2 2>&3 3>&1)
	pass2=$(dialog --no-cancel --passwordbox "Retype the password for $1." 12 65 3>&1 1>&2 2>&3 3>&1)

	# Making sure the passwords match and aren't empty
	while [ "$pass" != "$pass2" ] || [ "$pass" = "" ]
	do
		pass="$(dialog --no-cancel --passwordbox "The passwords apparently didn't match or you entered an empty password which is not allowed. Please try and re-enter them" 12 65 3>&1 1>&2 2>&3 3>&1)"
		pass2="$(dialog --no-cancel --passwordbox "Retype the password for $1" 12 65 3>&1 1>&2 2>&3 3>&1)"
	done

	echo $pass
	unset pass pass2
}

getCredentials(){

	username="$(verifyCredential "username" "the new user" '^[a-z][-a-z0-9]*$' 32)"

	userPass="$(getPass "the new user")"
	dialog --title "Root account?" --yesno "Do you want to enable the root user?" 0 0 && rootPass="$(getPass "the root user")" || rootPass="!"

	hostname="$(verifyCredential "hostname" "the computer" '^[a-z][-a-z0-9]*$' 63)"

}

chooseInstallFonts(){
	fonts="noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra,Noto-fonts
adobe-source-code-pro-fonts adobe-source-sans-pro-fonts adobe-source-serif-pro-fonts,Adobe-fonts
ttf-dejavu,DejaVu-fonts
ttf-linux-libert,Linux-Libertine-fonts
gnu-free-fonts,GNU-Free-fonts
ttf-droid,Droid-fonts"

	fontChoices="$(dialog --title "Font install" --no-cancel --no-items --checklist "Choose which fonts to install:" 0 0 0 $(echo "$fonts" | cut -d ',' -f2 | sort | awk '{sum +=1; print $1" " sum}') 3>&1 1>&2 2>&3 3>&1)"

	for font in $fontChoices
	do
		installFonts="${installFonts} $(echo "$fonts" | grep "$font\$" | cut -d ',' -f1)"
	done

}

# SLAMGraphical is able to parse any of the CSV files in the repo to install the contents of them. This function chooses which should be used
chooseSoftwareBundles(){
	bundles="$(dialog --title "Bundle install" --no-cancel --no-items --checklist "Choose which software bundles you want to install:" 0 0 0 $(find ./CSVFiles -name "*.csv" | sed -e "s/\.csv//g;s/^.*\///g" | sort | awk '{sum +=1; print $1" " sum}') 3>&1 1>&2 2>&3 3>&1 )"
}

# SlamGraphical automatically adjusts some sudo privs, and it does also give the user the opportunity to select some commands, that should be able to be run as root without giving a password. This function chooses which it should be.
chooseRootCommands(){
	rootCommands="$(dialog --title "Commands as root" --no-cancel --no-items --checklist "Which commands should the user be able to run as root?" 0 0 0 \
		"/usr/bin/shutdown" "0" \
		"/usr/bin/reboot" "1" \
		"/usr/bin/systemctl suspend" "2" \
		"/usr/bin/mount" "3" \
		"/usr/bin/umount" "4" \
		"/usr/bin/pacman -Syu" "5" \
		3>&1 1>&2 2>&3 3>&1 )"
}

# Determine needed size of swap file based on RAM size + 2 GB
getSwapSize(){
	# Converting the output from KB to B and adding 2 GB
	swapSize="$(( $(grep MemTotal /proc/meminfo | sed 's/[^0-9]*//g') * 1024 + 2147483648 ))"
}

# For verifying the size of the drive, and wiping in and thereby preparing it for formating
verifyAndProcced() {
	driveSize="$(lsblk -bdn --output SIZE "$drive")"

	# Making sure the drive is the right size
	# Completly aborting if there isn't enough space
	if [ "$driveSize" -le 1073741824 ];
	then
		dialog --title "Too small" --msgbox "The selected drive, $drive, seem to be less than 1 GiB in size. This is simply to little space for the installation to continue, and as such, it will now end" 8 50; error "too little space on $drive"

	# Warning the user if there's less than 4 GiB available on the drive
	elif [ "$driveSize" -le 4294967296 ];
	then
		dialog --title "Very little space" --yes-label "I know what I'm doing" --no-label "Whoops, MB, abort!" --yesno "The selected drive, $drive, seem to be less than 4 GiB in size. This may be enough, but is very much an unsupported use-case for this script as there's a good chance that it's not. Are you sure you want to continue?" 8 60 || error "User exited as there is less than 4 GiB on the drive"

	# Making sure that the swap file doesn't take up more than half of the drive
	elif [ "$driveSize" -le $(( swapSize * 2 )) ];
	then
		dialog --title "Swap problems" --yes-label "Disable it" --no-label "Abort installation" --yesno "It seems like the swap file is bigger half of the drive, and as such the installation unfortunatly isn't able to continue. If you want to continue though, you can completly disable the swapfile?" 0 0 && swapSize=0 || error "User exited as the swap file was too big for the drive"
	fi

	# Given no errors, the program will no go onto warning the user that it's going to wipe the drive, and then procced with the script, which will wipe the drive
	dialog --title "WARNING!" --defaultno --yes-label "NUKE IT!" --no-label "Please don't..." --yesno "This script is readying to NUKE $drive. ARE YOU SURE YOU WANT TO CONTINUE?"  10 60 || error "User apparently didn't wan't to massacre $drive"
}

main(){
 checkLaptop; checkBootMode; locateInstallDrive; getCredentials; chooseRootCommands; chooseInstallFonts; chooseSoftwareBundles; getSwapSize; verifyAndProcced && ./SLAMMinimal.sh
}

main
