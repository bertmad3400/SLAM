#!/bin/sh

error() {
	echo "Error: $@"
	exit 1
}

set -a

# For properly formating the newly cleared drive
# Will create on boot partition (based on the result from checkBootMode) and then one big root partition. Swap is in a swapfile
partitionDrive(){
	# For creating the boot partition and setting the disklabel to GPT for UEFI boot
	dialog --title "Partitioning drive..." --infobox "Currently in the procces of partitioning $drive" 5 60

	if [ "$bootMode" = "UEFI" ]
	then
		partitionScheme="	label: gpt
							,512M,U;
							;"

	# For setting the disklabel to DOS for BIOS booting
	elif [ "$bootMode" = "BIOS" ]
	then
					partitionScheme="	label: dos
										;"
	fi

	sed "s/\s*\#.*$//" <<-EOF | sfdisk "$drive"
	$partitionScheme
	EOF
}

getPartitionPaths(){
	partitionPaths="$(lsblk $drive -o NAME,TYPE,SIZE -pnl | grep part)"

	if [ "$bootMode" = "UEFI" ]
	then
		part1="$(echo "$partitionPaths" | grep "M" | cut -d ' ' -f1)"
		part2="$(echo "$partitionPaths" | grep "G" | cut -d ' ' -f1)"
	elif [ "$bootMode" = "BIOS" ]
	then
		part1="$(echo "$partitionPaths" | cut -d ' ' -f1)"
	fi
	echo $part1
}

createFS(){
	dialog --title "Creating FS" --infobox "Creating the filesystem for $drive ..." 5 60
	if [ "$bootMode" = "UEFI" ]
	then
		yes | mkfs.fat -F32 "$part1"
		yes | mkfs.ext4 "$part2"

	elif [ "$bootMode" = "BIOS" ]
	then
		yes | mkfs.ext4 "$part1"

	fi
}

mountDrive(){
	dialog --title "Mounting drive..." --infobox "Mounting $drive at /mnt" 5 60

	if [ "$bootMode" = "UEFI" ]
	then
		mount "$part2" /mnt

	elif [ "$bootMode" = "BIOS" ]
	then
		mount "$part1" /mnt
	fi
}

# Function for collecting all the functions for install arch on the selected drive
finishDrive () {
	partitionDrive
	getPartitionPaths
	createFS
	mountDrive

	genfstab -p -U /mnt >> /mnt/etc/fstab

	dialog --title "Using pacstrap" --infobox "Installing base, base-devel, linux, linux-firmware, dialog and git" 5 60
	pacstrap /mnt base base-devel linux linux-firmware dialog git
}

# Functions for copying over files to new installation so that they can be run inside chroot
copyFiles (){
	# The directory on the new install that will store all needed files for further installation in chroot
	SLAMDir="/mnt/SLAM"

	# Create directory in the temp directory and the subdirectory needed for storing the csv files
	mkdir -p "${SLAMDir}/installFiles"

	# Add trap for cleanup
	trap "rm -rf $SLAMDir" INT TERM EXIT

	# Copy over the script the will be run in chroot
	cp ./SLAMGraphical.sh "$SLAMDir/"

	# Copy over the needed bundles and their depency files
	for bundle in $bundles
	do
		# Get the full path to the file stored in CSVFiles folder
		filepath="$(find . -name "${bundle}.csv")"
		# Copy over the file itself
		cp "$filepath" "${SLAMDir}/installFiles/"

		# Locate all potential depency files and custom install scripts and copy those over too
		for extraFile in $(grep -E "^D|^C" "$filepath" | cut -d ',' -f2)
		do
			cp "$extraFile" "${SLAMDir}/installFiles/"
		done

	done

	# Copy over custom profile for firefox
	cp -r ./firefoxProfile "$SLAMDir"

}
							# Redifine SLAMDir as the root point is changing from / to /mnt/
finishDrive && copyFiles && SLAMDir=$(echo "$SLAMDir" | sed "s/\/mnt//") && arch-chroot /mnt "${SLAMDir}/SLAMGraphical.sh"
