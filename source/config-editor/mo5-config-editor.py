#!/usr/bin/env python3
"""MO5 configuration editor.

Graphical front-end of generate-generic-image.sh:
- generate an image, with a form built from the options described by the generator (--describe),
  and load or save the generation scripts of work/target;
- read and modify the controller, display and sound settings of a generated image or of an SD card.

The generator stays the single source of truth: this program knows no option by itself.
"""

import json
import os
import queue
import re
import shlex
import struct
import subprocess
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, simpledialog, ttk

HERE = os.path.dirname(os.path.abspath(__file__))
REPOSITORY = os.path.normpath(os.path.join(HERE, "..", ".."))
GENERATOR = os.path.join(REPOSITORY, "source", "generate-image", "generate-generic-image.sh")
TARGET_DIRECTORY = os.path.join(REPOSITORY, "work", "target")
ORIGIN_DIRECTORY = os.path.join(REPOSITORY, "work", "origin")
RECORD_NAME = "mo5-options.conf"


# Generator description ################################################


def describe_generator():
    """Options, categories and conflicts, as described by the generator."""
    output = subprocess.run(["bash", GENERATOR, "--describe"], capture_output=True, text=True, check=True).stdout
    return json.loads(output)


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


def list_sd_cards():
    """Removable or USB disks that do not hold the running system: [(path, description)]."""
    output = subprocess.run(["lsblk", "-J", "-o", "PATH,SIZE,MODEL,VENDOR,RM,TRAN,TYPE,MOUNTPOINT"],
                            capture_output=True, text=True, check=True).stdout
    cards = []
    for disk in json.loads(output)["blockdevices"]:
        if disk["type"] != "disk" or not (disk["rm"] in (True, "1") or disk["tran"] == "usb"):
            continue
        # card reader without card
        if disk["size"] in ("0", "0B", None):
            continue
        mountpoints = [child.get("mountpoint") for child in disk.get("children", [])] + [disk.get("mountpoint")]
        if any(mountpoint in ("/", "/boot", "/boot/efi", "/home") for mountpoint in mountpoints):
            continue
        label = " ".join(part.strip() for part in (disk.get("vendor") or "", disk.get("model") or "") if part)
        cards.append((disk["path"], f"{disk['path']}  {disk['size']}  {label}".strip()))
    return cards


def read_sd_card_boot_files(device, names):
    """Read files of the boot partition of an SD card, mounted by the desktop or with udisksctl (no sudo)."""
    output = subprocess.run(["lsblk", "-J", "-o", "PATH,TYPE,MOUNTPOINT", device], capture_output=True, text=True,
                            check=True).stdout
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


def settings_from_config_txt(text, hdmi_modes):
    """Display settings guessed from config.txt, for images generated before mo5-options.conf."""
    active = {}
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith(("#", "[")) and "=" in line:
            key, value = line.split("=", 1)
            active[key.strip()] = value.strip()
    settings = {}
    if active.get("disable_overscan") == "0" and any(f"overscan_{side}" in active for side in ("left", "right", "top", "bottom")):
        sides = [f"{side}={active[f'overscan_{side}']}" for side in ("left", "right", "top", "bottom")
                 if active.get(f"overscan_{side}", "0") != "0"]
        if sides:
            settings["border"] = ",".join(sides)
    rotation = {"1": "90", "2": "180", "3": "270"}.get(active.get("display_rotate", ""))
    if rotation:
        settings["rotate"] = rotation
    if "hdmi_group" in active and "hdmi_mode" in active:
        for name, (group, mode) in hdmi_modes.items():
            if active["hdmi_group"] == group and active["hdmi_mode"] == mode:
                settings["hdmi-mode"] = name
    if active.get("enable_tvout") == "1":
        settings["tv-out"] = {"2": "pal", "0": "ntsc"}.get(active.get("sdtv_mode", ""), "pal")
    return settings


# Script files of work/target ##########################################


def parse_generation_script(path):
    """Arguments given to the generator by a work/target script, with paths made absolute."""
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


def quote(value):
    """Quote a shell value the way the work/target scripts do."""
    if re.fullmatch(r"[\w@%+=:,./-]+", value):
        return value
    if not re.search(r'["$`\\]', value):
        return f'"{value}"'
    return shlex.quote(value)


# Generator process ####################################################


class GeneratorRun:
    """Runs the generator through sudo, and streams its output to a queue."""

    def __init__(self, arguments, password, working_directory):
        command = ["sudo", "-S", "-p", "", "bash", GENERATOR, "--batch"] + arguments
        self.lines = queue.Queue()
        self.process = subprocess.Popen(command, cwd=working_directory, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.process.stdin.write((password or "") + "\n")
        self.process.stdin.close()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.process.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def stop(self):
        if self.process.poll() is None:
            self.process.terminate()


# User interface #######################################################


class OptionsForm(ttk.Frame):
    """Form built from the generator description, for the given categories."""

    def __init__(self, parent, description, categories, browse_directory):
        super().__init__(parent)
        self.description = description
        self.options = {option["long"]: option for option in description["options"]}
        self.variables = {}
        self.browse_directory = browse_directory
        labels = {category["name"]: category["label"] for category in description["categories"]}
        for category in categories:
            options = [option for option in description["options"] if option["category"] == category]
            if not options:
                continue
            frame = ttk.LabelFrame(self, text=labels.get(category, category), padding=6)
            frame.pack(fill="x", padx=4, pady=4)
            frame.columnconfigure(1, weight=1)
            for row, option in enumerate(options):
                self._add_field(frame, row, option)

    def _add_field(self, frame, row, option):
        name = option["long"]
        ttk.Label(frame, text=f"--{name}").grid(row=row * 2, column=0, sticky="w", padx=(0, 8))
        if option["type"] == "flag":
            variable = tk.BooleanVar()
            ttk.Checkbutton(frame, variable=variable).grid(row=row * 2, column=1, sticky="w")
        else:
            variable = tk.StringVar()
            if option["type"] == "choice":
                ttk.Combobox(frame, textvariable=variable, values=[""] + option["values"], state="readonly").grid(
                    row=row * 2, column=1, sticky="ew")
            else:
                ttk.Entry(frame, textvariable=variable).grid(row=row * 2, column=1, sticky="ew")
                if option["type"] in ("file", "dir", "path"):
                    ttk.Button(frame, text="…", width=3,
                               command=lambda: self._browse(option, variable)).grid(row=row * 2, column=2, padx=(4, 0))
        hint = option["description"]
        if option["label"] and option["type"] not in ("file", "dir", "path"):
            hint = f"{option['label']} : {hint}"
        ttk.Label(frame, text=hint, foreground="gray40", wraplength=620, justify="left").grid(
            row=row * 2 + 1, column=1, columnspan=2, sticky="w", pady=(0, 4))
        self.variables[name] = variable

    def _browse(self, option, variable):
        initial = os.path.dirname(variable.get()) if variable.get() else self.browse_directory(option)
        if option["type"] == "dir":
            path = filedialog.askdirectory(initialdir=initial, title=f"--{option['long']}")
        elif option["type"] == "path":
            path = filedialog.asksaveasfilename(initialdir=initial, title=f"--{option['long']}")
        else:
            path = filedialog.askopenfilename(initialdir=initial, title=f"--{option['long']}")
        if path:
            variable.set(path)

    def clear(self):
        for variable in self.variables.values():
            variable.set(False if isinstance(variable, tk.BooleanVar) else "")

    def set_values(self, values):
        """values: {long name: value}, "ON" or True for a flag."""
        for name, value in values.items():
            if name in self.variables:
                variable = self.variables[name]
                variable.set(value in (True, "ON") if isinstance(variable, tk.BooleanVar) else value)

    def values(self):
        """{long name: value} of the filled fields."""
        result = {}
        for name, variable in self.variables.items():
            value = variable.get()
            if value not in ("", False):
                result[name] = value
        return result

    def check_conflicts(self, values):
        for first, second in self.description["conflicts"]:
            if first in values and second in values:
                return f"--{first} et --{second} ne se combinent pas"
        return None


class LogWindow(ttk.Frame):
    """Generator output, with a stop button."""

    def __init__(self, parent):
        super().__init__(parent)
        self.text = scrolledtext.ScrolledText(self, height=12, font="TkFixedFont", state="disabled")
        self.text.pack(fill="both", expand=True)

    def clear(self):
        self.text.configure(state="normal")
        self.text.delete("1.0", "end")
        self.text.configure(state="disabled")

    def append(self, line):
        self.text.configure(state="normal")
        self.text.insert("end", line)
        self.text.see("end")
        self.text.configure(state="disabled")


class Editor(tk.Tk):

    def __init__(self):
        super().__init__()
        self.title("Éditeur de configuration MO5")
        self.geometry("900x860")
        self.password = None
        self.run = None
        try:
            self.description = describe_generator()
        except (subprocess.CalledProcessError, json.JSONDecodeError) as error:
            messagebox.showerror("Générateur", f"Impossible de lire la description des options :\n{error}")
            raise SystemExit(1)
        self.options = {option["long"]: option for option in self.description["options"]}
        self.hdmi_modes = self._hdmi_modes()

        notebook = ttk.Notebook(self)
        notebook.pack(fill="both", expand=True, padx=6, pady=6)
        notebook.add(self._generation_tab(notebook), text="Générer une image")
        notebook.add(self._modification_tab(notebook), text="Modifier une image ou une carte SD")

        self.log = LogWindow(self)
        self.log.pack(fill="both", expand=False, padx=6, pady=(0, 6))
        self.status = tk.StringVar(value="Prêt.")
        bottom = ttk.Frame(self)
        bottom.pack(fill="x", padx=6, pady=(0, 6))
        ttk.Label(bottom, textvariable=self.status).pack(side="left")
        self.stop_button = ttk.Button(bottom, text="Arrêter", command=self._stop, state="disabled")
        self.stop_button.pack(side="right")

    def _hdmi_modes(self):
        """name -> (hdmi_group, hdmi_mode), read from the generator table (for the config.txt fallback)."""
        modes = {}
        with open(GENERATOR, encoding="utf-8") as file:
            for match in re.finditer(r'\[(\w+)\]="(\d+) (\d+)"', file.read()):
                modes[match.group(1)] = (match.group(2), match.group(3))
        return modes

    def _scrollable(self, parent):
        """A vertically scrollable frame."""
        outer = ttk.Frame(parent)
        canvas = tk.Canvas(outer, highlightthickness=0)
        scrollbar = ttk.Scrollbar(outer, orient="vertical", command=canvas.yview)
        inner = ttk.Frame(canvas)
        inner.bind("<Configure>", lambda event: canvas.configure(scrollregion=canvas.bbox("all")))
        window = canvas.create_window((0, 0), window=inner, anchor="nw")
        canvas.bind("<Configure>", lambda event: canvas.itemconfigure(window, width=event.width))
        canvas.configure(yscrollcommand=scrollbar.set)

        # mouse wheel (X11 buttons 4 and 5) on the canvas under the pointer only
        def wheel_on(_event):
            canvas.bind_all("<Button-4>", lambda event: canvas.yview_scroll(-1, "units"))
            canvas.bind_all("<Button-5>", lambda event: canvas.yview_scroll(1, "units"))

        def wheel_off(_event):
            canvas.unbind_all("<Button-4>")
            canvas.unbind_all("<Button-5>")

        outer.bind("<Enter>", wheel_on)
        outer.bind("<Leave>", wheel_off)
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        return outer, inner

    def _browse_directory(self, option):
        if option["category"] == "image" and option["long"] == "input":
            return ORIGIN_DIRECTORY
        if option["category"] in ("mode", "game", "controller"):
            return os.path.join(ORIGIN_DIRECTORY, "game-to-install")
        return TARGET_DIRECTORY

    # Generation tab #####################################################

    def _generation_tab(self, notebook):
        tab = ttk.Frame(notebook)
        buttons = ttk.Frame(tab)
        buttons.pack(fill="x", pady=(4, 0))
        ttk.Button(buttons, text="Charger un script…", command=self._load_script).pack(side="left", padx=4)
        ttk.Button(buttons, text="Enregistrer comme script…", command=self._save_script).pack(side="left", padx=4)
        ttk.Button(buttons, text="Vider", command=lambda: self.generation_form.clear()).pack(side="left", padx=4)
        ttk.Button(buttons, text="Générer l'image", command=self._generate).pack(side="right", padx=4)

        outer, inner = self._scrollable(tab)
        outer.pack(fill="both", expand=True, pady=4)
        categories = [category["name"] for category in self.description["categories"] if category["name"] != "run"]
        self.generation_form = OptionsForm(inner, self._without(self.description, {"modify"}), categories,
                                           self._browse_directory)
        self.generation_form.pack(fill="x")
        self.generation_form.set_values({"input": os.path.join(ORIGIN_DIRECTORY, "origin.img")})
        return tab

    @staticmethod
    def _without(description, names):
        """The description without some options."""
        copy = dict(description)
        copy["options"] = [option for option in description["options"] if option["long"] not in names]
        return copy

    def _generation_arguments(self, values):
        arguments = []
        for name, value in values.items():
            arguments.append(f"--{name}")
            if self.options[name]["type"] != "flag":
                arguments.append(value)
        return arguments

    def _load_script(self):
        path = filedialog.askopenfilename(initialdir=TARGET_DIRECTORY, title="Script de génération",
                                          filetypes=[("Scripts", "*.sh"), ("Tous les fichiers", "*")])
        if not path:
            return
        try:
            arguments = parse_generation_script(path)
        except ValueError as error:
            messagebox.showerror("Script", str(error))
            return
        by_short = {f"-{option['short']}": option for option in self.description["options"]}
        values = {}
        index = 0
        while index < len(arguments):
            argument = arguments[index]
            name, _, inline = argument.partition("=")
            option = self.options.get(name[2:]) if name.startswith("--") else by_short.get(name)
            if option is None:
                messagebox.showwarning("Script", f"Option inconnue ignorée : {argument}")
                index += 1
                continue
            if option["type"] == "flag":
                values[option["long"]] = True
            else:
                if inline:
                    value = inline
                else:
                    index += 1
                    value = arguments[index] if index < len(arguments) else ""
                if option["type"] in ("file", "dir", "path"):
                    value = os.path.normpath(os.path.join(os.path.dirname(path), value))
                values[option["long"]] = value
            index += 1
        self.generation_form.clear()
        self.generation_form.set_values(values)
        self.status.set(f"Script chargé : {os.path.basename(path)}")

    def _save_script(self):
        values = self.generation_form.values()
        error = self._check_generation(values)
        if error:
            messagebox.showerror("Options", error)
            return
        path = filedialog.asksaveasfilename(initialdir=TARGET_DIRECTORY, title="Enregistrer le script",
                                            defaultextension=".sh", filetypes=[("Scripts", "*.sh")])
        if not path:
            return
        directory = os.path.dirname(path)
        lines = [f"{os.path.relpath(GENERATOR, directory)} \\"]
        for name, value in values.items():
            option = self.options[name]
            if option["type"] == "flag":
                lines.append(f"    --{name} \\")
            else:
                if option["type"] in ("file", "dir", "path"):
                    value = os.path.relpath(os.path.abspath(os.path.join(TARGET_DIRECTORY, value)), directory)
                lines.append(f"    --{name} {quote(value)} \\")
        lines += ["    2>&1 \\", "    | tee", ""]
        with open(path, "w", encoding="utf-8") as file:
            file.write("\n".join(lines))
        os.chmod(path, 0o755)
        self.status.set(f"Script enregistré : {os.path.basename(path)} (à lancer depuis {directory})")

    def _check_generation(self, values):
        if "generic" not in values and "specific" not in values:
            return "Choisir --generic ou --specific"
        for name in ("input", "output"):
            if name not in values:
                return f"--{name} est obligatoire"
        return self.generation_form.check_conflicts(values)

    def _generate(self):
        values = self.generation_form.values()
        error = self._check_generation(values)
        if error:
            messagebox.showerror("Options", error)
            return
        # paths relative to work/target, like the scripts
        for name, value in values.items():
            if self.options[name]["type"] in ("file", "dir", "path"):
                values[name] = os.path.abspath(os.path.join(TARGET_DIRECTORY, value))
        if os.path.exists(values["output"]) and not messagebox.askyesno(
                "Image existante", f"{values['output']} existe déjà et sera remplacée. Continuer ?"):
            return
        self._start(self._generation_arguments(values), f"Génération de {os.path.basename(values['output'])}")

    # Modification tab ###################################################

    def _modification_tab(self, notebook):
        tab = ttk.Frame(notebook)
        source = ttk.LabelFrame(tab, text="Image ou carte SD", padding=6)
        source.pack(fill="x", padx=4, pady=4)
        source.columnconfigure(1, weight=1)

        self.target = tk.StringVar()
        ttk.Label(source, text="Cible :").grid(row=0, column=0, sticky="w")
        ttk.Entry(source, textvariable=self.target).grid(row=0, column=1, sticky="ew", padx=4)
        ttk.Button(source, text="Image…", command=self._choose_image).grid(row=0, column=2)

        self.cards = ttk.Combobox(source, state="readonly")
        ttk.Label(source, text="Carte SD :").grid(row=1, column=0, sticky="w", pady=(4, 0))
        self.cards.grid(row=1, column=1, sticky="ew", padx=4, pady=(4, 0))
        self.cards.bind("<<ComboboxSelected>>", self._choose_card)
        ttk.Button(source, text="Actualiser", command=self._refresh_cards).grid(row=1, column=2, pady=(4, 0))

        ttk.Button(source, text="Lire les réglages", command=self._read_settings).grid(row=2, column=1, sticky="w",
                                                                                        padx=4, pady=(6, 0))
        self.recorded = tk.StringVar()
        ttk.Label(source, textvariable=self.recorded, foreground="gray30", wraplength=760, justify="left").grid(
            row=3, column=0, columnspan=3, sticky="w", pady=(6, 0))

        buttons = ttk.Frame(tab)
        buttons.pack(fill="x")
        ttk.Button(buttons, text="Appliquer les réglages", command=self._modify).pack(side="right", padx=4)
        ttk.Label(buttons, text="Tous les réglages ci-dessous sont appliqués : un champ vide revient à la valeur par défaut. "
                                "Manette vide : inchangée.", foreground="gray40").pack(side="left", padx=4)

        outer, inner = self._scrollable(tab)
        outer.pack(fill="both", expand=True, pady=4)
        categories = [category["name"] for category in self.description["categories"] if category["settings"]]
        self.modification_form = OptionsForm(inner, self.description, categories, self._browse_directory)
        self.modification_form.pack(fill="x")
        self._refresh_cards()
        return tab

    def _choose_image(self):
        path = filedialog.askopenfilename(initialdir=TARGET_DIRECTORY, title="Image générée",
                                          filetypes=[("Images", "*.img"), ("Tous les fichiers", "*")])
        if path:
            self.target.set(path)
            self._read_settings()

    def _refresh_cards(self):
        try:
            self.card_list = list_sd_cards()
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            self.card_list = []
        self.cards.configure(values=[description for _, description in self.card_list] or ["(aucune carte détectée)"])
        self.cards.set("")

    def _choose_card(self, _event=None):
        index = self.cards.current()
        if 0 <= index < len(self.card_list):
            self.target.set(self.card_list[index][0])
            self._read_settings()

    def _read_settings(self):
        target = self.target.get()
        if not target:
            messagebox.showerror("Cible", "Choisir une image ou une carte SD")
            return
        names = [RECORD_NAME, "config.txt"]
        try:
            if os.path.isfile(target):
                files = read_boot_files(target, names)
            else:
                files = read_sd_card_boot_files(target, names)
        except (OSError, RuntimeError, struct.error, subprocess.CalledProcessError) as error:
            messagebox.showerror("Lecture", f"Impossible de lire {target} :\n{error}")
            return
        self.modification_form.clear()
        if RECORD_NAME in files:
            record = parse_record(files[RECORD_NAME])
            settings = {name: value for name, value in record.items()
                        if name in self.options and self.options[name]["category"] in
                        [category["name"] for category in self.description["categories"] if category["settings"]]}
            # the controller field installs a new file: the recorded one is only shown
            settings.pop("controller", None)
            self.modification_form.set_values(settings)
            game = record.get("specific") and f"jeu {record['specific']}" or (record.get("generic") and "image générique") or "?"
            details = [game]
            if record.get("emulator"):
                details.append(f"émulateur {record['emulator']}")
            details.append(f"manette {record.get('controller', 'aucune installée')}")
            details.append(f"générée le {record.get('generated', '?')}")
            if record.get("modified"):
                details.append(f"modifiée le {record['modified']}")
            self.recorded.set("Réglages lus dans /boot/" + RECORD_NAME + " : " + ", ".join(details) + ".")
        elif "config.txt" in files:
            self.modification_form.set_values(settings_from_config_txt(files["config.txt"], self.hdmi_modes))
            self.recorded.set("Pas de /boot/" + RECORD_NAME + " (image générée avant son introduction) : seuls les réglages "
                              "de config.txt ont été relus. Le son, les scanlines et le lissage sont à vérifier.")
        else:
            self.recorded.set("Ni /boot/" + RECORD_NAME + " ni config.txt : ce n'est pas une image RetroPie ?")
        self.status.set(f"Réglages lus : {target}")

    def _modify(self):
        target = self.target.get()
        if not target:
            messagebox.showerror("Cible", "Choisir une image ou une carte SD")
            return
        values = self.modification_form.values()
        error = self.modification_form.check_conflicts(values)
        if error:
            messagebox.showerror("Options", error)
            return
        if not os.path.isfile(target) and not messagebox.askyesno(
                "Carte SD", f"Modifier la carte {target} ? Ses partitions vont être démontées."):
            return
        self._start(["--modify", target] + self._generation_arguments(values), f"Modification de {target}")

    # Generator runs #####################################################

    def _ask_password(self):
        """sudo password, checked then kept for the session (not needed when sudo has no password)."""
        if subprocess.run(["sudo", "-n", "true"], capture_output=True).returncode == 0:
            return ""
        prompt = "Mot de passe sudo (pour monter les images) :"
        while self.password is None:
            password = simpledialog.askstring("sudo", prompt, show="*", parent=self)
            if password is None:
                return None
            check = subprocess.run(["sudo", "-S", "-k", "-p", "", "true"], input=password + "\n", capture_output=True,
                                   text=True)
            if check.returncode == 0:
                self.password = password
            else:
                prompt = "Mot de passe incorrect. Mot de passe sudo :"
        return self.password

    def _start(self, arguments, label):
        if self.run is not None:
            messagebox.showwarning("Générateur", "Une opération est déjà en cours")
            return
        password = self._ask_password()
        if password is None:
            return
        self.log.clear()
        self.log.append("$ generate-generic-image.sh --batch " + " ".join(shlex.quote(a) for a in arguments) + "\n")
        self.status.set(label + "…")
        self.run = GeneratorRun(arguments, password, TARGET_DIRECTORY)
        self.stop_button.configure(state="normal")
        self.after(100, self._poll, label)

    def _poll(self, label):
        while True:
            try:
                line = self.run.lines.get_nowait()
            except queue.Empty:
                self.after(100, self._poll, label)
                return
            if line is None:
                break
            self.log.append(line)
        code = self.run.process.wait()
        if code == 0:
            self.status.set(f"{label} : terminé")
        else:
            self.status.set(f"{label} : échec (code {code}), voir le journal")
        self.run = None
        self.stop_button.configure(state="disabled")

    def _stop(self):
        if self.run is not None:
            self.run.stop()


if __name__ == "__main__":
    Editor().mainloop()
