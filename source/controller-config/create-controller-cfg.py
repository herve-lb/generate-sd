#!/usr/bin/env python3
"""
Crée un fichier de configuration de manette RetroArch (autoconfig) depuis un PC Linux.

On branche la manette (ou l'encodeur USB de la borne) sur le PC, on appuie sur les
commandes demandées, et le fichier .cfg est écrit, prêt pour l'option -c de
generate-generic-image.sh.

Les numéros de boutons et d'axes sont calculés comme le fait le pilote "udev" de
RetroArch sur le Raspberry Pi : même noyau Linux, donc mêmes numéros.

Usage :
  create-controller-cfg.py -o "fichier.cfg"             # choisit la manette s'il y en a plusieurs
  create-controller-cfg.py -o "fichier.cfg" -d /dev/input/event20
  create-controller-cfg.py -l                           # liste les manettes branchées
"""

import argparse
import fcntl
import glob
import os
import select
import struct
import sys
import termios
import time

# Constantes du noyau (linux/input.h, linux/input-event-codes.h) ##########

EV_KEY = 0x01
EV_ABS = 0x03
KEY_MAX = 0x2ff
BTN_MISC = 0x100
BTN_JOYSTICK = 0x120
BTN_DIGI = 0x140
BTN_TRIGGER_HAPPY = 0x2c0
ABS_X = 0x00
ABS_HAT0X = 0x10
ABS_HAT3Y = 0x17
ABS_MISC = 0x28

# struct input_event sur 64 bits : timeval (2 x long), type, code, value
EVENT_FORMAT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)


def _ioc_read(nr, size):
    """_IOC(_IOC_READ, 'E', nr, size)"""
    return (2 << 30) | (size << 16) | (ord("E") << 8) | nr


def EVIOCGNAME(length):
    return _ioc_read(0x06, length)


EVIOCGID = _ioc_read(0x02, 8)


def EVIOCGBIT(ev, length):
    return _ioc_read(0x20 + ev, length)


def EVIOCGABS(axis):
    return _ioc_read(0x40 + axis, 24)


# Commandes demandées, dans l'ordre (clé RetroArch, libellé) ###############

CONTROLS = [
    ("up", "HAUT"),
    ("down", "BAS"),
    ("left", "GAUCHE"),
    ("right", "DROITE"),
    ("a", "A (NES/Game Boy : A ; RetroPad : bouton de droite)"),
    ("b", "B (NES/Game Boy : B ; RetroPad : bouton du bas)"),
    ("x", "X (RetroPad : bouton du haut)"),
    ("y", "Y (RetroPad : bouton de gauche)"),
    ("l", "L (gâchette gauche)"),
    ("r", "R (gâchette droite)"),
    ("l2", "L2"),
    ("r2", "R2"),
    ("select", "SELECT / COIN (pièce)"),
    ("start", "START"),
]


# Lecture du périphérique #################################################

def test_bit(bits, i):
    return bool(bits[i // 8] & (1 << (i % 8)))


class Device:
    def __init__(self, path):
        self.path = path
        self.fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)

        buf = fcntl.ioctl(self.fd, EVIOCGNAME(256), bytes(256))
        self.name = buf.split(b"\0", 1)[0].decode(errors="replace")
        _bustype, self.vendor, self.product, _version = struct.unpack(
            "HHHH", fcntl.ioctl(self.fd, EVIOCGID, bytes(8)))

        keybits = fcntl.ioctl(self.fd, EVIOCGBIT(EV_KEY, KEY_MAX // 8 + 1), bytes(KEY_MAX // 8 + 1))
        absbits = fcntl.ioctl(self.fd, EVIOCGBIT(EV_ABS, 8), bytes(8))

        # Boutons : même ordre que udev_joypad.c de RetroArch
        # (BTN_JOYSTICK..KEY_MAX, puis BTN_MISC..BTN_JOYSTICK)
        self.buttons = {}
        for code in list(range(BTN_JOYSTICK, KEY_MAX)) + list(range(BTN_MISC, BTN_JOYSTICK)):
            if test_bit(keybits, code):
                self.buttons[code] = len(self.buttons)

        # Axes : numérotés dans l'ordre des codes, sans les "hats" (croix numérique)
        self.axes = {}
        self.absinfo = {}
        self.hats = set()
        for code in range(ABS_MISC):
            if not test_bit(absbits, code):
                continue
            _value, minimum, maximum, _fuzz, _flat, _res = struct.unpack(
                "iiiiii", fcntl.ioctl(self.fd, EVIOCGABS(code), bytes(24)))
            if ABS_HAT0X <= code <= ABS_HAT3Y:
                self.hats.add(code)
            elif maximum > minimum:
                self.axes[code] = len(self.axes)
                self.absinfo[code] = (minimum, maximum)

        # Dernière position connue de chaque axe, mise à jour par les évènements
        # (l'état lu par ioctl avant le premier évènement n'est pas fiable)
        self.positions = {code: 0 for code in self.axes}

    def is_joystick(self):
        """Boutons de joystick/manette (BTN_JOYSTICK..BTN_DIGI ou BTN_TRIGGER_HAPPY) : exclut souris et écrans tactiles."""
        return any(BTN_JOYSTICK <= code < BTN_DIGI or code >= BTN_TRIGGER_HAPPY for code in self.buttons)

    def read_events(self):
        events = []
        while True:
            try:
                data = os.read(self.fd, EVENT_SIZE * 64)
            except BlockingIOError:
                break
            if not data:
                break
            for i in range(0, len(data) - EVENT_SIZE + 1, EVENT_SIZE):
                _s, _us, ev_type, code, value = struct.unpack(EVENT_FORMAT, data[i:i + EVENT_SIZE])
                events.append((ev_type, code, value))
        return events

    def axis_position(self, code, value):
        """-1, 0 ou +1 selon la position de l'axe (seuil à mi-course)."""
        minimum, maximum = self.absinfo[code]
        center = (minimum + maximum) / 2
        half = (maximum - minimum) / 2
        if value > center + half / 2:
            return 1
        if value < center - half / 2:
            return -1
        return 0

    def binding(self, ev_type, code, value):
        """Traduit un évènement en (type, valeur RetroArch) s'il correspond à un appui, sinon None.
        Un relâchement renvoie ("release", None)."""
        if ev_type == EV_KEY and code in self.buttons:
            if value == 1:
                return ("btn", str(self.buttons[code]))
            if value == 0:
                return ("release", None)
        if ev_type == EV_ABS and code in self.axes:
            previous = self.positions[code]
            position = self.axis_position(code, value)
            self.positions[code] = position
            if position != previous:
                if position == 0:
                    return ("release", None)
                return ("axis", ("+" if position > 0 else "-") + str(self.axes[code]))
        if ev_type == EV_ABS and code in self.hats:
            if value == 0:
                return ("release", None)
            hat = (code - ABS_HAT0X) // 2
            if (code - ABS_HAT0X) % 2 == 0:
                direction = "right" if value > 0 else "left"
            else:
                direction = "down" if value > 0 else "up"
            return ("btn", "h%d%s" % (hat, direction))
        return None


def find_joysticks():
    """Renvoie (manettes trouvées, nombre de périphériques non lisibles)."""
    devices = []
    denied = 0
    for path in sorted(glob.glob("/dev/input/event*"), key=lambda p: int(p[len("/dev/input/event"):])):
        try:
            device = Device(path)
        except PermissionError:
            denied += 1
            continue
        except OSError:
            continue
        if device.is_joystick():
            devices.append(device)
        else:
            os.close(device.fd)
    return devices, denied


def describe(device):
    return "%s  \"%s\"  (vendor %04x, product %04x, %d boutons, %d axes, %d hats)" % (
        device.path, device.name, device.vendor, device.product,
        len(device.buttons), len(device.axes), len(device.hats) // 2)


# Capture interactive #####################################################

def drain(device, duration, verbose):
    """Ignore les évènements pendant 'duration' secondes (rebonds, retour au centre)."""
    end = time.monotonic() + duration
    while True:
        remaining = end - time.monotonic()
        if remaining <= 0:
            break
        select.select([device.fd], [], [], remaining)
        for event in device.read_events():
            device.binding(*event)
            if verbose:
                print("    [ignoré] type=%d code=0x%03x valeur=%d" % event)


def wait_for_release(device, verbose, timeout=5.0):
    """Attend le relâchement de la commande capturée (au plus 'timeout' secondes)."""
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        select.select([device.fd], [], [], 0.05)
        for event in device.read_events():
            if verbose:
                print("    [relâchement ?] type=%d code=0x%03x valeur=%d" % event)
            found = device.binding(*event)
            if found and found[0] == "release":
                return


def capture(device, verbose):
    bindings = []
    print()
    print("Appuyez sur la commande demandée. Entrée pour l'ignorer si elle n'existe pas.")
    drain(device, 0.2, verbose)
    for key, label in CONTROLS:
        # oublie les appuis sur Entrée faits en avance
        termios.tcflush(sys.stdin, termios.TCIFLUSH)
        print("  %-55s" % label, end="", flush=True)
        result = None
        while result is None:
            ready, _, _ = select.select([device.fd, sys.stdin], [], [])
            if sys.stdin in ready:
                sys.stdin.readline()
                result = "ignoré"
                break
            for event in device.read_events():
                if verbose:
                    print("\n    [évènement] type=%d code=0x%03x valeur=%d" % event, end="")
                found = device.binding(*event)
                if found and found[0] != "release":
                    kind, value_str = found
                    bindings.append((key, kind, value_str))
                    result = "%s %s" % ("bouton" if kind == "btn" else "axe", value_str)
                    break
        if verbose and result != "ignoré":
            print()
        print(result)
        if result != "ignoré":
            wait_for_release(device, verbose)
            drain(device, 0.2, verbose)
    return bindings


def write_cfg(device, bindings, output):
    lines = [
        'input_device = "%s"' % device.name,
        'input_driver = "udev"',
        'input_vendor_id = "%d"' % device.vendor,
        'input_product_id = "%d"' % device.product,
        "",
    ]
    for key, kind, value in bindings:
        lines.append('input_%s_%s = "%s"' % (key, kind, value))
    with open(output, "w") as cfg:
        cfg.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description="Crée un fichier autoconfig RetroArch pour une manette branchée sur ce PC.")
    parser.add_argument("-o", "--output", help="fichier .cfg à écrire")
    parser.add_argument("-d", "--device", help="périphérique /dev/input/eventN (sinon choix dans la liste)")
    parser.add_argument("-l", "--list", action="store_true", help="liste les manettes branchées et quitte")
    parser.add_argument("-v", "--verbose", action="store_true", help="affiche les évènements bruts (diagnostic)")
    args = parser.parse_args()

    if args.device:
        device = Device(args.device)
    else:
        devices, denied = find_joysticks()
        if not devices:
            sys.exit("Aucune manette trouvée. Branchez-la%s." % (
                ", ou relancez avec sudo (%d périphériques non lisibles)" % denied if denied else ""))
        if args.list:
            for device in devices:
                print(describe(device))
            return
        if len(devices) == 1:
            device = devices[0]
        else:
            for i, dev in enumerate(devices):
                print("%d) %s" % (i + 1, describe(dev)))
            choice = input("Numéro de la manette : ")
            device = devices[int(choice) - 1]

    if not args.output:
        sys.exit("Préciser le fichier à écrire avec -o")

    print("Manette : " + describe(device))
    bindings = capture(device, args.verbose)
    write_cfg(device, bindings, args.output)
    print()
    print("Fichier écrit : %s" % args.output)


if __name__ == "__main__":
    main()
