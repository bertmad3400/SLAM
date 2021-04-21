#!/bin/sh

error() {
	echo "Error: $@"
	exit 1
}

dialog --title "Deploying Nuke" --infobox "Currently in the procces of cleaning $drive ..." 5 60
dd if=/dev/zero of="$drive" bs=1M count=1000 1> /dev/null

# For properly formating the newly cleared drive
# Will create on boot partition (based on the result from checkBootMode) and then one big root partition. Swap is in a swapfile
partitionDrive(){
	# For creating the boot partition and setting the disklabel to GPT for UEFI boot
	dialog --title "Partitioning drive..." --infobox "Currently in the procces of partitioning $drive" 5 60

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
					p	# Printing the partition table just before writing, for use in logfile
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
					p	# Printing the partition table just before writing, for use in logfile
					w	# Write the changes to the drive "
	fi

	sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<-EOF | fdisk "$drive"
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
	dialog --title "Mounting drive..." --infobox "Mounting $drive at /mnt" 5 60
	
	if [ "$bootMode" = "UEFI" ]
	then
		mount "${drive}2" /mnt

	elif [ "$bootMode" = "BIOS" ]
	then
		mount "${drive}1" /mnt
	fi
}

# Function for collecting all the functions for install arch on the selected drive
finishDrive () {
	partitionDrive
	createFS
	mountDrive

	genfstab -p -U /mnt >> /mnt/etc/fstab

	dialog --title "Using pacstrap" --infobox "Installing base, base-devel, linux, linux-firmware, dialog, git and doas" 5 60
	pacstrap /mnt base base-devel linux linux-firmware dialog git doas
}

finishDrive && cp ./SLAMGraphical.sh /mnt && arch-chroot /mnt ./SLAMGraphical.sh 
