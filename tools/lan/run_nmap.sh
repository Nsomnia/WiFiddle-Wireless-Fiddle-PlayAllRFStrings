#!/bin/bash

# Wrapper script for nmap

# Log file for the main toolkit
LOG_FILE="./toolkit.log" # Relative path to the main log file from project root

log_main_toolkit() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [run_nmap.sh] - $1" >> "$LOG_FILE"
}

echo "--- Nmap Network Scanner ---"
log_main_toolkit "Starting nmap wrapper script."

# Check if nmap is installed
if ! command -v nmap &> /dev/null; then
    echo "ERROR: nmap is not installed."
    echo "Please install it (e.g., 'sudo apt install nmap' or your distro's equivalent)."
    log_main_toolkit "ERROR: nmap not found. Advised user to install nmap."
    exit 1
fi

echo "nmap found."
log_main_toolkit "nmap found on system."

echo ""
echo "INFO: Nmap is a powerful network scanning tool used for network discovery and security auditing."
echo "It can discover hosts, services, operating systems, and vulnerabilities on a network."
log_main_toolkit "Informed user about nmap capabilities."

# --- Gather parameters from the user ---
echo ""
echo "Select Nmap Scan Type:"
echo "  1) TCP SYN Scan (-sS) - Stealthy, needs sudo"
echo "  2) UDP Scan (-sU) - Scans UDP ports, needs sudo"
echo "  3) Ping Scan (-sn) - Host discovery only, no port scan"
# Add more scan types later if needed

read -p "Enter choice (e.g., 1): " scan_choice

scan_type_param=""
scan_desc=""
needs_sudo=false

case $scan_choice in
    1)
        scan_type_param="-sS"
        scan_desc="TCP SYN Scan"
        needs_sudo=true
        log_main_toolkit "User selected: TCP SYN Scan (-sS)"
        ;;
    2)
        scan_type_param="-sU"
        scan_desc="UDP Scan"
        needs_sudo=true
        log_main_toolkit "User selected: UDP Scan (-sU)"
        ;;
    3)
        scan_type_param="-sn"
        scan_desc="Ping Scan"
        log_main_toolkit "User selected: Ping Scan (-sn)"
        ;;
    *)
        echo "ERROR: Invalid scan type choice. Exiting."
        log_main_toolkit "ERROR: Invalid scan type choice: $scan_choice"
        exit 1
        ;;
esac

read -p "Enter target IP address, range, or hostname (e.g., 192.168.1.1, 192.168.1.0/24, example.com): " target
if [ -z "$target" ]; then
    echo "ERROR: No target provided. Exiting."
    log_main_toolkit "ERROR: User did not provide a target."
    exit 1
fi
log_main_toolkit "User provided target: $target"

read -p "Enter specific ports (e.g., 80,443 or -p- for all, leave blank for default nmap behavior): " ports
port_param=""
if [ -n "$ports" ]; then
    if [[ "$ports" == "-p-" ]]; then
        port_param="-p-"
    else
        port_param="-p $ports"
    fi
    log_main_toolkit "User specified ports: $ports"
else
    log_main_toolkit "User did not specify ports (using nmap default)."
fi

# Create output directory if it doesn't exist
mkdir -p "./output"
log_main_toolkit "Ensured ./output directory exists."

# Generate unique output filename
output_filename="run_nmap_$(date +%Y%m%d-%H%M%S).log"
output_filepath="./output/$output_filename"

# Construct the command parts
nmap_base_command="nmap $scan_type_param $port_param $target"
full_nmap_command_for_display="$nmap_base_command"
if [ "$needs_sudo" = true ]; then
    full_nmap_command_for_display="sudo $nmap_base_command"
fi

echo ""
echo "Confirm Scan Details:"
echo "  Scan Type:   $scan_desc ($scan_type_param)"
echo "  Target:      $target"
if [ -n "$port_param" ]; then
    echo "  Ports:       $ports"
fi
echo "  Needs sudo:  $needs_sudo"
echo "  Full Command (approx): $full_nmap_command_for_display"
echo "  Output File: $output_filepath"
echo ""
read -p "Proceed with this scan? (yes/no): " confirm_scan

if [[ "$confirm_scan" != "yes" ]]; then
    echo "Scan cancelled by user."
    log_main_toolkit "User cancelled the nmap scan."
    exit 0
fi

echo "Attempting to start nmap..."
echo "Output will be saved to: $output_filepath"
echo "This may take some time..."
log_main_toolkit "Executing Nmap. Target: $target, Scan Type: $scan_type_param, Ports: $ports, Output: $output_filepath"

# Execute nmap and redirect output
if [ "$needs_sudo" = true ]; then
    sudo nmap $scan_type_param $port_param "$target" > "$output_filepath" 2>&1
else
    nmap $scan_type_param $port_param "$target" > "$output_filepath" 2>&1
fi
NMAP_EXIT_CODE=$?

if [ $NMAP_EXIT_CODE -eq 0 ]; then
    echo "Nmap scan completed. Output saved to: $output_filepath"
    log_main_toolkit "Nmap scan completed successfully. Output: $output_filepath (Exit code: $NMAP_EXIT_CODE)."
else
    echo "Nmap scan exited with code $NMAP_EXIT_CODE. Output (if any) saved to: $output_filepath"
    echo "This could be due to permissions, incorrect parameters, network issues, or the target being down."
    log_main_toolkit "Nmap scan exited with code $NMAP_EXIT_CODE. Output: $output_filepath."
fi

exit $NMAP_EXIT_CODE
