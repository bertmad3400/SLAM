#!/bin/sh

# Function for checking whether it's booted as UEFI or BIOS
checkBootMode() {

	ls /sys/firmware/efi/efivars && { dialog --title "Boot-mode" --yesno "The detected boot mode is UEFI. Is that right?" && bootMode="UEFI" || bootMode="BIOS"} || { dialog --title "Boot-mode" --yesno "The detected boot-mode is BIOS. Is that right?" && bootMode="BIOS" || bootMode="UEFI"}

	dialog --title "Boot-mode" --msgbox "The boot-mode has been set to $bootMode" 6 39

}

# Function for choosing which drive to install on
locateInstallDrive() {

	lsblk -o NAME | tail -n +2 -f - | grep -v '[0-9]'

}

echo "Refreshing keyrings..."
pacman --noconfirm -Sy archlinux-keyring 2> ErrorLog || { echo "Make sure to run this script as root, with an internet connection"; exit 1; }
pacman --noconfirm --needed -Sy dialog || { echo "Make sure to run this script as root, with an internet connection."; exit 1; }

dialog --title "LET'S GO!" --yesno "With refreshed keyrings and dialog installed we're are ready to take this script for a spin. Please, DO NOT run it unless you fully understand the risk! This was developed by me for me only, and as such there might be errors that worst case could wipe entire drives. You sure you want to continue?" 10 60 || { echo "User exited"; exit 1; }

checkBootMode


