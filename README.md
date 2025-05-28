# Zsh Penetration Testing Toolkit

Welcome to the Zsh Penetration Testing Toolkit! This toolkit provides a streamlined, Zsh and Curses-based interface to manage and launch a collection of common penetration testing scripts and tools. It's designed for pentesters and security enthusiasts who prefer a command-line environment but appreciate a structured, menu-driven approach to accessing their arsenal.

Our goal is to simplify the execution of various tools by providing wrapper scripts that handle common configurations and logging, all accessible through an intuitive curses interface.

## 🚀 Installation

1.  **Clone the repository:**
    ```bash
    git clone <repository_url> # Replace <repository_url> with the actual URL
    cd zsh-pentest-toolkit
    ```
2.  **Ensure Zsh is installed:** Most modern Linux distributions and macOS systems come with Zsh. If not, you can typically install it via your system's package manager.
    *   For Debian/Ubuntu: `sudo apt install zsh`
    *   For Fedora: `sudo dnf install zsh`
    *   For macOS (if not default): `brew install zsh`
3.  **Zsh Curses Module (`zsh/curses`):** This module is a standard part of Zsh and should be available with your installation. The toolkit script (`pen_test_toolkit.zsh`) will attempt to load it automatically using `zmodload zsh/curses`. If you encounter issues, ensure your Zsh installation is complete and not a minimal version.

### Important: `zsh/curses` Module Prerequisites

This toolkit relies heavily on the `zsh/curses` module for its user interface. 
For the toolkit to function correctly, your Zsh environment must meet the following conditions:

1.  **`zsh/curses` Module Availability:** The `zmodload zsh/curses` command must successfully load the module.
2.  **Standard Curses Functions:** The loaded `zsh/curses` module must provide standard curses function names, such as:
    *   `zcurses_init`
    *   `zcurses_end`
    *   `zcurses_newwin`
    *   `zcurses_addstr`
    *   `zcurses_refresh`
    *   `zcurses_clear`
    *   `zcurses_box`
    *   `zcurses_attr` (or `zcurses_attr_on`/`zcurses_attr_off`)
    *   `zcurses_readkey`
    *   `zcurses_getmaxyx`
    *   `zcurses_delwin`
    *   `zcurses_messagebox` (if available, or similar functionality)
    *   Color functions like `zcurses_start_color`, `zcurses_init_pair` (if color features are desired).

If you encounter errors like "zcurses_init: command not found" or similar, it likely means your Zsh's `curses` module is missing, incomplete, or uses different function names. Please ensure your Zsh installation includes a fully functional `curses` module that adheres to these common function names. This might involve recompiling Zsh with appropriate options or installing an alternative `zsh-curses` package if your distribution provides one.

4.  **Install Penetration Testing Tools:** The individual tools wrapped by this toolkit need to be installed separately on your system. The wrapper scripts within the toolkit are designed to notify you if a specific tool is missing. Common installation commands for Debian/Ubuntu-based systems are:
    *   `btscanner`: `sudo apt install btscanner`
    *   `bluez` (for `bluetoothctl`): `sudo apt install bluez`
    *   `aircrack-ng` suite (for `airodump-ng`, `aireplay-ng`): `sudo apt install aircrack-ng`
    *   `nmap`: `sudo apt install nmap`
    Refer to your distribution's documentation for installing these tools on other systems.
5.  **Make the main script executable:**
    ```bash
    chmod +x pen_test_toolkit.zsh
    ```
6.  **(Optional) Review individual wrapper scripts:** The tool wrapper scripts are located in the `tools/` directory (e.g., `tools/bluetooth/run_btscanner.sh`). You may want to review them to understand their specific operations or if you need to modify them for advanced use cases. Ensure they are also executable (`chmod +x tools/*/*.sh`).

## 🛠️ Usage

1.  **Run the main toolkit script** from the root directory of the project:
    ```bash
    ./pen_test_toolkit.zsh
    ```
2.  **Navigate the menu:**
    *   Use the **UP** and **DOWN arrow keys** to highlight different tools or options.
    *   Press **ENTER** to select a highlighted tool/option. This will either launch the tool's wrapper script or take you to a submenu (future feature).
3.  **Exiting:**
    *   Press **'q'** to quit the current menu or, if at the main menu, to exit the toolkit.
    *   The "Exit Toolkit" option in the main menu will also close the application.
4.  **Tool Interaction:** Once a tool is selected, its wrapper script will take over. This might involve:
    *   The Zsh/Curses interface closing temporarily to run the tool in the standard terminal.
    *   Prompts for further information (e.g., network interface, target IP).
    *   Follow the on-screen instructions provided by each wrapper script.
5.  **Logging:** All significant actions, tool executions, and errors are logged in `toolkit.log` in the root directory of the toolkit. This file can be useful for tracking your activities or debugging issues.

## ⚔️ Penetration Testing Tools

This toolkit includes wrapper scripts for a variety of tools. Here's a breakdown of the currently integrated tools:

### Bluetooth Tools

| Tool             | Description                                      | Purpose in Pentesting                                 |
|------------------|--------------------------------------------------|-------------------------------------------------------|
| **btscanner**    | A command-line tool (and older GUI) to scan for Bluetooth devices. | Discovering nearby Bluetooth devices (classic and LE depending on hardware/tool version), gathering information like device name, MAC address, class, and sometimes services. Useful for initial Bluetooth reconnaissance. |
| **bluetoothctl** | The primary command-line interface for managing Bluetooth devices on Linux via BlueZ. | Interactive management of Bluetooth adapters and devices, including scanning, pairing, connecting, and exploring services. Essential for deeper interaction with Bluetooth targets. |

### 📶 WiFi Tools

| Tool             | Description                                      | Purpose in Pentesting                                 |
|------------------|--------------------------------------------------|-------------------------------------------------------|
| **airodump-ng**  | Part of the Aircrack-ng suite, used for 802.11 packet capture. | Discovering WiFi networks (APs) and connected clients, capturing raw wireless packets, identifying ESSIDs, BSSIDs, channels, encryption types, and collecting WPA/WPA2 handshakes for offline cracking. |
| **aireplay-ng**  | Also part of Aircrack-ng, used to inject/replay wireless frames. | Performing various attacks like deauthentication (to disconnect clients), fake authentication (to probe APs), ARP replay (to stimulate traffic for WEP cracking), and other specialized frame injection tasks. |

### 💻 LAN Tools

| Tool             | Description                                      | Purpose in Pentesting                                 |
|------------------|--------------------------------------------------|-------------------------------------------------------|
| **nmap**         | (Network Mapper) A versatile and powerful open-source tool for network exploration and security auditing. | Host discovery (identifying live hosts on a network), port scanning (detecting open TCP/UDP ports), service enumeration (identifying services running on open ports and their versions), OS detection, and vulnerability scanning using the Nmap Scripting Engine (NSE). |

### 🖼️ Windows Tools
[Windows-specific tools will be listed here once integrated.]

### 🤖 Android Tools
[Android-specific tools will be listed here once integrated.]

### 🍏 Apple (macOS/iOS) Tools
[Apple-specific tools will be listed here once integrated.]

### 🌐 Router Tools
[Router assessment tools will be listed here once integrated.]

### 🔄 Switch Tools
[Network switch assessment tools will be listed here once integrated.]

### 📺 IPTV Tools
[IPTV testing tools will be listed here once integrated.]

### 🚪 Gateway Tools
[Gateway assessment tools will be listed here once integrated.]

## ✨ Contributing

Contributions are welcome! If you'd like to add new tools, improve existing ones, or enhance the interface:

1.  **Fork the repository.**
2.  **Create a new branch** for your feature (e.g., `git checkout -b feature/AmazingTool`).
3.  **Develop your feature.** If adding a new tool, please try to follow the existing wrapper script structure in the `tools/` directory.
    *   Include checks for tool installation.
    *   Provide clear user prompts and logging.
    *   Ensure the script is executable.
4.  **Commit your changes** (`git commit -m 'Add some AmazingTool'`).
5.  **Push to the branch** (`git push origin feature/AmazingTool`).
6.  **Open a Pull Request** against the main branch of the original repository.

Please ensure wrapper scripts are well-commented and the main `pen_test_toolkit.zsh` menu is updated accordingly if you add a new tool.

## 📄 License

This project is licensed under the MIT License.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
