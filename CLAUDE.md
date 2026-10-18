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
generate-generic-image.sh -d -g -i ../origin/origin.img -o generic.img

# specific image (one game baked in)
generate-generic-image.sh -d -i ../origin/origin.img -o out.img \
  -s ../origin/game-to-install/<core>/<rom> \
  [-e <emulator, e.g. lr-mame2003>] [-c <joypad .cfg>] [-p <samples dir>] [-x <cabinet profile>] [-l scanlines_horizontal|scanlines_vertical] [-n] [-r <percent>:<width>x<height>[:<alignment>]]
```

- `-g` (generic) and `-s` (specific) are mutually exclusive. One of them is required.
- **The core/system is inferred from the ROM's parent directory name.** For example, `game-to-install/snes/Pocky-Rocky.smc` installs into `roms/snes/`. So the directories under `work/origin/game-to-install/` must match RetroPie roms directory names (`arcade`, `nes`, `snes`, `pcengine`, …).
- The script pauses (`read -p`) before unmounting, so you can inspect the mounted image in `work_temp/`. It also pauses if the core is unknown. It is interactive and is not meant to run unattended.
- The working copy goes to `$HOME/out.img`, is loop-mounted (p2 → `work_temp/`, p1 → `work_temp/boot`), and is then copied to the `-o` path. An `EXIT` trap set in `mount_image` unmounts and frees the loop device on errors and Ctrl-C (`umount_image` is idempotent). If mounts or loop devices are still left behind (failed unmount, killed process), `work/target/clean.sh` unmounts `work/target/work_temp{/boot,}`, detaches the loop devices bound to `$HOME/out.img` and removes `work_temp/` (see README §1.6). The log file is written next to the script (`generate-generic-image.log`).
- Writing an image to a card: `sudo dd bs=4M if=game.img of=/dev/sdX` (see README.md).

`work/origin/` holds the source RetroPie image (`origin.img`), ROMs, samples and joypad `.cfg` files. Large `*.img` files are gitignored.

## How the image is modified

`apply_common_modifications_on_SD` makes `sed` edits to `boot/cmdline.txt`, `boot/config.txt`, `runcommand.cfg`, the `retroarch.cfg` files, the splash screen, motd/issue and `rc.local`. It also enables SSH. **Cabinet-specific hardware tweaks are selected with `-x <profile>`** and implemented as `if [[ "${specific_console}" == ... ]]` blocks in that function. The existing profiles are `borne_arcade_1_up`, `borne_rene_pierre`, `borne_pacman_mo5` and `pacman_GameStoryVersailles`. They cover overscan, display rotation, HDMI/TV-out mode, audio over jack, and the custom RetroArch viewport. To add a new cabinet, add another profile block there. `-r` (shrink by a percentage, for a given screen resolution, optionally aligned with `haut`, `bas`, `gauche`, `droite` or a corner such as `bas-gauche`) is validated and converted into per-side pixel margins in `check_parameters`. The overscan lines are then rewritten in `config.txt` after the profile blocks, so `-r` overrides a profile's overscan.

The boot-time launcher is installed as `/opt/retropie/configs/all/autostart.sh`:
- **Specific mode** copies `source/launch-game/10-retropie.sh.specific`, then fills in its `CORE_NAME`, `GAME_NAME` and `EMULATOR_NAME` placeholders with `sed`. At boot it runs `runcommand.sh` for the game. If `-e` was given, it uses that emulator's command line from `configs/<core>/emulators.cfg` instead.
- **Generic mode** copies `10-retropie.sh.generic`. At boot it runs `/media/usb0/bin/launch-game.py` from a USB key if present, and otherwise falls back to EmulationStation.

## USB-key launcher (`source/launch-game/`)

This is a Python 3 program that runs on the Pi from the USB key's `bin/`. The key's layout is `bin/` plus `roms/<SYSTEM>/<game + controller .cfg>`.

- `ConsoleFinder` reads `es_systems.cfg` to validate the single system directory on the key and to get its extensions and launch command.
- `Console` locates the game, the controller and the BIOS, and has subclasses for systems that need a BIOS (`PCEngine`, `Playstation`).
- `Controllers` copies joypad configs to the SD card and checks that the plugged controllers are configured.

`globals.py` switches paths depending on whether the hostname contains `retropie`. Off-Pi, it uses `/Volumes/ROMS/...-tests` dirs for testing on macOS. `USB_Key_Sample/bin/` is a copy of these files that has diverged from them, so check both if you change the launcher.

## Other directories

- `source/controller-config/create-controller-cfg.py` creates joypad `.cfg` files (see README §1.9).
