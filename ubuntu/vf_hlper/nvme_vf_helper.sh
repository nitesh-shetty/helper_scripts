#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2025 Nitesh Shetty <nitheshshetty@gmail.com>
# helper script to VF and driver management

set -eu

#DEVICE, this will be initilized in parse_options function
#BDF, this will be initilized in parse_options function
#DRIVER, this will be initilized in parse_options function

usage() {
	USAGE="$0 command [OPTIONS..]\n\n

	This script helps in managing VFs and driver functionality\n

	command:\n\t
		cvf	: Create Virtural Function(enable SR-IOV) for a NVMe device\n\t
		dvf	: Destroy Virtural Function(disable SR-IOV) for a NVMe device\n\t
		adb	: Attach a Driver to Bdf\n\t 
		help	: help\n\n

	options:\n\t
		-d	: device\n\t
		-b	: device BDF\n\t
		-k	: driver name to attach\n\t
		-v	: verbose\n\n

	sample command:\n\t
		$0 cvf -d /dev/nvme4\n\t
		$0 adb -b 0000:ca:04.0 -k libnvm_helper\n\t
		$0 adb -b 0000:ca:04.0 -k nvme\n\t
		$0 dvf -d /dev/nvme4\n\t
		$0 help\n"

		echo -ne $USAGE
}

parse_options() {
	local user_device=none user_bdf=none user_driver=none

	while getopts "hvd:b:k:" opt; do
		case $opt in
			v ) set -x;;
			h ) usage;;
			d ) user_device="$OPTARG";;
			b ) user_bdf="$OPTARG";;
			k ) user_driver="$OPTARG";;
		esac
	done

	#check for mandotory options
	if [ "$SUBCMD" == "cvf" ] || [ "$SUBCMD" == "dvf" ]; then
		if [ "$user_device" == "none" ]; then
			echo "Device info (-d) is missing !!. See below for more info"
			usage
			return 1
		fi
	fi
	if [ "$SUBCMD" == "adb" ]; then
		if [ "$user_bdf" == "none" ]; then
			echo "BDF info (-b) is missing !!"
			echo "Possible BDF values:"
			lspci -D | grep -i Vol
			echo -ne "\nSee below for more info\n"
			usage
			return 1
		fi
		if [ "$user_driver" == "none" ]; then
			echo "Driver info (-k) is missing !!. See below for more info"
			usage
			return 1
		fi
	fi

	echo -ne "Test Parameters:\n\t"
	echo -ne "command: $SUBCMD\n\t"
	if [ "$SUBCMD" == "cvf" ] || [ "$SUBCMD" == "dvf" ]; then
		DEVICE=$user_device
		echo -ne "device: $DEVICE\n"
	fi
	if [ "$SUBCMD" == "adb" ]; then
		BDF=$user_bdf
		DRIVER=$user_driver
		echo "bdf: $BDF"
		echo "driver: $DRIVER"
	fi
}

get_primary_ctrl_caps_feat() {
	local feature=$1

	if ! command -v jq &> /dev/null ; then
		echo "jq could not be found, installing now.."
		sudo apt install jq -y
	fi

	echo $(sudo nvme primary-ctrl-caps $DEVICE -o json | jq .$feature)
}

get_cntl_id() {
	get_primary_ctrl_caps_feat cntlid
}

get_secondary_vq_max() {
	get_primary_ctrl_caps_feat vqfrsm
}

get_secondary_vi_max() {
	get_primary_ctrl_caps_feat vifrsm
}

create_vfs() {
	local device=$DEVICE
	local dev_bname=$(basename $device)
	local bdf drv_sysfs dev_sysfs
	local nr_vfs=${2:-1}
	local vbdf i
	local vq_max=$(get_secondary_vq_max)
	local vi_max=$(get_secondary_vi_max)

	if [ ! -e "/sys/class/nvme/$dev_bname" ]; then
		echo "Failed to find sysfs: /sys/class/nvme/$dev_bname"
		return 1
	fi
	bdf=$(basename $(readlink /sys/class/nvme/$dev_bname/device))
	dev_sysfs="/sys/bus/pci/devices/$bdf"
	drv_sysfs="/sys/bus/pci/drivers/nvme"

	# stop the nvme drivers from autoprobing and failing wrong allocation
	echo 0 | sudo tee $dev_sysfs/sriov_drivers_autoprobe

	# remove all the vf's
	echo 0 | sudo tee $dev_sysfs/sriov_numvfs
	
	for (( i=1; i<=nr_vfs; i++ )); do
		# take the controller $i offline
		sudo nvme virt-mgmt $device -c $i -a 7
		# allcoate vq resources
		sudo nvme virt-mgmt $device -c $i -a 8 -r 0 -n $vq_max
		# allcoate vi resources
		sudo nvme virt-mgmt $device -c $i -a 8 -r 1 -n $vi_max
	done

	# allocate vf's, after this lscpi shows multiple bdf's
	echo ${nr_vfs} | sudo tee $dev_sysfs/sriov_numvfs

	for (( i=1; i<=nr_vfs; i++ )); do
		# fucntion lelel reset
		vbdf="$(basename $(readlink $dev_sysfs/virtfn$(($i-1))))"
		echo 1 | sudo tee /sys/bus/pci/devices/$vbdf/reset

		# transition the controller to online state
		sudo nvme virt-mgmt $device -c $i -a 9

		# nvme driver binding
		echo "nvme" | sudo tee $dev_sysfs/virtfn$((i-1))/driver_override
		echo $vbdf | sudo tee $drv_sysfs/bind
	done
	echo "Successful in creating $nr_vfs secondary controller with $((vq_max-1)) IO queues"
	sudo nvme list -v
}

destroy_vfs() {
	local device=$DEVICE
	local dev_bname=$(basename $device)
	local bdf dev_sysfs nr_vfs
	local cntl_id=$(get_cntl_id)

	if [ ! -e "/sys/class/nvme/$dev_bname" ]; then
		echo "Failed to find the sysfs: /sys/class/nvme/$dev_bname"
		return 1
	fi

	bdf=$(basename $(readlink /sys/class/nvme/$dev_bname/device))
	dev_sysfs="/sys/bus/pci/devices/$bdf"
	nr_vfs=$(cat $dev_sysfs/sriov_numvfs)

	sudo nvme virt-mgmt $device -c $cntl_id -r 1 -a 1 -n 0
	sudo nvme virt-mgmt $device -c $cntl_id -r 0 -a 1 -n 0
	sudo nvme reset $device
	echo 1 | sudo tee /sys/bus/pci/rescan

	for (( i=1; i<=nr_vfs; i++ )); do
		sudo nvme virt-mgmt $device -c $i -r 0 -a 8 -n 0
		sudo nvme virt-mgmt $device -c $i -r 1 -a 8 -n 0
	done
	echo 1 | sudo tee /sys/bus/pci/rescan

	echo 0 | sudo tee $dev_sysfs/sriov_drivers_autoprobe
	echo 0 | sudo tee $dev_sysfs/sriov_numvfs
	sudo nvme primary-ctrl-caps $device -c $cntl_id -H
	echo "Successful in destroying secondary controllers"
}

attach_driver_to_bdf() {
	local bdf=$BDF
	local bdf_driver=$DRIVER
	local dev_sysfs="/sys/bus/pci/devices/$bdf"
	local drv_sysfs="/sys/bus/pci/drivers/$bdf_driver"
	local vid did

	if sudo lspci -k -s $bdf | grep "driver in use" | grep $bdf_driver; then
		echo "Driver $bdf_driver is already attached to $bdf"
		return 0
	fi

	vid=$(lspci -n -s $bdf | cut -d' ' -f3 | cut -d':' -f1)
	did=$(lspci -n -s $bdf | cut -d' ' -f3 | cut -d':' -f2)

	if ! echo $vid $did | sudo tee $drv_sysfs/new_id; then
		echo $vid $did | sudo tee $drv_sysfs/remove_id
		echo $vid $did | sudo tee $drv_sysfs/new_id
	fi
	echo $bdf_driver | sudo tee $dev_sysfs/driver_override
	if [ -e "$dev_sysfs/driver/unbind" ]; then
		echo $bdf | sudo tee $dev_sysfs/driver/unbind
	fi
	echo $bdf | sudo tee $drv_sysfs/bind
	echo "Successful in attaching $bdf_driver to $bdf"
}

setup() {
	if [[ $# -lt 1 ]]; then
		usage
		return 1
	fi

	echo "$0: Start"
	SUBCMD="$1"; shift
	
	parse_options $@

	case "$SUBCMD" in
		cvf )
			create_vfs
			;;
		dvf )
			destroy_vfs
			;;
		adb )
			attach_driver_to_bdf
			;;
		* )
			usage
			;;
	esac
			
	echo "$0: Complete"
}


setup $@
