#!/bin/bash

# ContrailPkgs.sh
# Author: Arthur "Damon" Mills
# Last Update: 06.08.2018
# Version: .7
# License: GPLv3

# Usage: Execute without passing arguments

# Designed for Ubuntu 14.04.5 LTS deployment of Juniper Contrail CSO
# KVM Packages installed following the guide on:
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

function ipcheck() 
{
    local ADDR=$1
    
    # regex to check for valid IP address (0-255.0-255.0-255.0-255)
    if [[ "$ADDR" =~ ^([0-1]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([0-1]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([0-1]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([0-1]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])$ ]]; then
        # valid IP address
        return 0
    else
        # invalid IP address
        return 1
    fi
    # return ipcheck
}

function virtenv()
{
    local SU=$1     # superuser username
    local LOG=$2    # logfile

    sudo adduser $SU libvirtd
    sudo chown $SU /etc/modprobe.d/qemu-system-x86.conf
    sudo echo "options kvm-intel nested=y enable_apicv=n" >> /etc/modprobe.d/qemu-system-x86.conf

    sudo service libvirt-bin restart

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
    local PRIME=$2  # primary DNS server address
    local SECOND=$3 # secondary DNS server address
    local LDOM=$4   # local domain
    local LOG=$5    # logfile
    
    sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
    echo "Original /etc/dnsmasq.conf backed up to /etc/dnsmasq.conf.orig" | tee -a $LOG

    sudo sed -i -e "s/#domain-needed/domain-needed/g" /etc/dnsmasq.conf
    sudo sed -i -e "s/#bogus-priv/bogus-priv/g" /etc/dnsmasq.conf
    sudo sed -i -e "s/#no-resolv/no-resolv/g" /etc/dnsmasq.conf
    sudo sed -i -e "s/#no-poll/no-poll/g" /etc/dnsmasq.conf
    sudo sed -i -e "/#local=/a local=\/$LDOM\/" /etc/dnsmasq.conf
    sudo sed -i -e "/#server=\/localnet\//a server=$PRIME\nserver=$SECOND" /etc/dnsmasq.conf
    sudo sed -i -e "s/#listen-address=/listen-address=$IP,127.0.0.1\n/g" /etc/dnsmasq.conf
    sudo sed -i -e "s/#no-hosts/no-hosts/g" /etc/dnsmasq.conf
    sudo sed -i -e "/#addn-hosts=/a addn-hosts=\/etc\/dnsmasq_static_hosts.conf" /etc/dnsmasq.conf
    echo "DNS Configuration wrote to /etc/dnsmasq.conf" | tee -a $LOG

    sudo service network-manager restart
    echo "DNS (dnsmasq) Server Configuration: SUCCESSFUL" | tee -a $LOG
    echo -e
    
    return 0        # return confdns
}

function confbridge()
{
    local IP=$1     # local server IP address
    local NMASK=$2  # local server network mask
    local LOG=$3    # logfile
    
    local IFACE=$(sed -n '/primary/,/^$/{//!p}' /etc/network/interfaces | grep iface | cut -d' ' -f2) # primary network interface on server
    local NWRK=$(sed -n '/primary/,/^$/{//!p}' /etc/network/interfaces | grep network | cut -d' ' -f2) # network ID on primary interface
    local BCAST=$(sed -n '/primary/,/^$/{//!p}' /etc/network/interfaces | grep broadcast | cut -d' ' -f2) # broadcast address on primary interface
    local GWAY=$(sed -n '/primary/,/^$/{//!p}' /etc/network/interfaces | grep gateway | cut -d' ' -f2) # gateway address on primary interface
    local DNSS=$(sed -n '/primary/,/^$/{//!p}' /etc/network/interfaces | grep dns-search | cut -d' ' -f2) # DNS search address on primary interface
    
    # deletes primary interface configuration in /etc/network/interfaces file
    sudo sed -i '/primary/,/^$/{//!d}' /etc/network/interfaces
    # assigns primary interface to logical bridge device
    sudo sed -i -e "/primary/a auto $IFACE\niface $IFACE inet manual\n\tup ifconfig $IFACE 0.0.0.0 up" /etc/network/interfaces
    
    # creates virtual bridge interface using primary interface configuration
    sudo echo -e >> /etc/network/interfaces
    sudo echo -e "# The virtual bridge network interface" >> /etc/network/interfaces
    sudo echo -e "auto virbr0" >> /etc/network/interfaces
    sudo echo -e "iface virbr0 inet static" >> /etc/network/interfaces
    sudo echo -e "\tbridge_ports $IFACE" >> /etc/network/interfaces
    sudo echo -e "\taddress $IP" >> /etc/network/interfaces
    sudo echo -e "\tnetmask $NMASK" >> /etc/network/interfaces
    sudo echo -e "\tnetwork $NWRK" >> /etc/network/interfaces
    sudo echo -e "\tbroadcast $BCAST" >> /etc/network/interfaces
    sudo echo -e "\tgateway $GWAY"  >> /etc/network/interfaces
    sudo echo -e "\tdns-search $DNSS" >> /etc/network/interfaces
    
    # ADD EDITS TO default.xml FILE - HERE
    
    echo "*** CREATING Simlinks ***"
    cd /etc/libvirt/qemu/networks/autostart
    ln -s /etc/libvirt/qemu/networks/default.xml default.xml
    echo "Bridge Interface Configuration: SUCCESSFUL" | tee -a $LOG
    echo -e
    
    return 0        # return confvirbr
}

# variable declarations
SUDOER=$(id -un)
IPADDR=$(sed -n '/primary/,/^$/{//!p}' /etc/network/interfaces | grep address | cut -d' ' -f2)
NETMASK=$(sed -n '/primary/,/^$/{//!p}' /etc/network/interfaces | grep netmask | cut -d' ' -f2)
INSTALL_LOG="install.$(date +%H%M%S)_$(date +%m%d%Y).log"
CPUSUPPORT=$(egrep -c '(vmx|svm)' /proc/cpuinfo)
PROMPT="N"

# main ContrailPkgs.sh

echo "CONTRAIL SERVER CONFIGURATION" | tee -a $INSTALL_LOG

# validates CPU supports hardware virtualization and 64 bit support
sudo lscpu >> $INSTALL_LOG

if [ $CPUSUPPORT -eq 0 ]; then
    echo "Processor DOES NOT support virtualization: Installation Aborted." | tee -a $INSTALL_LOG
    exit 1
else
    echo "Processor SUPPORTS virtualization: Installing..." | tee -a $INSTALL_LOG
fi

# prompt user to input environmental variables used in deployment
echo "*** COLLECTING Environmental Variables ***" | tee -a $INSTALL_LOG
until [ ${PROMPT^^} = "Y" ] || [ ${PROMPT^^} = "YES" ]; do
    PRIMARY="0"
    SECONDARY="0"
    DOMAIN="example.net"
    until ipcheck $PRIMARY; do
        read -p "Primary DNS (8.8.8.8): " PRIMARY
        if [ -z "$PRIMARY" ]; then
            PRIMARY="8.8.8.8"
        fi
    done
    until ipcheck $SECONDARY; do
        read -p "Secondary DNS (8.8.4.4): " SECONDARY
        if [ -z "$SECONDARY" ]; then
            SECONDARY="8.8.4.4"
        fi        
    done
    read -p "Domain (example.net): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        DOMAIN="example.net"
    fi    
    echo -e "Primary DNS:\t ${PRIMARY}"
    echo -e "Secondary DNS:\t ${SECONDARY}"
    echo -e "Domain:\t\t ${DOMAIN}"
    read -p "Correct (y/n)? " PROMPT
    if [ -z $PROMPT ]; then
        PROMPT="N"
    fi
done
echo -e

# updates all currently installed packages
echo "Downloading package list from repositories and updating... " | tee -a $INSTALL_LOG
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
echo "*** VERIFYING Package Installs *** " | tee -a $INSTALL_LOG
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
confbridge $IPADDR $NETMASK $INSTALL_LOG

# installs and configures NTP server
echo "*** INSTALLING/CONFIGURING NTP Server ***" | tee -a $INSTALL_LOG
installapt ntp $INSTALL_LOG
apt -qq list ntp | tee -a $INSTALL_LOG
confntp $IPADDR $INSTALL_LOG

# installs and configures DNS server
echo "*** INSTALLING/CONFIGURING DNS Server ***" | tee -a $INSTALL_LOG
installapt dnsmasq $INSTALL_LOG
apt -qq list dnsmasq | tee -a $INSTALL_LOG
confdns $IPADDR $PRIMARY $SECONDARY $DOMAIN $INSTALL_LOG

# installs additional packages 
echo "*** INSTALLING Additional Packages ***" | tee -a $INSTALL_LOG
installapt emacs $INSTALL_LOG
apt -qq list emacs | tee -a $INSTALL_LOG

# finalizing installation
echo "All installation logs written to ${INSTALL_LOG}" | tee -a $INSTALL_LOG
echo "INSTALLATION COMPLETED" | tee -a $INSTALL_LOG

exit 0 # return ContrailPkgs.sh