#!/bin/bash

# Wrapper script for btscanner

# Log file for the main toolkit
LOG_FILE="./toolkit.log" # Relative path to the main log file from project root

log_main_toolkit() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [run_btscanner.sh] - $1" >> "$LOG_FILE"
}

echo "--- Bluetooth Scanner (btscanner) ---"
log_main_toolkit "Starting btscanner wrapper script."

# Check if btscanner is installed
if ! command -v btscanner &> /dev/null; then
    echo "ERROR: btscanner is not installed."
    echo "Please install it using 'sudo apt install btscanner' (or your distro's equivalent)."
    log_main_toolkit "ERROR: btscanner not found. Advised user to install."
    exit 1
fi

echo "btscanner found."
log_main_toolkit "btscanner found on system."

# Create output directory if it doesn't exist
mkdir -p "./output"
log_main_toolkit "Ensured ./output directory exists."

# Generate unique record filename
record_filename="run_btscanner_$(date +%Y%m%d-%H%M%S).log"
record_filepath="./output/$record_filename"

# Execute btscanner with a basic inquiry scan
echo ""
echo "Starting btscanner for inquiry scan (btscanner --inquiry)..."
echo "A record of this operation will be saved to: $record_filepath"
echo "NOTE: btscanner typically requires root privileges (sudo) and might need a Bluetooth interface to be up."
echo "This script will attempt to run 'btscanner --inquiry'."
echo "If it fails, try running 'sudo btscanner --inquiry' manually in your terminal."
echo "Press Ctrl+C to stop btscanner if it runs continuously or hangs."
log_main_toolkit "btscanner --inquiry initiated. Record: $record_filepath"

# Write initial record
{
    echo "btscanner Session Record"
    echo "Start Time: $(date)"
    echo "Command: btscanner --inquiry"
    echo "Note: btscanner output is typically interactive and shown on the terminal."
    echo "---"
} > "$record_filepath"

# Attempt to run the command. Output will go to stdout/stderr.
# The main output of btscanner is usually interactive text, not easily captured to a single file
# without losing its interactivity or purpose. So, we let it run on the terminal.
btscanner --inquiry
SCAN_EXIT_CODE=$?

# Append final status to record
{
    echo "---"
    echo "End Time: $(date)"
    echo "btscanner Exit Code: $SCAN_EXIT_CODE"
} >> "$record_filepath"

if [ $SCAN_EXIT_CODE -eq 0 ]; then
    echo "btscanner --inquiry completed. Record saved to: $record_filepath"
    log_main_toolkit "btscanner --inquiry completed successfully. Record: $record_filepath (Exit code: $SCAN_EXIT_CODE)."
else
    echo "btscanner --inquiry exited with code $SCAN_EXIT_CODE. Record saved to: $record_filepath"
    echo "This might be due to permissions (try sudo), no Bluetooth adapter, or other issues."
    log_main_toolkit "btscanner --inquiry exited with code $SCAN_EXIT_CODE. Record: $record_filepath."
fi

exit $SCAN_EXIT_CODE
