#!/bin/bash

# ContrailPkgs.sh
# Author: Arthur "Damon" Mills
# Last Update: 06.07.2018
# Version: .5
# License: GPLv3

# Usage: Execute without passing arguments
#
# Designed for usage on Ubuntu 14.04.5 LTS for Juniper Contrail CSO
# Assumed Default user account name: juniper
# KVM Packages installed following:
# https://help.ubuntu.com/community/KVM/Installation

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

function virtenv()
{
    local SU=$1     # superuser username
    local LOG=$2    # logfile

    sudo chown $SU /etc/modprobe.d/qemu-system-x86.conf
    sudo echo "options kvm-intel nested=y enable_apicv=n" >> /etc/modprobe.d/qemu-system-x86.conf

    sudo service libvirtd-bin restart

    local NEST=$(cat /sys/module/kvm_intel/parameters/nested)
    local APIC=$(cat /sys/module/kvm_intel/parameters/enable_apicv)
    local PLM=$(cat /sys/module/kvm_intel/parameters/pml)

    echo "Nested Virtualization enabled: ${NEST}" | tee -a $LOG
    echo "APIC Virtualization enabled: ${APIC}" | tee -a $LOG
    echo "Page Modification Logging enabled: ${PLM}" | tee -a $LOG

    if [ ${NEST^^}="Y" ] && [ ${APIC^^}="N" ] && [ ${PLM^^}="N" ]; then
        echo "KVM Environment Configuration: SUCCESSFUL" | tee -a $LOG
    fi
    echo -e

    return 0        # return virtenv
}

function confntp()
{
    local IP=$1     # local server IP address
    local LOG=$2    # logfile

    sudo sed -i -e "s/server 0.ubuntu.pool.ntp.org/ s/&/ iburst" /etc/ntp.conf
    sudo sed -i -e "/server ntp.ubuntu.com/a server $IP" /etc/ntp.conf
    
    sudo service ntp restart
    sudo ntpq >> $LOG
    echo "NTP (ntpd) Server Configuration: SUCCESSFUL" | tee -a $LOG
    echo -e 
    
    return 0        # return confntp
}

function confdns()
{
    local IP=$1     # local server IP address
    local LOG=$2    # logfile
    
    sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
    echo "Original /etc/dnsmasq.conf backed up to /etc/dnsmasq.conf.orig" | tee -a $LOG

    sudo sed -i -e "s/#domain-needed/domain-needed/g" /etc/dnsmasq.conf
    sudo sed -i -e "s/#bogus-priv/bogus-priv/g" /etc/dnsmasq.conf
    sudo sed -i -e "s/#no-resolv/no-resolv/g" /etc/dnsmasq.conf
    sudo sed -i -e "s/#no-poll/no-poll/g" /etc/dnsmasq.conf
    sudo sed -i -e "/#local=/a local=\/example.net\/" /etc/dnsmasq.conf
    sudo sed -i -e "/#server=\/localnet\//a server=8.8.8.8" /etc/dnsmasq.conf
    sudo sed -i -e "/server=8.8.8.8/a server=8.8.4.4" /etc/dnsmasq.conf
    sudo sed -i -e "s/#listen-address=/listen-address=$IP,127.0.0.1\n/g" /etc/dnsmasq.conf
    sudo sed -i -e "s/#no-hosts/no-hosts/g" /etc/dnsmasq.conf
    sudo sed -i -e "/#addn-hosts=/a addn-hosts=\/etc\/dnsmasq_static_hosts.conf" /etc/dnsmasq.conf
    echo "DNS Configuration wrote to /etc/dnsmasq.conf" | tee -a $LOG

    sudo service network-manager restart
    echo "DNS (dnsmasq) Server Configuration: SUCCESSFUL" | tee -a $LOG
    echo -e
    
    return 0        # return confdns
}

function confbridge()file:///usr/share/doc/HTML/index.html
{
    local IP=$1     # local server IP address
    local LOG=$2    # logfile
    
    # add edits to default.xml file HERE
    
    echo "*** CREATING Simlinks ***"
    cd /etc/libvirt/qemu/networks/autostart
    ln -s /etc/libvirt/qemu/networks/default.xml default.xml

    return 0        # return confvirbr
}

# variable declarations
SUDOER="juniper"
INSTALL_LOG="install.$(date +%H%M%S)_$(date +%m%d%Y).log"
CPUSUPPORT=$(egrep -c '(vmx|svm)' /proc/cpuinfo)

IFACE=$(grep -A 10 "primary" /etc/network/interface | grep iface | cut -d' ' -f2)
IPADDR=$(grep -A 10 "primary" /etc/network/interfaces | grep address | cut -d' ' -f2)
MASK=$(grep -A 10 "primary" /etc/network/interfaces | grep netmask | cut -d' ' -f2)

# main ContrailPkgs.sh

echo "CONTRAIL SERVER CONFIGURATION" | tee -a $INSTALL_LOG

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
echo "*** INSTALLING Virtualization Packages ***" | tee -a $INSTALL_LOG
installapt qemu-kvm $INSTALL_LOG
installapt libvirt-bin $INSTALL_LOG
installapt ubuntu-vm-builder $INSTALL_LOG
installapt bridge-utils $INSTALL_LOG

# validates packages are installed
echo "*** VERIFYING Packages Installations *** " | tee -a $INSTALL_LOG
apt -qq list qemu-kvm | tee -a $INSTALL_LOG
apt -qq list libvirt-bin | tee -a $INSTALL_LOG
apt -qq list ubuntu-vm-builder | tee -a $INSTALL_LOG
apt -qq list bridge-utils | tee -a $INSTALL_LOG
echo -e

# optional KVM GUI tool
read -p "Install Optional virt-manager GUI tool? [Y/n]? " OPTION

if [ ${OPTION^^} = "Y" ] || [ ${OPTION^^} = "YES" ]; then
    installapt virt-manager $INSTALL_LOG
    apt -qq list virt-manager | tee -a $INSTALL_LOG
fi
echo -e

# configures KVM environment
echo "*** CONFIGURING KVM Environment ***" | tee -a $INSTALL_LOG
virtenv $SUDOER $INSTALL_LOG
confbridge $IPADDR $INSTALL_LOG

# installs and configures NTP server
echo "*** INSTALLING/CONFIGURING NTP Server ***" | tee -a $INSTALL_LOG
installapt ntp $INSTALL_LOG
apt -qq list ntp | tee -a $INSTALL_LOG
confntp $IPADDR $INSTALL_LOG

# installs and configures DNS server
echo "*** INSTALLING/CONFIGURING DNS Server ***" | tee -a $INSTALL_LOG
installapt dnsmasq $INSTALL_LOG
apt -qq list dnsmasq | tee -a $INSTALL_LOG
confdns $IPADDR $INSTALL_LOG

# installs additional packages 
echo "*** INSTALLING Additional Packages ***" | tee -a $INSTALL_LOG
installapt emacs $INSTALL_LOG
apt -qq list emacs | tee -a $INSTALL_LOG

# finalizing installation
echo "All installation logs written to ${INSTALL_LOG}" | tee -a $INSTALL_LOG
echo "INSTALLATION COMPLETED" | tee -a $INSTALL_LOG

exit 0 # return ContrailPkgs.sh