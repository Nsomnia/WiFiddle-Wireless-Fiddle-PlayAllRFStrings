#!/usr/bin/env zsh

# Log file location - Define early for use in initial error checks
LOG_FILE="toolkit.log" # Assuming it's in the same directory as the script

# --- Logging Function (defined early for initial checks) ---
_initial_log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Attempt to load zcurses module
zmodload zsh/curses

# Check if zcurses_init is available
if ! command -v zcurses_init >/dev/null 2>&1; then
    local err_msg="CRITICAL Error: zsh/curses module may have loaded, but zcurses_init command is NOT available."
    echo "$err_msg" >&2
    echo "Please ensure your zsh/curses module is correctly installed, functional, and provides 'zcurses_init'." >&2
    _initial_log_message "$err_msg"
    exit 1
fi

# --- Full Logging Function ---
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# --- Global variable for status window ---
typeset -g status_win
# --- Global flag for zcurses initialization ---
typeset -g ZCURSES_IS_INITIALIZED

# --- Global Color Pair Variables ---
typeset -g color_pair_title
typeset -g color_pair_status
typeset -g color_pair_highlight
typeset -g color_pair_main_border
typeset -g colors_initialized_successfully

# --- Color Initialization Function ---
init_colors() {
    log_message "Attempting to initialize colors..."
    colors_initialized_successfully=0 
    zcurses_init_pair 1 7 4 && color_pair_title=1 || color_pair_title=0
    zcurses_init_pair 2 0 2 && color_pair_status=2 || color_pair_status=0
    zcurses_init_pair 3 3 0 && color_pair_highlight=3 || color_pair_highlight=0
    zcurses_init_pair 4 4 0 && color_pair_main_border=4 || color_pair_main_border=0
    if (( color_pair_title != 0 || color_pair_status != 0 || color_pair_highlight != 0 || color_pair_main_border != 0 )); then
        log_message "At least one color pair initialized."
        colors_initialized_successfully=1
    else
        log_message "Failed to initialize any color pairs. Using monochrome."
    fi
}

# --- Network Management Functions ---
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        log_message "Root privileges check: FAILED. User is not root."
        if [[ -n "$ZCURSES_IS_INITIALIZED" ]]; then
            zcurses_messagebox "Error: Root privileges are required for this operation. Please run the toolkit with sudo." "Privilege Error"
        else
            echo "Error: Root privileges are required for this operation. Please run the toolkit with sudo."
        fi
        return 1 
    fi
    log_message "Root privileges check: PASSED."
    return 0 
}

manage_network_manager() {
    local action="$1" 
    if ! command -v systemctl >/dev/null 2>&1; then
        log_message "NetworkManager: systemctl command not found."
        display_status "Error: systemctl not found."
        return 1
    fi
    if ! check_root_privileges; then return 1; fi
    display_status "Attempting to $action NetworkManager..."
    if sudo systemctl "$action" NetworkManager; then
        log_message "NetworkManager successfully ${action}ed."
        display_status "NetworkManager successfully ${action}ed."
        sleep 1; return 0
    else
        log_message "NetworkManager: Failed to $action NetworkManager."
        display_status "Error: Failed to $action NetworkManager."
        return 1
    fi
}

manage_monitor_mode() {
    local interface="$1"
    local action="$2" 
    if [[ -z "$interface" ]]; then
        log_message "MonitorMode: No interface specified."
        display_status "Error: No wireless interface specified."
        return 1
    fi
    if ! command -v iw >/dev/null 2>&1 || ! command -v ip >/dev/null 2>&1; then
        log_message "MonitorMode: 'iw' or 'ip' command not found."
        display_status "Error: 'iw' or 'ip' not found."
        return 1
    fi
    if ! check_root_privileges; then return 1; fi

    if [[ "$action" == "enable" ]]; then
        display_status "Enabling monitor mode on $interface..."
        log_message "MonitorMode: Enabling on $interface."
        if command -v airmon-ng >/dev/null 2>&1; then
            sudo airmon-ng check kill >/dev/null 2>&1 && log_message "MonitorMode: Killed interfering processes (airmon-ng)." && display_status "Killed processes (airmon-ng)." && sleep 1
            if sudo airmon-ng start "$interface"; then
                log_message "MonitorMode: Enabled on $interface (airmon-ng)."
                display_status "Monitor mode enabled on $interface (airmon-ng)."
                [[ -n "$ZCURSES_IS_INITIALIZED" ]] && zcurses_messagebox "Monitor mode enabled via airmon-ng. Interface name might have changed (e.g., to ${interface}mon)." "Interface Note" || echo "INFO: Interface name might change (e.g., ${interface}mon)."
                return 0
            else
                log_message "MonitorMode: airmon-ng start failed. Trying manual."
                display_status "airmon-ng failed. Trying manual for $interface."
            fi
        fi
        (set -x; sudo ip link set "$interface" down && sudo iw dev "$interface" set type monitor && sudo ip link set "$interface" up)
        if [[ $? -eq 0 ]]; then log_message "MonitorMode: Enabled on $interface (manual)."; display_status "Monitor mode enabled on $interface (manual)."; return 0; else log_message "MonitorMode: Failed manual enable on $interface."; display_status "Error: Failed manual enable on $interface."; return 1; fi
    elif [[ "$action" == "disable" ]]; then
        display_status "Disabling monitor mode on $interface..."
        log_message "MonitorMode: Disabling on $interface."
        if command -v airmon-ng >/dev/null 2>&1 && [[ "$interface" == *"mon"* ]]; then
           if sudo airmon-ng stop "$interface"; then log_message "MonitorMode: Disabled on $interface (airmon-ng)."; display_status "Monitor mode disabled on $interface (airmon-ng)."; return 0; else log_message "MonitorMode: airmon-ng stop failed. Trying manual."; display_status "airmon-ng stop failed. Trying manual."; fi
        fi
        (set -x; sudo ip link set "$interface" down && sudo iw dev "$interface" set type managed && sudo ip link set "$interface" up)
        if [[ $? -eq 0 ]]; then log_message "MonitorMode: Disabled on $interface (manual)."; display_status "Monitor mode disabled on $interface (manual)."; return 0; else log_message "MonitorMode: Failed manual disable on $interface."; display_status "Error: Failed manual disable on $interface."; return 1; fi
    else
        log_message "MonitorMode: Invalid action '$action'."
        display_status "Error: Invalid monitor mode action '$action'."
        return 1
    fi
}

# --- Status Display Function ---
display_status() {
    local message="$1"; log_message "STATUS: $message"
    if [[ -z "$ZCURSES_IS_INITIALIZED" ]]; then echo "STATUS (no-zcurses): $message"; return; fi
    [[ -n "$status_win" ]] && zcurses_delwin "$status_win"
    integer lines cols; zcurses_getmaxyx lines cols
    if (( lines > 0 && cols > 0 )); then
        status_win=$(zcurses_newwin 1 "$cols" $((lines - 1)) 0)
        if [[ -n "$status_win" ]]; then
            (( colors_initialized_successfully && color_pair_status > 0 )) && zcurses_attr_on "$status_win" "color_pair($color_pair_status)"
            zcurses_addstr "$status_win" 0 0 "${message[1,$((cols-1))]}"
            (( colors_initialized_successfully && color_pair_status > 0 )) && zcurses_attr_off "$status_win" "color_pair($color_pair_status)"
            zcurses_refresh_win "$status_win"
        else log_message "ERROR: Failed to create status_win."; echo "STATUS (win_fail): $message"; fi
    else log_message "ERROR: Invalid screen dimensions for status_win."; echo "STATUS (dim_fail): $message"; fi
}

# --- Script Content Display Function ---
display_script_content() {
    local script_path="$1"; log_message "Displaying script: $script_path"
    if [[ -f "$script_path" ]]; then
        if [[ -n "$ZCURSES_IS_INITIALIZED" ]]; then
            local content; content=$(cat "$script_path") 
            (( ${#content} > 4000 )) && content="${content[1,4000]}\n... (truncated) ..."
            zcurses_messagebox "Content of $script_path:\n\n$content" "Script Viewer"
            log_message "Displayed $script_path in messagebox."
        else cat "$script_path"; log_message "Displayed $script_path to stdout."; fi
    else
        display_status "ERROR: Script not found: $script_path"
        [[ -n "$ZCURSES_IS_INITIALIZED" ]] && zcurses_messagebox "ERROR: Script not found: $script_path" "Error"
        log_message "ERROR: Script not found for display: $script_path"
    fi
}

# --- Main Menu Function ---
main_menu() {
    log_message "Main menu initializing..."
    zcurses_clear 
    integer lines cols; zcurses_getmaxyx lines cols 
    local main_win; main_win=$(zcurses_newwin "$lines" "$cols" 0 0)
    if [[ -z "$main_win" ]]; then log_message "ERROR: Failed to create main_win."; echo "CRITICAL ERROR: Could not create main menu. Exiting." >&2; return 1; fi

    redraw_main_window_elements() {
        (( colors_initialized_successfully && color_pair_main_border > 0 )) && zcurses_attr_on "$main_win" "color_pair($color_pair_main_border)"
        zcurses_box "$main_win" 0 0
        (( colors_initialized_successfully && color_pair_main_border > 0 )) && zcurses_attr_off "$main_win" "color_pair($color_pair_main_border)"
        (( colors_initialized_successfully && color_pair_title > 0 )) && zcurses_attr_on "$main_win" "color_pair($color_pair_title)"
        zcurses_addstr "$main_win" 1 3 "Zsh Penetration Testing Toolkit"
        (( colors_initialized_successfully && color_pair_title > 0 )) && zcurses_attr_off "$main_win" "color_pair($color_pair_title)"
        (( colors_initialized_successfully && color_pair_main_border > 0 )) && zcurses_attr_on "$main_win" "color_pair($color_pair_main_border)"
        zcurses_addstr "$main_win" 2 3 "----------------------------------"
        (( colors_initialized_successfully && color_pair_main_border > 0 )) && zcurses_attr_off "$main_win" "color_pair($color_pair_main_border)"
    }
    redraw_main_window_elements

    typeset -A tool_paths tool_flags
    tool_paths=(
        "Bluetooth: Scan (btscanner)"        "./tools/bluetooth/run_btscanner.sh"
        "Bluetooth: Manage (bluetoothctl)"   "./tools/bluetooth/run_bluetoothctl.sh"
        "WiFi: Discover (airodump-ng)"       "./tools/wifi/run_airodump-ng.sh"
        "WiFi: Inject (aireplay-ng)"         "./tools/wifi/run_aireplay-ng.sh"
        "LAN: Network Scan (nmap)"           "./tools/lan/run_nmap.sh"
        "LAN: ARP Spoof (arpspoof)"          "./tools/lan/run_arpspoof.sh"
        "Windows: Enumerate (enum4linux-ng)" "./tools/windows/run_enum4linux-ng.sh"
        "Web: Scan Server (nikto)"           "./tools/web/run_nikto.sh"
    )
    tool_flags=(
        "WiFi: Discover (airodump-ng)"       "wifi"
        "WiFi: Inject (aireplay-ng)"         "wifi"
    )
    local -a menu_items
    menu_items=(
        "Bluetooth: Scan (btscanner)"
        "Bluetooth: Manage (bluetoothctl)"
        "WiFi: Discover (airodump-ng)"
        "WiFi: Inject (aireplay-ng)"
        "LAN: Network Scan (nmap)"
        "LAN: ARP Spoof (arpspoof)"
        "Windows: Enumerate (enum4linux-ng)"
        "Web: Scan Server (nikto)"
        "View Script (Test)"
        "Exit Toolkit"
    )
    integer current_item=0 num_items=${#menu_items[@]} local key_name 
    display_status "Navigate: UP/DOWN Arrows | Select: ENTER | Quit: 'q'"

    while true; do
        for i in {0..$((num_items - 1))}; do
            local item_label="${menu_items[i+1]}" display_line=$((i + 4)) 
            zcurses_addstr "$main_win" "$display_line" 5 "$(printf '%*s' $((cols-10)) '')" 
            if (( i == current_item )); then
                if (( colors_initialized_successfully && color_pair_highlight > 0 )); then zcurses_attr_on "$main_win" "color_pair($color_pair_highlight)"; fi
                zcurses_addstr "$main_win" "$display_line" 5 "> $item_label"
                if (( colors_initialized_successfully && color_pair_highlight > 0 )); then zcurses_attr_off "$main_win" "color_pair($color_pair_highlight)"; else zcurses_attr_off "$main_win" "reverse"; fi # Ensure reverse is off if fallback used
            else zcurses_addstr "$main_win" "$display_line" 5 "  $item_label"; fi
        done
        zcurses_refresh_win "$main_win" 

        integer key_code; zcurses_readkey key_code key_name; log_message "Key: $key_name ($key_code)"

        case "$key_name" in
            "KEY_UP") ((current_item = (current_item - 1 + num_items) % num_items)); display_status "Selected: ${menu_items[current_item+1]}";;
            "KEY_DOWN") ((current_item = (current_item + 1) % num_items)); display_status "Selected: ${menu_items[current_item+1]}";;
            "KEY_ENTER"|"\n"|"\r") 
                local selected_tool_name="${menu_items[current_item+1]}"
                log_message "Selected: '$selected_tool_name'"
                display_status "Processing: $selected_tool_name..."

                local wrapper_script_path="" current_tool_type=""
                integer is_wifi_tool=0
                typeset original_nm_status="unknown" managed_interface=""

                if [[ "$selected_tool_name" == "Exit Toolkit" ]]; then
                    log_message "Exit selected."; zcurses_delwin "$main_win"; return 0 
                elif [[ "$selected_tool_name" == "View Script (Test)" ]]; then
                    log_message "'View Script (Test)' selected."
                    local test_script_path="./test_display_script.sh"; echo "#!/bin/zsh\necho 'Test script content'" > "$test_script_path"; chmod +x "$test_script_path"
                    display_script_content "$test_script_path"; rm "$test_script_path"
                    zcurses_clear; redraw_main_window_elements; display_status "Navigate: UP/DOWN | ENTER: Select | q: Quit"; continue 
                fi

                wrapper_script_path="${tool_paths[$selected_tool_name]}"
                current_tool_type="${tool_flags[$selected_tool_name]}"

                if [[ -z "$wrapper_script_path" ]]; then
                    zcurses_messagebox "Tool '$selected_tool_name' not configured." "Config Error"
                    log_message "Config Error: No path for $selected_tool_name"
                    zcurses_clear; redraw_main_window_elements; display_status "Config error for $selected_tool_name"; continue
                fi
                
                if [[ "$current_tool_type" == "wifi" ]]; then is_wifi_tool=1; fi

                if (( is_wifi_tool )); then
                    if ! check_root_privileges; then
                        log_message "WiFi tool: Root needed. Skipping WiFi setup."; display_status "Root needed for WiFi setup. Skipping."; sleep 2
                    elif zcurses_yesno_box "Auto-manage WiFi (NetworkManager stop, monitor mode enable)?" "WiFi Setup"; then
                        log_message "User agreed to auto WiFi setup."
                        [[ -n "$ZCURSES_IS_INITIALIZED" ]] && { zcurses_end; unset ZCURSES_IS_INITIALIZED; clear; }
                        echo -n "Enter wireless interface (e.g., wlan0): "; read managed_interface
                        if [[ -z "$managed_interface" ]]; then
                            echo "No interface. Aborting WiFi setup."; sleep 2
                            if ! zcurses_init; then _initial_log_message "CRIT: zcurses re-init failed."; echo "CRIT: zcurses re-init failed." >&2; exit 1; fi
                            export ZCURSES_IS_INITIALIZED=1; init_colors; zcurses_clear; redraw_main_window_elements
                            display_status "WiFi setup aborted: No interface."; continue 
                        fi
                        log_message "User interface: $managed_interface"
                        if ! zcurses_init; then _initial_log_message "CRIT: zcurses re-init failed."; echo "CRIT: zcurses re-init failed." >&2; exit 1; fi
                        export ZCURSES_IS_INITIALIZED=1; init_colors; zcurses_clear; redraw_main_window_elements
                        
                        display_status "Checking NM status for $managed_interface..."
                        if systemctl is-active --quiet NetworkManager; then original_nm_status="active"; log_message "NM active."; manage_network_manager "stop";
                        elif systemctl is-inactive --quiet NetworkManager || systemctl is-failed --quiet NetworkManager; then original_nm_status="inactive"; log_message "NM inactive/failed."; display_status "NM already inactive/failed.";
                        else original_nm_status="failed_to_check"; log_message "Failed to get NM status."; display_status "Could not get NM status."; fi
                        sleep 1; manage_monitor_mode "$managed_interface" "enable"; sleep 1 
                    else
                        log_message "User declined auto WiFi setup."; display_status "Skipping auto WiFi setup."; sleep 2 
                    fi
                    zcurses_clear; redraw_main_window_elements
                fi

                if [[ -n "$wrapper_script_path" ]]; then
                    log_message "Running: $wrapper_script_path for $selected_tool_name"
                    display_status "Launching: $selected_tool_name..."; sleep 1 
                    [[ -n "$ZCURSES_IS_INITIALIZED" ]] && { zcurses_end; unset ZCURSES_IS_INITIALIZED; }
                    clear 
                    if [[ -x "$wrapper_script_path" ]]; then "$wrapper_script_path"; else echo "ERR: $wrapper_script_path not exec."; log_message "ERR: $wrapper_script_path not exec."; sleep 2; fi
                    echo "\n--- Script finished ---"; echo -n "Press ENTER to return..."; read 
                    
                    if ! zcurses_init; then _initial_log_message "CRIT: zcurses re-init failed."; echo "CRIT: zcurses re-init failed." >&2; exit 1; fi
                    export ZCURSES_IS_INITIALIZED=1; log_message "zcurses re-init success."; init_colors 

                    if (( is_wifi_tool )) && [[ -n "$managed_interface" ]]; then
                        log_message "Post-tool WiFi cleanup for $managed_interface."
                        display_status "Reverting WiFi changes for $managed_interface..."
                        manage_monitor_mode "$managed_interface" "disable"
                        if [[ "$original_nm_status" == "active" ]]; then manage_network_manager "start"; else log_message "NM not restarted (was not active)."; display_status "NM not restarted."; fi
                        sleep 1; unset managed_interface; unset original_nm_status
                    fi
                    zcurses_clear; redraw_main_window_elements; display_status "Navigate: UP/DOWN | ENTER: Select | q: Quit"
                fi
                ;;
            "q") log_message "Quit action."; zcurses_delwin "$main_win"; return 0;;
            *) log_message "Unknown key: $key_name"; display_status "Unknown key. Use UP/DOWN, ENTER, q.";;
        esac
    done
    [[ -n "$main_win" ]] && zcurses_delwin "$main_win"; log_message "Main menu exited."; return 0 
}

# --- Main Script Execution ---
log_message "Toolkit script started. PID: $$" 
if ! zcurses_init; then local err_msg="CRITICAL Error: Could not initialize zcurses (zcurses_init failed)."; echo "$err_msg" >&2; log_message "$err_msg"; exit 1; fi
typeset -g ZCURSES_IS_INITIALIZED=1; log_message "zcurses initialized successfully."
init_colors

cleanup_and_exit() {
    local exit_status=$?; local signal_name=$1 
    [[ -n "$signal_name" ]] && log_message "Caught $signal_name. Exit: $exit_status. Cleaning up..." || log_message "Script ending. Exit: $exit_status. Cleaning up..."
    if [[ -n "$ZCURSES_IS_INITIALIZED" ]]; then display_status "Exiting toolkit..."; sleep 0.1; zcurses_end; unset ZCURSES_IS_INITIALIZED; log_message "zcurses ended."; fi
    log_message "Toolkit finished. Exit: $exit_status."; exit $exit_status
}
trap 'cleanup_and_exit' EXIT; trap 'cleanup_and_exit SIGINT' INT; trap 'cleanup_and_exit SIGTERM' TERM; trap 'cleanup_and_exit SIGHUP' HUP   

main_menu_return_code=0; main_menu || main_menu_return_code=$? 
if (( main_menu_return_code != 0 )); then log_message "Main menu error: $main_menu_return_code."; exit $main_menu_return_code; fi
log_message "Main menu returned successfully."; exit 0
