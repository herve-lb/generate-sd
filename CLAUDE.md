# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repo builds Raspberry Pi SD card images for MO5.com retro-gaming exhibition cabinets ("bornes"). Each image starts from a stock RetroPie image. It is then changed to boot silently, straight into a single game (or into a USB-key launcher). There is no build system, no linter and no test suite: the project is a set of Bash scripts plus a small Python launcher. Comments, log messages and user-facing strings are mostly in French. Keep that convention when editing existing scripts.

## Generating an image

The main tool is `source/generate-image/generate-generic-image.sh`. It is Linux-only and needs `losetup` and `sudo`. Per-game wrapper scripts live in `work/target/` and must be run **from that directory**, because they use relative paths (`../../source/...`, `../origin/...`):

```
cd work/target
./generate-pacman-0.78-lf-mame2003.sh
```

Direct usage:

```
# generic image (game supplied later on a USB key)
generate-generic-image.sh -g -i ../origin/origin.img -o generic.img

# specific image (one game baked in)
generate-generic-image.sh -i ../origin/origin.img -o out.img \
  -s ../origin/game-to-install/<core>/<rom> \
  [-e <emulator, e.g. lr-mame2003>] [-c <joypad .cfg>] [-S <samples dir>] [-l horizontal|vertical] [-n] [-r <percent>:<width>x<height>[:<alignment>] | -b left=N,right=N,top=N,bottom=N] [-m monitor_800x600_60hz|… | -t pal|ntsc] [-R 90|180|270] [-a jack|hdmi]
```

- `-g` (generic) and `-s` (specific) are mutually exclusive. One of them is required.
- **The core/system is inferred from the ROM's parent directory name.** For example, `game-to-install/snes/Pocky-Rocky.smc` installs into `roms/snes/`. So the directories under `work/origin/game-to-install/` must match RetroPie roms directory names (`arcade`, `nes`, `snes`, `pcengine`, …).
- The script pauses (`read -p`) before unmounting, so you can inspect the mounted image in `work_temp/`. It also pauses if the core is unknown. Without `--batch` it is interactive and is not meant to run unattended.
- The working copy goes to `$HOME/out.img`, is loop-mounted (p2 → `work_temp/`, p1 → `work_temp/boot`), and is then copied to the `-o` path. An `EXIT` trap set in `mount_image` unmounts and frees the loop device on errors and Ctrl-C (`umount_image` is idempotent). If mounts or loop devices are still left behind (failed unmount, killed process), `work/target/clean.sh` unmounts `work/target/work_temp{/boot,}`, detaches the loop devices bound to `$HOME/out.img` and removes `work_temp/` (see README §1.6). The log file is written next to the script (`generate-generic-image.log`).
- Writing an image to a card: `sudo dd bs=4M if=game.img of=/dev/sdX` (see README.md).

`work/origin/` holds the source RetroPie image (`origin.img`), ROMs, samples and joypad `.cfg` files. Large `*.img` files are gitignored.

## How the image is modified

`apply_common_modifications_on_SD` makes `sed` edits to `boot/cmdline.txt`, `boot/config.txt`, `runcommand.cfg`, the `retroarch.cfg` files, the splash screen, motd/issue and `rc.local`. It also enables SSH. The generator knows no cabinet: display and sound settings are generic options. **Every option is declared once in the `OPTIONS` table** (`short|long|variable|type|values|label|category|title|description`; `values` lists a choice's values or a file's allowed extensions), with `CONFLICTS` and `CATEGORIES`: getopts, long names (`--name value` or `--name=value`), help, choice-value checks and `--describe` (JSON for the configuration editor) are all derived from it. To add an option, add a line there, then its specific checks in `check_parameters` and its effect in an `apply_*` function. Short and long names and values are English (`-s/--specific`, `-R/--rotate`, `--audio jack`).

Generation runs `apply_base_modifications` (one-time: silent/fast boot, services, console) then the settings functions `apply_display_settings`, `apply_sound_settings`, `apply_controller_settings`, which are idempotent so that `--modify <image.img|/dev/sdX>` can re-run them on a generated image or SD card (it replaces all display/sound settings; unspecified ones go back to default). The options used are recorded in `/boot/mo5-options.conf` (`long_name=value`), which `--modify` updates and the editor reads. `--batch` removes the interactive pauses. Each wrapper in `work/target/` is self-contained: all options, one per line in long form, in the style of `generate-zelda-links-awakening-dx-gbc.sh`; README §1.7 lists the options used per cabinet.

The boot-time launcher is installed as `/opt/retropie/configs/all/autostart.sh`:
- **Specific mode** copies `source/launch-game/10-retropie.sh.specific`, then fills in its `CORE_NAME`, `GAME_NAME` and `EMULATOR_NAME` placeholders with `sed`. At boot it runs `runcommand.sh` for the game. If `-e` was given, it uses that emulator's command line from `configs/<core>/emulators.cfg` instead.
- **Generic mode** copies `10-retropie.sh.generic`. At boot it runs `/media/usb0/bin/launch-game.py` from a USB key if present, and otherwise falls back to EmulationStation.

## USB-key launcher (`source/launch-game/`)

This is a Python 3 program that runs on the Pi from the USB key's `bin/`. The key's layout is `bin/` plus `roms/<SYSTEM>/<game + controller .cfg>`.

- `ConsoleFinder` reads `es_systems.cfg` to validate the single system directory on the key and to get its extensions and launch command.
- `Console` locates the game, the controller and the BIOS, and has subclasses for systems that need a BIOS (`PCEngine`, `Playstation`).
- `Controllers` copies joypad configs to the SD card and checks that the plugged controllers are configured.

`globals.py` switches paths depending on whether the hostname contains `retropie`. Off-Pi, it uses `/Volumes/ROMS/...-tests` dirs for testing on macOS. `USB_Key_Sample/bin/` is a copy of these files that has diverged from them, so check both if you change the launcher.

## Configuration editor (`source/config-editor/mo5-config-editor.py`)

Python 3 + PySide6 (Qt) GUI (Ubuntu desktop, `python3-pyside6.qtwidgets`), README §1.11. `mo5_core.py` holds the logic without UI (testable without Qt); `mo5-config-editor.py` is the UI. It hard-codes no generator option: forms are built from `generate-generic-image.sh --describe` (field title from the `title` column, help from `description`). It loads/saves `work/target` scripts (shlex parsing of the generator call), runs generations and `--modify` through `sudo -S ... --batch` with cwd `work/target`, and reads `/boot/mo5-options.conf` (and `config.txt` as a fallback) from an image without mounting (its own FAT reader with long-name support) or from an SD card's boot partition (desktop mountpoint or `udisksctl mount`). Planned v3: discover a USB controller plugged into the PC and generate its RetroArch `.cfg`, replacing `source/controller-config/create-controller-cfg.py`.

## Other directories

- `source/controller-config/create-controller-cfg.py` creates joypad `.cfg` files (see README §1.9).
