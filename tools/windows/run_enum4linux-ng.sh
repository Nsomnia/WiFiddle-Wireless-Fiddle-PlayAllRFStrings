#!/bin/bash

# Wrapper script for enum4linux-ng.py

LOG_FILE="./toolkit.log" # Relative to project root
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [run_enum4linux_ng] - $1" >> "$LOG_FILE"
}

echo "--- Enum4linux-ng (Windows/Samba Enumeration) ---"
log_message "Starting enum4linux-ng.py wrapper script."

# 1. Tool Check
# Attempt to find enum4linux-ng.py in PATH first.
if command -v enum4linux-ng.py &> /dev/null; then
    ENUM4LINUX_CMD="enum4linux-ng.py"
    echo "enum4linux-ng.py found in PATH."
    log_message "enum4linux-ng.py found in PATH."
# Else, check a common alternative location.
elif [ -x "/opt/enum4linux-ng/enum4linux-ng.py" ]; then
    ENUM4LINUX_CMD="/opt/enum4linux-ng/enum4linux-ng.py"
    echo "enum4linux-ng.py found at /opt/enum4linux-ng/enum4linux-ng.py."
    log_message "enum4linux-ng.py found at /opt/enum4linux-ng/enum4linux-ng.py."
else
    echo "ERROR: enum4linux-ng.py not found in PATH or at /opt/enum4linux-ng/enum4linux-ng.py."
    echo "Please clone it from GitHub (e.g., https://github.com/cddmp/enum4linux-ng)"
    echo "and ensure enum4linux-ng.py is in your PATH or installed in a common location like /opt/enum4linux-ng/."
    log_message "ERROR: enum4linux-ng.py not found. Advised user on installation."
    exit 1
fi

# 2. Gather Parameters
read -p "Enter the target IP address of the Windows/Samba machine: " target_ip
if [ -z "$target_ip" ]; then
    echo "ERROR: No target IP address provided. Exiting."
    log_message "ERROR: User did not provide a target IP."
    exit 1
fi
log_message "User provided target IP: $target_ip"

read -p "Enter enumeration options (e.g., -A, -U, -S, or leave blank for default -A): " enum_options
if [ -z "$enum_options" ]; then
    enum_options="-A" # Default to all simple enumeration
    log_message "No specific options provided by user, defaulting to -A."
else
    log_message "User provided options: $enum_options"
fi

# Create output directory if it doesn't exist
mkdir -p "./output"
log_message "Ensured ./output directory exists."

# Generate unique output filename
output_filename="run_enum4linux_ng_$(date +%Y%m%d-%H%M%S)_${target_ip//[^a-zA-Z0-9_]/}.log"
output_filepath="./output/$output_filename"

# 3. Execution
echo ""
echo "Attempting to run Enum4linux-ng against $target_ip..."
echo "Output will be saved to: $output_filepath"
echo "This may take some time."
log_message "Enum4linux-ng initiated. Target: $target_ip, Options: $enum_options. Output to: $output_filepath"

# enum4linux-ng.py is a Python script
"$ENUM4LINUX_CMD" $enum_options "$target_ip" > "$output_filepath" 2>&1
ENUM_EXIT_CODE=$?

if [ $ENUM_EXIT_CODE -eq 0 ]; then
    echo "Enum4linux-ng completed successfully. Output saved to: $output_filepath"
    log_message "Enum4linux-ng finished successfully. Output: $output_filepath (Exit code: $ENUM_EXIT_CODE)."
else
    echo "Enum4linux-ng scan may have encountered an error (Exit status: $ENUM_EXIT_CODE). Output saved to: $output_filepath"
    log_message "Enum4linux-ng finished with exit status $ENUM_EXIT_CODE. Output: $output_filepath."
fi

echo "Enum4linux-ng wrapper script finished."
log_message "Enum4linux-ng wrapper script finished."
exit $ENUM_EXIT_CODE
