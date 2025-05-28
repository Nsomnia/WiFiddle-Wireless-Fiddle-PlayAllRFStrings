#!/bin/bash

# Wrapper script for Nikto

LOG_FILE="./toolkit.log" # Relative to project root
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [run_nikto] - $1" >> "$LOG_FILE"
}

echo "--- Nikto Web Scanner ---"
log_message "Starting Nikto wrapper script."

# 1. Tool Check
NIKTO_CMD=""
if command -v nikto &> /dev/null; then
    NIKTO_CMD="nikto"
elif command -v nikto.pl &> /dev/null; then
    NIKTO_CMD="nikto.pl"
else
    echo "ERROR: Nikto not found (tried 'nikto' and 'nikto.pl')."
    echo "Please install it (e.g., 'sudo apt install nikto' or download from https://cirt.net/Nikto2)."
    log_message "ERROR: Nikto not found. Advised user on installation."
    exit 1
fi
echo "Nikto found as '$NIKTO_CMD'."
log_message "Nikto found as '$NIKTO_CMD'."

# 2. Gather Parameters
read -p "Enter the target URL (e.g., http://example.com) or IP address: " target_host
if [ -z "$target_host" ]; then
    echo "ERROR: No target URL/IP provided. Exiting."
    log_message "ERROR: User did not provide a target host."
    exit 1
fi
log_message "User provided target: $target_host"

read -p "Enter any additional Nikto options (e.g., -Tuning x 123b -Format htm -o report.html, or leave blank for default): " nikto_options
if [ -z "$nikto_options" ]; then
    log_message "No specific options provided by user."
    # Default is just -h <target>, which is implicitly handled.
else
    log_message "User provided options: $nikto_options"
fi

# Create output directory if it doesn't exist
mkdir -p "./output"
log_message "Ensured ./output directory exists."

# Generate unique output filename
# Sanitize target_host for use in filename (remove http(s):// and replace non-alphanum chars)
sanitized_target_host=$(echo "$target_host" | sed -e 's|^http[s]*://||' -e 's|[^a-zA-Z0-9_.-]||g')
output_filename="run_nikto_$(date +%Y%m%d-%H%M%S)_${sanitized_target_host}.log"
output_filepath="./output/$output_filename"

# 3. Execution
echo ""
echo "Attempting to run Nikto against $target_host..."
echo "Output will be saved to: $output_filepath"
echo "This may take some time."
log_message "Nikto initiated. Target: $target_host, Options: $nikto_options. Output to: $output_filepath"

# Nikto does not typically require sudo.
# Use eval to correctly parse user-provided options string
# The -h option is standard. If nikto_options include -o, it will also be used.
# If user options include -o, it might conflict if they don't expect output to also go to stdout.
# However, Nikto's -o is for its own report formats (HTML, XML, CSV), not a simple stdout redirect.
# Our redirect captures everything Nikto sends to stdout/stderr.
eval "$NIKTO_CMD -h \"$target_host\" $nikto_options" > "$output_filepath" 2>&1
NIKTO_EXIT_CODE=$?

if [ $NIKTO_EXIT_CODE -eq 0 ]; then
    echo "Nikto scan completed successfully. Output saved to: $output_filepath"
    log_message "Nikto scan finished successfully. Output: $output_filepath (Exit code: $NIKTO_EXIT_CODE)."
else
    # Nikto often exits with non-zero status even if it produces useful output (e.g., if host is down or scan is incomplete).
    echo "Nikto scan finished (Exit status: $NIKTO_EXIT_CODE). Check output at: $output_filepath"
    log_message "Nikto scan finished with exit status $NIKTO_EXIT_CODE. Output: $output_filepath."
fi

echo "Nikto wrapper script finished."
log_message "Nikto wrapper script finished."
exit $NIKTO_EXIT_CODE
