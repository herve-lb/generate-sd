"""Logic of the MO5 configuration editor, without user interface.

The generator (generate-generic-image.sh) stays the single source of truth: options are read from
its --describe output, and images are generated or modified by running it.
"""

import json
import os
import re
import shlex
import struct
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
REPOSITORY = os.path.normpath(os.path.join(HERE, "..", ".."))
GENERATOR = os.path.join(REPOSITORY, "source", "generate-image", "generate-generic-image.sh")
TARGET_DIRECTORY = os.path.join(REPOSITORY, "work", "target")
ORIGIN_DIRECTORY = os.path.join(REPOSITORY, "work", "origin")
RECORD_NAME = "mo5-options.conf"
PATH_TYPES = ("file", "dir", "path")


# Generator description ################################################


def describe_generator():
    """Options, categories and conflicts, as described by the generator."""
    output = subprocess.run(["bash", GENERATOR, "--describe"], capture_output=True, text=True, check=True).stdout
    return json.loads(output)


def hdmi_modes():
    """HDMI mode name -> (hdmi_group, hdmi_mode), read from the generator table."""
    modes = {}
    with open(GENERATOR, encoding="utf-8") as file:
        for match in re.finditer(r'\[(\w+)\]="(\d+) (\d+)"', file.read()):
            modes[match.group(1)] = (match.group(2), match.group(3))
    return modes


def generator_arguments(options, values):
    """Command line arguments for {long name: value}; a flag value is True."""
    arguments = []
    for name, value in values.items():
        arguments.append(f"--{name}")
        if options[name]["type"] != "flag":
            arguments.append(value)
    return arguments


def conflict(description, values):
    """First pair of incompatible options found in values, or None."""
    for first, second in description["conflicts"]:
        if first in values and second in values:
            return first, second
    return None


# FAT boot partition reading, without mounting ########################


def read_boot_files(image_path, names):
    """Read files from the root directory of the first (FAT) partition of a disk image.

    Returns {lowercase name: text} for the names found. Long file names (VFAT) are supported.
    """
    with open(image_path, "rb") as image:
        image.seek(446)
        partition = image.read(16)
        start_sector = struct.unpack_from("<I", partition, 8)[0]
        offset = start_sector * 512

        def read(position, size):
            image.seek(offset + position)
            return image.read(size)

        boot_sector = read(0, 512)
        bytes_per_sector, sectors_per_cluster, reserved, fats, root_entries, _, _, fat_size16 = struct.unpack_from(
            "<HBHBHHBH", boot_sector, 11)
        fat_size = fat_size16 or struct.unpack_from("<I", boot_sector, 36)[0]
        fat32 = fat_size16 == 0
        fat_offset = reserved * bytes_per_sector
        root_offset = fat_offset + fats * fat_size * bytes_per_sector
        data_offset = root_offset + ((root_entries * 32 + bytes_per_sector - 1) // bytes_per_sector) * bytes_per_sector
        cluster_size = sectors_per_cluster * bytes_per_sector
        fat = read(fat_offset, fat_size * bytes_per_sector)

        def chain(cluster):
            end = 0x0FFFFFF8 if fat32 else 0xFFF8
            while 2 <= cluster < end:
                yield cluster
                if fat32:
                    cluster = struct.unpack_from("<I", fat, cluster * 4)[0] & 0x0FFFFFFF
                else:
                    cluster = struct.unpack_from("<H", fat, cluster * 2)[0]

        def read_clusters(first_cluster):
            return b"".join(read(data_offset + (cluster - 2) * cluster_size, cluster_size) for cluster in chain(first_cluster))

        if fat32:
            root = read_clusters(struct.unpack_from("<I", boot_sector, 44)[0])
        else:
            root = read(root_offset, root_entries * 32)

        wanted = {name.lower() for name in names}
        found = {}
        long_name_parts = []
        for position in range(0, len(root), 32):
            entry = root[position:position + 32]
            if entry[0] == 0:
                break
            if entry[0] == 0xE5:
                long_name_parts = []
                continue
            if entry[11] == 0x0F:
                # long name entry: 13 UTF-16 characters, the entries come last part first
                characters = entry[1:11] + entry[14:26] + entry[28:32]
                long_name_parts.insert(0, characters.decode("utf-16-le", errors="ignore"))
                continue
            short_name = entry[0:8].decode("latin-1").strip()
            extension = entry[8:11].decode("latin-1").strip()
            name = "".join(long_name_parts).split("\x00")[0] if long_name_parts else (
                short_name + ("." + extension if extension else ""))
            long_name_parts = []
            if name.lower() in wanted:
                cluster = struct.unpack_from("<H", entry, 26)[0] | (struct.unpack_from("<H", entry, 20)[0] << 16)
                size = struct.unpack_from("<I", entry, 28)[0]
                data = read_clusters(cluster)[:size] if cluster else b""
                found[name.lower()] = data.decode("utf-8", errors="replace")
        return found


# SD cards #############################################################


# transports of SD card readers: USB readers, and built-in readers (mmc), which are not flagged removable
CARD_TRANSPORTS = ("usb", "mmc")


def list_sd_cards():
    """Removable, USB or built-in reader disks with a card, that do not hold the running system: [(path, description)]."""
    # NAME keeps the tree output (partitions as children), needed to see the mount points
    output = subprocess.run(["lsblk", "-J", "--tree", "-o", "NAME,PATH,SIZE,MODEL,VENDOR,RM,TRAN,TYPE,MOUNTPOINT"],
                            capture_output=True, text=True, check=True).stdout
    cards = []
    for disk in json.loads(output)["blockdevices"]:
        if disk["type"] != "disk" or not (disk["rm"] in (True, "1") or disk["tran"] in CARD_TRANSPORTS):
            continue
        # card reader without card
        if disk["size"] in ("0", "0B", None):
            continue
        mountpoints = [child.get("mountpoint") for child in disk.get("children", [])] + [disk.get("mountpoint")]
        if any(mountpoint in ("/", "/boot", "/boot/efi", "/home") for mountpoint in mountpoints):
            continue
        label = " ".join(part.strip() for part in (disk.get("vendor") or "", disk.get("model") or "") if part)
        if not label and disk["tran"] == "mmc":
            label = "lecteur SD intégré"
        cards.append((disk["path"], f"{disk['path']}  {disk['size']}  {label}".strip()))
    return cards


def read_sd_card_boot_files(device, names):
    """Read files of the boot partition of an SD card, mounted by the desktop or with udisksctl (no sudo)."""
    output = subprocess.run(["lsblk", "-J", "--tree", "-o", "NAME,PATH,TYPE,MOUNTPOINT", device], capture_output=True,
                            text=True, check=True).stdout
    partitions = [child for child in json.loads(output)["blockdevices"][0].get("children", []) if child["type"] == "part"]
    if not partitions:
        raise RuntimeError(f"{device} n'a pas de partition")
    boot = partitions[0]
    mountpoint = boot.get("mountpoint")
    mounted_here = False
    if not mountpoint:
        result = subprocess.run(["udisksctl", "mount", "--no-user-interaction", "-b", boot["path"]],
                                capture_output=True, text=True)
        match = re.search(r" at (.+?)\.?$", result.stdout.strip())
        if result.returncode != 0 or not match:
            raise RuntimeError(f"Impossible de monter {boot['path']} : {result.stderr.strip() or result.stdout.strip()}")
        mountpoint = match.group(1)
        mounted_here = True
    try:
        found = {}
        for name in names:
            path = os.path.join(mountpoint, name)
            if os.path.isfile(path):
                with open(path, encoding="utf-8", errors="replace") as file:
                    found[name.lower()] = file.read()
        return found
    finally:
        if mounted_here:
            subprocess.run(["udisksctl", "unmount", "--no-user-interaction", "-b", boot["path"]], capture_output=True)


def read_target_boot_files(target, names):
    """Boot files of an image file or of an SD card device."""
    if os.path.isfile(target):
        return read_boot_files(target, names)
    return read_sd_card_boot_files(target, names)


# Settings of an image or card #########################################


def parse_record(text):
    """long_name=value lines of mo5-options.conf."""
    values = {}
    for line in text.splitlines():
        if line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def settings_from_config_txt(text, modes):
    """Display settings guessed from config.txt, for images generated before mo5-options.conf."""
    active = {}
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith(("#", "[")) and "=" in line:
            key, value = line.split("=", 1)
            active[key.strip()] = value.strip()
    settings = {}
    if active.get("disable_overscan") == "0":
        sides = [f"{side}={active[f'overscan_{side}']}" for side in ("left", "right", "top", "bottom")
                 if active.get(f"overscan_{side}", "0") != "0"]
        if sides:
            settings["border"] = ",".join(sides)
    rotation = {"1": "90", "2": "180", "3": "270"}.get(active.get("display_rotate", ""))
    if rotation:
        settings["rotate"] = rotation
    if "hdmi_group" in active and "hdmi_mode" in active:
        for name, (group, mode) in modes.items():
            if active["hdmi_group"] == group and active["hdmi_mode"] == mode:
                settings["hdmi-mode"] = name
    if active.get("enable_tvout") == "1":
        settings["tv-out"] = {"2": "pal", "0": "ntsc"}.get(active.get("sdtv_mode", ""), "pal")
    return settings


# Script files of work/target ##########################################


def parse_generation_script(path):
    """Arguments given to the generator by a work/target script, as written in the script."""
    with open(path, encoding="utf-8") as file:
        text = file.read()
    text = text.replace("\\\n", " ")
    tokens = shlex.split(text, comments=True)
    start = next((index for index, token in enumerate(tokens) if token.endswith("generate-generic-image.sh")), None)
    if start is None:
        raise ValueError("pas d'appel à generate-generic-image.sh dans ce script")
    arguments = []
    for token in tokens[start + 1:]:
        if token in ("2>&1", "|", "||", "&&", ";") or token.startswith((">", "2>")):
            break
        arguments.append(token)
    return arguments


def script_values(description, path):
    """{long name: value} of a work/target script, paths made absolute. Returns (values, unknown arguments)."""
    options = {option["long"]: option for option in description["options"]}
    by_short = {f"-{option['short']}": option for option in description["options"]}
    arguments = parse_generation_script(path)
    values, unknown = {}, []
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        name, _, inline = argument.partition("=")
        option = options.get(name[2:]) if name.startswith("--") else by_short.get(name)
        if option is None:
            unknown.append(argument)
        elif option["type"] == "flag":
            values[option["long"]] = True
        else:
            if inline:
                value = inline
            else:
                index += 1
                value = arguments[index] if index < len(arguments) else ""
            if option["type"] in PATH_TYPES:
                value = os.path.normpath(os.path.join(os.path.dirname(path), value))
            values[option["long"]] = value
        index += 1
    return values, unknown


def quote(value):
    """Quote a shell value the way the work/target scripts do."""
    if re.fullmatch(r"[\w@%+=:,./-]+", value):
        return value
    if not re.search(r'["$`\\]', value):
        return f'"{value}"'
    return shlex.quote(value)


def script_text(description, values, directory):
    """A self-contained work/target script, in the style of generate-zelda-links-awakening-dx-gbc.sh."""
    options = {option["long"]: option for option in description["options"]}
    lines = [f"{os.path.relpath(GENERATOR, directory)} \\"]
    for name, value in values.items():
        option = options[name]
        if option["type"] == "flag":
            lines.append(f"    --{name} \\")
        else:
            if option["type"] in PATH_TYPES:
                value = os.path.relpath(os.path.abspath(os.path.join(TARGET_DIRECTORY, value)), directory)
            lines.append(f"    --{name} {quote(value)} \\")
    lines += ["    2>&1 \\", "    | tee", ""]
    return "\n".join(lines)


# sudo #################################################################


def sudo_needs_password():
    return subprocess.run(["sudo", "-n", "true"], capture_output=True).returncode != 0


def sudo_password_is_valid(password):
    return subprocess.run(["sudo", "-S", "-k", "-p", "", "true"], input=password + "\n", capture_output=True,
                          text=True).returncode == 0


def sudo_command(arguments):
    """Program and arguments to run the generator through sudo, in batch mode (password on stdin)."""
    return "sudo", ["-S", "-p", "", "bash", GENERATOR, "--batch"] + arguments
