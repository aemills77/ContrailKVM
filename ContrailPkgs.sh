#!/bin/bash

# ContrailPkgs.sh
# Author: Arthur "Damon" Mills
# Last Update: 5.31.2018
# Version: .4
# License: GPLv3

# Usage: Execute without passing arguments
#
# Designed for usage on Ubuntu 14.04.5 LTS for Juniper Contrail CSO
# Assumed Default user account name: juniper
# KVM Packages installed following:
# https://help/ubuntu.com/community/KVM/Installation

# function declarations

function installapt()
{
    local APP=$1    # apt-get package
    local LOG=$2    # logfile 

    echo "Installing ${APP}... "
    sudo apt-get --yes install $APP >> $LOG 
    echo -e >> $LOG  
    echo "done."
    
    sleep 3
    return 0        # return installapt
}   

# variable declarations

INSTALL_LOG="install.$(date +%H%M%S)_$(date +%m%d%Y).log"
CPUSUPPORT=$(egrep -c '(vmx|svm)' /proc/cpuinfo)

# main ContrailPkgs.sh

echo "VIRTUALIZATION PACKAGES INSTALLATION" | tee -a $INSTALL_LOG

# validates that CPU supports hardware virtualization and 64 bit support

sudo lscpu >> $INSTALL_LOG

if [ $CPUSUPPORT -eq 0 ]; then
    echo "Processor DOES NOT support virtualization: Installation Aborted." | tee -a $INSTALL_LOG
    exit 1
else
    echo "Processor SUPPORTS virtualization: Installing..." | tee -a $INSTALL_LOG
fi

# updates all currently installed packages

echo -n "Downloading package list from repositories and updating... " | tee -a $INSTALL_LOG
sudo apt-get --yes update >> $INSTALL_LOG
echo "done."
echo -e

# installs required ubuntu virtualization packages

echo "*** INSTALLING Virtualization Packages ***"
installapt libvirt-bin $INSTALL_LOG
installapt qemu-kvm $INSTALL_LOG
installapt ubuntu-vm-builder $INSTALL_LOG
installapt bridge-utils $INSTALL_LOG

# validates packages are installed

apt -qq list libvirt-bin | tee -a $INSTALL_LOG
apt -qq list qemu-kvm | tee -a $INSTALL_LOG
apt -qq list ubuntu-vm-builder | tee -a $INSTALL_LOG
apt -qq list bridge-utils | tee -a $INSTALL_LOG
echo -e

# optional KVM GUI tool

read -p "Install optional virt-manager GUI tool? [Y/n]? " OPTION

if [ ${OPTION,,} = "y" ] || [ ${OPTION,,} = "yes" ]; then
    installapt virt-manager $INSTALL_LOG
    apt -qq list virt-manager | tee -a $INSTALL_LOG
fi
echo -e

# installs additional non-virtualization packages 

echo "*** INSTALLING Additional Packages ***"
installapt emacs $INSTALL_LOG
installapt dnsmasq $INSTALL_LOG
installapt ntp $INSTALL_LOG

# validates packages are installed

apt -qq list emacs | tee -a $INSTALL_LOG
apt -qq list dnsmasq | tee -a $INSTALL_LOG
apt -qq list ntp | tee -a $INSTALL_LOG
echo -e 

# writing to configuration files for environment

sudo chown juniper /etc/modprobe.d/qemu-system-x86.conf
sudo echo "options kvm-intel nested=y enable_apicv=n" >> /etc/modprobe.d/qemu-system-x86.conf

sudo service libvirtd-bin restart

echo -n "Nested KVM enabled: "
cat /sys/module/kvm_intel/parameters/nested
echo -n "APICv Virtualization enabled: "
cat /sys/module/kvm_intel/parameters/enable_apicv
echo -n "Page Modification Logging enabled: "
cat /sys/module/kvm_intel/parameters/pml
echo -e

echo "All installation logs written to ${INSTALL_LOG}"
echo "INSTALLATION COMPLETED"

exit 0 # return ContrailPkgs.sh
