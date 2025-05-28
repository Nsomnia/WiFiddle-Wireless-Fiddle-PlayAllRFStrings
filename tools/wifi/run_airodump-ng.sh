#!/bin/bash

# Wrapper script for airodump-ng

# Log file for the main toolkit
LOG_FILE="./toolkit.log" # Relative path to the main log file from project root

log_main_toolkit() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [run_airodump-ng.sh] - $1" >> "$LOG_FILE"
}

echo "--- Airodump-ng (WiFi Sniffing) ---"
log_main_toolkit "Starting airodump-ng wrapper script."

# Check if airodump-ng is installed
if ! command -v airodump-ng &> /dev/null; then
    echo "ERROR: airodump-ng is not installed."
    echo "Please install the Aircrack-ng suite (e.g., 'sudo apt install aircrack-ng' or your distro's equivalent)."
    log_main_toolkit "ERROR: airodump-ng not found. Advised user to install aircrack-ng."
    exit 1
fi

echo "airodump-ng found."
log_main_toolkit "airodump-ng found on system."

echo ""
echo "INFO: airodump-ng requires a wireless interface to be in MONITOR MODE."
echo "You may need to use a tool like 'airmon-ng start [interface]' to enable monitor mode."
echo "Common monitor mode interface names are like 'wlan0mon', 'wlan1mon', etc."
log_main_toolkit "Informed user about monitor mode requirement."

# Prompt user for the interface name
read -p "Enter the name of your wireless interface in monitor mode (e.g., wlan0mon): " interface_name

if [ -z "$interface_name" ]; then
    echo "ERROR: No interface name provided. Exiting."
    log_main_toolkit "ERROR: User did not provide an interface name."
    exit 1
fi
log_main_toolkit "User provided interface: $interface_name"

# Create output directory if it doesn't exist
mkdir -p "./output"
log_main_toolkit "Ensured ./output directory exists."

# Prompt for airodump-ng output prefix
read -p "Enter a filename prefix for airodump-ng output files (e.g., capture1, default: airodump_scan): " output_prefix
if [[ -z "$output_prefix" ]]; then
    output_prefix="airodump_scan"
    log_main_toolkit "No output prefix provided, defaulting to '$output_prefix'."
else
    log_main_toolkit "User provided output prefix: '$output_prefix'."
fi

# This is the record file for the wrapper's action
wrapper_log_filename="run_airodump_ng_$(date +%Y%m%d-%H%M%S)_${interface_name//[^a-zA-Z0-9_]/}.log"
wrapper_log_filepath="./output/$wrapper_log_filename"
 
airodump_output_basepath="./output/${output_prefix}" # airodump-ng will append extensions

echo ""
echo "Attempting to start airodump-ng on interface '$interface_name'..."
echo "Airodump-ng output files will be prefixed with: $airodump_output_basepath"
echo "A record of this operation will be saved to: $wrapper_log_filepath"
echo "Press Ctrl+C in this terminal to stop airodump-ng."
log_main_toolkit "Airodump-ng initiated on $interface_name. Output prefix: $airodump_output_basepath. Record log: $wrapper_log_filepath"

# Write initial record
{
    echo "Airodump-ng Wrapper Log"
    echo "Timestamp: $(date)"
    echo "Interface: $interface_name"
    echo "Output File Prefix (used with --write): $airodump_output_basepath"
    echo "Expected files: ${airodump_output_basepath}-XX.cap, .csv, .kismet.netxml, etc. (where XX is channel number or sequence)"
    echo "Command issued: sudo airodump-ng --write \"$airodump_output_basepath\" \"$interface_name\""
    # Note: If collecting other airodump-ng options, they should be logged here too.
} > "$wrapper_log_filepath"

# Execute airodump-ng
# Note: airodump-ng typically requires root privileges.
# Add any other options your script might collect before --write
sudo airodump-ng --write "$airodump_output_basepath" "$interface_name"
DUMP_EXIT_CODE=$?

# Append to record log after completion
{
    echo "---"
    echo "Airodump-ng stopped at: $(date)"
    echo "Exit code: $DUMP_EXIT_CODE"
} >> "$wrapper_log_filepath"

if [ $DUMP_EXIT_CODE -eq 0 ]; then
    echo "Airodump-ng exited normally."
    log_main_toolkit "Airodump-ng exited normally. Files prefixed with $airodump_output_basepath. Record: $wrapper_log_filepath (Exit code: $DUMP_EXIT_CODE)."
else
    echo "Airodump-ng exited with code $DUMP_EXIT_CODE."
    echo "This could be due to incorrect interface, permissions, or other issues."
    log_main_toolkit "Airodump-ng exited with code $DUMP_EXIT_CODE. Files prefixed with $airodump_output_basepath. Record: $wrapper_log_filepath."
fi

echo "Output files should be in ./output/ with prefix '$output_prefix'."
echo "Operation record saved to $wrapper_log_filepath"
exit $DUMP_EXIT_CODE
