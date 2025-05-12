#!/bin/bash

# Final improved script to install and configure a DHCP server on Ubuntu
# Compatible with Ubuntu 18.04, 20.04, 22.04, and 24.04
# Based on DHCP.pdf from Universidad Doctor Andrés Bello
# Date: May 11, 2025

# Log file for tracking installation and configuration status
LOG_FILE="/var/log/dhcp_setup_final.log"
ERROR_COUNT=0
SUCCESS_COUNT=0
EXIT_CODE=0

# Network configuration parameters (as per the PDF)
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

# Function to track status and exit on failure
track_status_and_exit() {
    if [ $1 -ne 0 ]; then
        log_message "FAILURE: $2 (Exit code: $1)"
        log_message "Installation aborted at this step. Check $LOG_FILE for details."
        log_message "=== Final Summary ==="
        log_message "Successful steps: $SUCCESS_COUNT"
        log_message "Failed steps: $((ERROR_COUNT + 1))"
        exit $1
    else
        ((SUCCESS_COUNT++))
        log_message "SUCCESS: $2"
    fi
}

# Function to validate and fix DHCP configuration syntax
fix_dhcp_syntax() {
    local conf_file="$1"
    local temp_file="/tmp/dhcpd.conf.temp"
    log_message "Validating and fixing syntax in $conf_file"
    dhcpd -t -cf "$conf_file" 2> "$temp_file"
    if [ $? -ne 0 ]; then
        log_message "Syntax error detected in $conf_file. Attempting to fix..."
        # Basic syntax fixes: Ensure closing braces and basic structure
        sed -i 's/}$/}\n/' "$conf_file"  # Ensure each block ends with a newline
        sed -i '/subnet.*{/a\}' "$conf_file"  # Add missing closing brace if needed
        sed -i '/host.*{/a\}' "$conf_file"  # Add missing closing brace if needed
        dhcpd -t -cf "$conf_file" 2>> "$temp_file"
        if [ $? -ne 0 ]; then
            log_message "ERROR: Failed to fix syntax in $conf_file. Errors: $(cat $temp_file)"
            rm -f "$temp_file"
            exit 1
        else
            log_message "Syntax fixed successfully in $conf_file"
            rm -f "$temp_file"
        fi
    else
        log_message "Syntax in $conf_file is valid"
    fi
}

# Initialize log file
> "$LOG_FILE"
log_message "Starting final DHCP server setup script"

# Step 1: Verify system readiness
log_message "Step 1: Verifying system readiness"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_message "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs)
log_message "Detected Ubuntu version: $UBUNTU_VERSION"
if [[ ! "$UBUNTU_VERSION" =~ ^(18\.04|20\.04|22\.04|24\.04)$ ]]; then
    log_message "WARNING: This script is optimized for Ubuntu 18.04, 20.04, 22.04, or 24.04. Detected version: $UBUNTU_VERSION"
fi

# Check network connectivity
ping -c 4 8.8.8.8 > /dev/null 2>&1
track_status_and_exit $? "Network connectivity check (ping to 8.8.8.8)"

# Check if interface exists
ip link show "$INTERFACE" > /dev/null 2>&1
track_status_and_exit $? "Network interface $INTERFACE exists"

# Step 2: Uninstall existing DHCP server (if installed)
log_message "Step 2: Uninstalling existing DHCP server (if installed)"
if dpkg -l | grep -q isc-dhcp-server; then
    log_message "isc-dhcp-server is installed. Proceeding with uninstallation."
    apt-get purge -y isc-dhcp-server > /dev/null 2>&1
    track_status_and_exit $? "Purging isc-dhcp-server package"
    apt-get autoremove -y > /dev/null 2>&1
    track_status_and_exit $? "Removing residual dependencies"
    rm -rf /etc/dhcp/dhcpd.conf /etc/default/isc-dhcp-server 2>/dev/null
    track_status_and_exit $? "Removing existing DHCP configuration files"
else
    log_message "isc-dhcp-server is not installed. Skipping uninstallation."
    SUCCESS_COUNT=$((SUCCESS_COUNT + 3))
fi

# Step 3: Install isc-dhcp-server
log_message "Step 3: Installing isc-dhcp-server"
apt-get update > /dev/null 2>&1
track_status_and_exit $? "Updating package lists"
apt-get install -y isc-dhcp-server > /dev/null 2>&1
track_status_and_exit $? "Installing isc-dhcp-server"

# Step 4: Assign static IP to server (using netplan for modern Ubuntu)
log_message "Step 4: Assigning static IP to server"
NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"
if [ -d "/etc/netplan" ]; then
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
    track_status_and_exit $? "Writing netplan configuration to $NETPLAN_FILE"
    netplan apply > /dev/null 2>&1
    track_status_and_exit $? "Applying netplan configuration"
else
    log_message "Netplan not found. Falling back to /etc/network/interfaces (older Ubuntu version)."
    INTERFACES_FILE="/etc/network/interfaces"
    cat >> "$INTERFACES_FILE" << EOL
auto $INTERFACE
iface $INTERFACE inet static
    address 172.22.0.50
    netmask 255.255.0.0
    gateway 172.22.0.1
    dns-nameservers 8.8.8.8
EOL
    track_status_and_exit $? "Writing network configuration to $INTERFACES_FILE"
    ifdown "$INTERFACE" && ifup "$INTERFACE" > /dev/null 2>&1
    track_status_and_exit $? "Applying network configuration"
fi

# Step 5: Verify server IP
log_message "Step 5: Verifying server IP"
CURRENT_IP=$(ip addr show "$INTERFACE" | grep -oP 'inet \K[\d.]+/[0-9]+')
if [ "$CURRENT_IP" == "$STATIC_IP" ]; then
    log_message "Server IP correctly set to $STATIC_IP"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    log_message "ERROR: Server IP is $CURRENT_IP, expected $STATIC_IP"
    exit 1
fi

# Step 6: Configure DHCP server interface
log_message "Step 6: Configuring DHCP server interface in /etc/default/isc-dhcp-server"
DHCP_DEFAULT_FILE="/etc/default/isc-dhcp-server"
echo "INTERFACESv4=\"$INTERFACE\"" > "$DHCP_DEFAULT_FILE"
track_status_and_exit $? "Writing to $DHCP_DEFAULT_FILE"

# Step 7: Verify interface configuration
log_message "Step 7: Verifying interface configuration"
if grep -q "INTERFACESv4=\"$INTERFACE\"" "$DHCP_DEFAULT_FILE"; then
    log_message "Interface $INTERFACE correctly configured in $DHCP_DEFAULT_FILE"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    log_message "ERROR: Interface $INTERFACE not found in $DHCP_DEFAULT_FILE"
    exit 1
fi

# Step 8: Configure DHCP server (as per the PDF)
log_message "Step 8: Configuring DHCP server in /etc/dhcp/dhcpd.conf"
DHCP_CONF_FILE="/etc/dhcp/dhcpd.conf"
cat > "$DHCP_CONF_FILE" << EOL
# Configuración básica para el servidor DHCP
default-lease-time 3600;
max-lease-time 7200;

subnet $SUBNET netmask $NETMASK {
    range $DHCP_RANGE_START $DHCP_RANGE_END;
    option routers $GATEWAY;
    option subnet-mask $NETMASK;
    option domain-name-servers $DNS_SERVERS;
}

# Asignación de IP estática basada en MAC
host $CLIENT_NAME {
    hardware ethernet $CLIENT_MAC;
    fixed-address $CLIENT_STATIC_IP;
}
EOL
track_status_and_exit $? "Writing DHCP configuration to $DHCP_CONF_FILE"

# Step 9: Validate and fix DHCP configuration syntax
log_message "Step 9: Validating and fixing DHCP configuration syntax"
fix_dhcp_syntax "$DHCP_CONF_FILE"

# Step 10: Restart and verify DHCP service
log_message "Step 10: Restarting and verifying DHCP service"
service isc-dhcp-server restart > /dev/null 2>&1
track_status_and_exit $? "Restarting isc-dhcp-server"
service isc-dhcp-server status | grep -q "active (running)"
track_status_and_exit $? "Verifying isc-dhcp-server is active"

# Step 11: Final verification (check if DHCP is listening)
log_message "Step 11: Performing final verification"
ss -uln | grep -q ":67"
track_status_and_exit $? "DHCP server listening on port 67"

# Step 12: Summary report
log_message "=== Final Summary ==="
log_message "Successful steps: $SUCCESS_COUNT"
log_message "Failed steps: $ERROR_COUNT"
log_message "All steps completed successfully! DHCP server is configured and running."

# Instructions for client verification
log_message "To verify on a Windows client:"
log_message "1. Ensure the client is set to obtain IP automatically."
log_message "2. Run: ipconfig /renew"
log_message "3. Check if IP is within $DHCP_RANGE_START-$DHCP_RANGE_END or $CLIENT_STATIC_IP for the specified MAC."

exit 0
