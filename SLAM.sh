#!/bin/sh

error(){
	echo "Error: $@" 1>&2
	exit 1
}

echo "Refreshing keyrings..."
pacman --noconfirm -S archlinux-keyring || error "Make sure to run this script as root, with an internet connection."
pacman --noconfirm --needed -S dialog || error "Make sure to run this script as root, with an internet connection."

dialog --title "LET'S GO!" --yesno "With refreshed keyrings and dialog installed we're are ready to take this script for a spin. Please, DO NOT run it unless you fully understand the risk! This was developed by me for me only, and as such there might be errors that worst case could wipe entire drives. You sure you want to continue?" 10 60 || error "User exited"

./SLAMInput.sh

