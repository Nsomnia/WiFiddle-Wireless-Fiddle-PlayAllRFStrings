#!/bin/bash

# Wrapper script for bluetoothctl

# Log file for the main toolkit
LOG_FILE="./toolkit.log" # Relative path to the main log file from project root

log_main_toolkit() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [run_bluetoothctl.sh] - $1" >> "$LOG_FILE"
}

echo "--- Bluetooth Control (bluetoothctl) ---"
log_main_toolkit "Starting bluetoothctl wrapper script."

# Check if bluetoothctl is installed
if ! command -v bluetoothctl &> /dev/null; then
    echo "ERROR: bluetoothctl is not installed."
    echo "Please install it (e.g., 'sudo apt install bluez' or your distro's equivalent)."
    log_main_toolkit "ERROR: bluetoothctl not found. Advised user to install bluez."
    exit 1
fi

echo "bluetoothctl found."
log_main_toolkit "bluetoothctl found on system."

echo "This script will launch 'bluetoothctl' in interactive mode."
echo "You can use standard bluetoothctl commands (e.g., 'scan on', 'devices', 'pair <MAC>', 'exit')."
log_main_toolkit "Informing user about interactive bluetoothctl session."

# Create output directory if it doesn't exist
mkdir -p "./output"
log_main_toolkit "Ensured ./output directory exists."

# Generate unique record filename
record_filename="run_bluetoothctl_session_$(date +%Y%m%d-%H%M%S).log"
record_filepath="./output/$record_filename"

echo "A record of this interactive session will be saved to: $record_filepath"
log_main_toolkit "bluetoothctl interactive session initiated. Record: $record_filepath"

# Write initial record
{
    echo "bluetoothctl Interactive Session Record"
    echo "Start Time: $(date)"
    echo "Note: This log records the initiation and termination of an interactive bluetoothctl session."
    echo "Commands entered within bluetoothctl are not logged here."
    echo "---"
} > "$record_filepath"

# Execute bluetoothctl
bluetoothctl
CTL_EXIT_CODE=$?

# Append final status to record
{
    echo "---"
    echo "End Time: $(date)"
    echo "bluetoothctl Exit Code: $CTL_EXIT_CODE"
} >> "$record_filepath"

if [ $CTL_EXIT_CODE -eq 0 ]; then
    echo "bluetoothctl exited normally. Session record saved to: $record_filepath"
    log_main_toolkit "bluetoothctl exited normally. Record: $record_filepath (Exit code: $CTL_EXIT_CODE)."
else
    echo "bluetoothctl exited with code $CTL_EXIT_CODE. Session record saved to: $record_filepath"
    log_main_toolkit "bluetoothctl exited with code $CTL_EXIT_CODE. Record: $record_filepath."
fi

exit $CTL_EXIT_CODE
