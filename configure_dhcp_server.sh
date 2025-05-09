#!/bin/bash

# Script to verify, install, and configure a DHCP server on Ubuntu Server
# Based on DHCP.pdf from Universidad Doctor Andrés Bello
# Date: May 09, 2025

# Log file for tracking installation and configuration status
LOG_FILE="/var/log/dhcp_setup.log"
ERROR_COUNT=0
SUCCESS_COUNT=0

# Network configuration parameters
INTERFACE="enp0s3"  # Adjust to your network interface
STATIC_IP="172.22.0.50/16"
GATEWAY="172.22.0.1"
DNS_SERVERS="8.8.8.8,8.8.4.4"
SUBNET="172.22.0.0"
NETMASK="255.255.0.0"
DHCP_RANGE_START="172.22.0.10"
DHCP_RANGE_END="172.22.0.45"
CLIENT_MAC="00:14:22:01:23:45"  # Replace with actual client MAC address
CLIENT_STATIC_IP="172.22.0.5"
CLIENT_NAME="cliente1"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to increment success or error count
track_status() {
    if [ $1 -eq 0 ]; then
        ((SUCCESS_COUNT++))
        log_message "SUCCESS: $2"
    else
        ((ERROR_COUNT++))
        log_message "ERROR: $2"
    fi
}

# Initialize log file
> "$LOG_FILE"
log_message "Starting DHCP server setup script"

# Step 1: Verify system readiness
log_message "Step 1: Verifying system readiness"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_message "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs)
if [[ ! "$UBUNTU_VERSION" =~ ^(20\.04|22\.04|24\.04)$ ]]; then
    log_message "WARNING: This script is designed for Ubuntu 20.04, 22.04, or 24.04. Detected version: $UBUNTU_VERSION"
fi

# Check network connectivity
ping -c 4 8.8.8.8 > /dev/null 2>&1
track_status $? "Network connectivity check (ping to 8.8.8.8)"

# Check if interface exists
ip link show "$INTERFACE" > /dev/null 2>&1
track_status $? "Network interface $INTERFACE exists"

# Step 2: Install isc-dhcp-server
log_message "Step 2: Installing isc-dhcp-server"
apt-get update > /dev/null 2>&1
apt-get install -y isc-dhcp-server > /dev/null 2>&1
track_status $? "Installation of isc-dhcp-server"

# Step 3: Verify server IP
log_message "Step 3: Verifying server IP"
CURRENT_IP=$(ip addr show "$INTERFACE" | grep -oP 'inet \K[\d.]+/[0-9]+')
if [ -z "$CURRENT_IP" ]; then
    log_message "ERROR: No IP address assigned to $INTERFACE"
    ERROR_COUNT=$((ERROR_COUNT + 1))
else
    log_message "Current IP on $INTERFACE: $CURRENT_IP"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
fi

# Step 4: Assign static IP to server
log_message "Step 4: Assigning static IP to server"
NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"
cat > "$NETPLAN_FILE" << EOL
network:
  version: 2
  ethernets:
    $INTERFACE:
      addresses:
        - $STATIC_IP
      gateway4: $GATEWAY
      nameservers:
        addresses: [$DNS_SERVERS]
EOL
track_status $? "Writing netplan configuration"

# Step.Concurrent 5: Apply netplan changes
log_message "Step 5: Applying netplan changes"
netplan apply > /dev/null 2>&1
track_status $? "Applying netplan configuration"

# Step 6: Configure DHCP server interface
log_message "Step 6: Configuring DHCP server interface"
DHCP_DEFAULT_FILE="/etc/default/isc-dhcp-server"
echo "INTERFACESv4=\"$INTERFACE\"" >> "$DHCP_DEFAULT_FILE"
track_status $? "Configuring $DHCP_DEFAULT_FILE"

# Step 7: Configure DHCP server
log_message "Step 7: Configuring DHCP server"
DHCP_CONF_FILE="/etc/dhcp/dhcpd.conf"
cat >> "$DHCP_CONF_FILE" << EOL

subnet $SUBNET netmask $NETMASK {
    range $DHCP_RANGE_START $DHCP_RANGE_END;
    option routers $GATEWAY;
    option subnet-mask $NETMASK;
    option domain-name-servers $DNS_SERVERS;
    default-lease-time 3600;
    max-lease-time 7200;
}

host $CLIENT_NAME {
    hardware ethernet $CLIENT_MAC;
    fixed-address $CLIENT_STATIC_IP;
}
EOL
track_status $? "Writing DHCP configuration to $DHCP_CONF_FILE"

# Step 8: Validate DHCP configuration
log_message "Step 8: Validating DHCP configuration"
dhcpd -t -cf "$DHCP_CONF_FILE" > /dev/null 2>&1
track_status $? "Validating DHCP configuration syntax"

# Step 9: Restart and verify DHCP service
log_message "Step 9: Restarting and verifying DHCP service"
service isc-dhcp-server restart > /dev/null 2>&1
track_status $? "Restarting isc-dhcp-server"

# Check service status
service isc-dhcp-server status | grep -q "active (running)"
track_status $? "Verifying isc-dhcp-server is active"

# Step 10: Final verification
log_message "Step 10: Performing final verification"
# Check if DHCP server is listening
ss -uln | grep -q ":67"
track_status $? "DHCP server listening on port 67"

# Summary report
log_message "=== Setup Summary ==="
log_message "Successful steps: $SUCCESS_COUNT"
log_message "Failed steps: $ERROR_COUNT"
if [ "$ERROR_COUNT" -eq 0 ]; then
    log_message "All steps completed successfully! DHCP server is configured."
else
    log_message "Some steps failed. Check $LOG_FILE for details."
fi

# Instructions for client verification
log_message "To verify on a Windows client:"
log_message "1. Ensure the client is set to obtain IP automatically."
log_message "2. Run: ipconfig /renew"
log_message "3. Check if IP is within $DHCP_RANGE_START-$DHCP_RANGE_END or $CLIENT_STATIC_IP for the specified MAC."

exit $ERROR_COUNT
