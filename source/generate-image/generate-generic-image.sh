#!/bin/bash

##########################################################################
#
# This script creates GENERIC retropie images starting from a brand new retropie image.
#
# Requirements :
# - Linux OS
# - losetup
# - original retropie image file

# Constants ############################################################

WORKING_DIRECTORY="work_temp"
BOOT_DIRECTORY="${WORKING_DIRECTORY}/boot"
ROMS_DIRECTORY="${WORKING_DIRECTORY}/home/pi/RetroPie/roms"
AUTOLAUNCH_SCRIPT_FILENAME="autostart.sh"
AUTOLAUNCH_DIRECTORY="${WORKING_DIRECTORY}/opt/retropie/configs/all"
AUTOLAUNCH_SCRIPT_FILENAME_GenericLaunch="10-retropie.sh.generic"
AUTOLAUNCH_SCRIPT_FILENAME_SpecificLaunch="10-retropie.sh.specific"
JOYPAD_CONFIGURATION_DIRECTORY="${WORKING_DIRECTORY}/opt/retropie/configs/all/retroarch/autoconfig"
SHADERS_DIRECTORY="/opt/retropie/configs/all/retroarch/shaders"
TEMP_IMAGE="${HOME}/out.img"

# globals ################################################################

logFileName=
translated_options=()
specific=
generic=

loop=

original_retropie_image=
result_image="out.img"
samples_dir=
controller_file=
gamefile=
emulatorname=
scanlines=
nosmooth=
shader_file=
shrink=
borders=
audio_output=
tv_output=
hdmi_format=
rotation=
sdtv_mode=
hdmi_group=
hdmi_mode=
display_rotate=
overscan_left=
overscan_right=
overscan_top=
overscan_bottom=

# OS pre-requisite #######################################################

function install_prerequisites() {

  # check losetup installation
  if ! command -v losetup > /dev/null; then
    exitonerror "logiciel losetup manquant. Impossible de charger l'image de Retropie"
  fi
}

function check_parameters() {

  # check if the user selects Generic or Specific Mode
  if [[ -z "${specific}" && -z "${generic}" ]]; then
    usage
    exitonerror "Pas de choix entre mode générique ou spécifique"
  fi

  # check if the user selects Generic or Specific Mode
  if ! [[ -z "${specific}" ]] && ! [[ -z "${generic}" ]]; then
    usage
    exitonerror "Il faut choisir entre mode générique ou spécifique"
  fi

  # check scanlines option and select the matching shader
  if ! [[ -z "${scanlines}" ]]; then
    case "${scanlines}" in
      horizontal) shader_file="crt-pi.glslp" ;;
      vertical) shader_file="crt-pi-vertical.glslp" ;;
      *)
        usage
        exitonerror "Option -l (--scanlines) inconnue : ${scanlines} (valeurs possibles : horizontal, vertical)"
        ;;
    esac
  fi

  # check shrink option (percent:WIDTHxHEIGHT[:alignment]) and compute the overscan margins in pixels
  if ! [[ -z "${shrink}" ]]; then
    if ! [[ "${shrink}" =~ ^([0-9]+)(\.[0-9]+)?:([0-9]+)x([0-9]+)(:(top|bottom|left|right|top-left|top-right|bottom-left|bottom-right))?$ ]] || (( 10#${BASH_REMATCH[1]} >= 50 )); then
      usage
      exitonerror "Option -r (--reduce) invalide : ${shrink} (format attendu : pourcentage:largeurxhauteur[:alignement], par exemple 5:1024x768 ou 5:1024x768:bottom, avec un pourcentage inférieur à 50 et un alignement parmi top, bottom, left, right, top-left, top-right, bottom-left, bottom-right)"
    fi
    local shrink_percent="${shrink%%:*}"
    local shrink_alignment="${BASH_REMATCH[6]}"
    local overscan_horizontal=$(awk -v p="${shrink_percent}" -v w="${BASH_REMATCH[3]}" 'BEGIN { printf "%d", w * p / 200 + 0.5 }')
    local overscan_vertical=$(awk -v p="${shrink_percent}" -v h="${BASH_REMATCH[4]}" 'BEGIN { printf "%d", h * p / 200 + 0.5 }')

    # centered by default, the whole margin goes to the opposite side of the alignment
    overscan_left=${overscan_horizontal}
    overscan_right=${overscan_horizontal}
    overscan_top=${overscan_vertical}
    overscan_bottom=${overscan_vertical}
    case "${shrink_alignment}" in
      top*) overscan_top=0 ; overscan_bottom=$((overscan_vertical * 2)) ;;
      bottom*) overscan_top=$((overscan_vertical * 2)) ; overscan_bottom=0 ;;
    esac
    case "${shrink_alignment}" in
      *left) overscan_left=0 ; overscan_right=$((overscan_horizontal * 2)) ;;
      *right) overscan_left=$((overscan_horizontal * 2)) ; overscan_right=0 ;;
    esac
    trace "Shrink ${shrink} : overscan gauche ${overscan_left} px, droite ${overscan_right} px, haut ${overscan_top} px, bas ${overscan_bottom} px"
  fi

  # check border option (left=N,right=N,top=N,bottom=N in pixels, missing sides are 0)
  if ! [[ -z "${borders}" ]]; then
    if ! [[ -z "${shrink}" ]]; then
      usage
      exitonerror "Les options -r (--reduce) et -b (--border) règlent toutes les deux l'overscan : il faut choisir l'une ou l'autre"
    fi
    overscan_left=0
    overscan_right=0
    overscan_top=0
    overscan_bottom=0
    local border
    for border in ${borders//,/ }; do
      if ! [[ "${border}" =~ ^(left|right|top|bottom)=([0-9]+)$ ]]; then
        usage
        exitonerror "Option -b (--border) invalide : ${border} (format attendu : left=N,right=N,top=N,bottom=N en pixels, par exemple left=20,right=20)"
      fi
      case "${BASH_REMATCH[1]}" in
        left) overscan_left=$((10#${BASH_REMATCH[2]})) ;;
        right) overscan_right=$((10#${BASH_REMATCH[2]})) ;;
        top) overscan_top=$((10#${BASH_REMATCH[2]})) ;;
        bottom) overscan_bottom=$((10#${BASH_REMATCH[2]})) ;;
      esac
    done
    trace "Bordures ${borders} : overscan gauche ${overscan_left} px, droite ${overscan_right} px, haut ${overscan_top} px, bas ${overscan_bottom} px"
  fi

  # check audio option
  if ! [[ -z "${audio_output}" ]]; then
    case "${audio_output}" in
      jack|hdmi) ;;
      *)
        usage
        exitonerror "Option -a (--audio) inconnue : ${audio_output} (valeurs possibles : jack, hdmi)"
        ;;
    esac
  fi

  # check composite output option
  if ! [[ -z "${tv_output}" ]]; then
    case "${tv_output}" in
      pal) sdtv_mode=2 ;;
      ntsc) sdtv_mode=0 ;;
      *)
        usage
        exitonerror "Option -t (--tv-out) inconnue : ${tv_output} (valeurs possibles : pal, ntsc)"
        ;;
    esac
    if ! [[ -z "${hdmi_format}" ]]; then
      usage
      exitonerror "Les options -t (--tv-out, sortie composite) et -m (--hdmi-mode) ne se combinent pas : la borne utilise l'une ou l'autre sortie"
    fi
  fi

  # check HDMI mode option: group 1 = CEA (TV modes), group 2 = DMT (computer monitor modes)
  if ! [[ -z "${hdmi_format}" ]]; then
    case "${hdmi_format}" in
      monitor_640x480_60hz) hdmi_group=2 ; hdmi_mode=4 ;;
      monitor_800x600_60hz) hdmi_group=2 ; hdmi_mode=9 ;;
      monitor_1024x768_60hz) hdmi_group=2 ; hdmi_mode=16 ;;
      monitor_1280x1024_60hz) hdmi_group=2 ; hdmi_mode=35 ;;
      tv_720p_60hz) hdmi_group=1 ; hdmi_mode=4 ;;
      tv_1080p_60hz) hdmi_group=1 ; hdmi_mode=16 ;;
      *)
        usage
        exitonerror "Option -m (--hdmi-mode) inconnue : ${hdmi_format} (valeurs possibles : monitor_640x480_60hz, monitor_800x600_60hz, monitor_1024x768_60hz, monitor_1280x1024_60hz, tv_720p_60hz, tv_1080p_60hz)"
        ;;
    esac
  fi

  # check rotation option (clockwise)
  if ! [[ -z "${rotation}" ]]; then
    case "${rotation}" in
      90) display_rotate=1 ;;
      180) display_rotate=2 ;;
      270) display_rotate=3 ;;
      *)
        usage
        exitonerror "Option -R (--rotate) inconnue : ${rotation} (valeurs possibles : 90, 180, 270)"
        ;;
    esac
  fi

  # check if the user specify a good filename for the game
  if ! [[ -z "${specific}" ]]; then

    # No filename
    if [[ -z "${gamefile}" ]]; then
      usage
      exitonerror "Il faut préciser un nom de fichier pour le jeu à installer"
    fi

    # bad file
    if ! [[ -f "${gamefile}" ]]; then
      usage
      exitonerror "Il faut préciser un nom de fichier valide pour le jeu à installer"
    fi

    # if samples is provided then check samples directory existence
    if [[ ! -z "${samples_dir}" ]] && [[ ! -d "${samples_dir}" ]]; then
      usage
      exitonerror "Il faut préciser un répertoire de Samples valide pour accompagner le jeu à installer"
    fi

    # if controller filename is provided then check file exists
    if [[ ! -z "${controller_file}" ]] && [[ ! -f "${controller_file}" ]]; then
      usage
      exitonerror "Il faut préciser un nom de fichier valide pour la configuration du joystick"
    fi
  fi
}

# Error Management #######################################################

function init_log_file() {

    # if filename is empty, get the filename for logs from the script filename
    if [[ -z "${logFileName}" ]]; then
      logFileName="${BASH_SOURCE[0]}"
      logFileName="${logFileName%.*}.log"

      # Remove previous log file if any
      rm -f "${logFileName}"
    fi
}

function log_message() {
  local message="[$(date -u)][$1] $2"

  # display to console
  echo "${message}"

  #init log file if needed
  init_log_file

  #add to log file
  echo "${message}" >> "${logFileName}"
}

function trace() {
  log_message DEBUG "$1"
}

function warning() {
  log_message WARN "$1"
}

# the image is freed by the EXIT trap set in mount_image
function exitonerror() {
  log_message ERROR "$1"
  exit 1
}

# Image file Management #######################################################

function prepare_image() {
  trace "##########################"
  trace "prepare_image ############"

  if [[ -z "${original_retropie_image}" ]]; then
    exitonerror "Pas d'image Retropie en entrée"
  fi
  if ! [[ -f "${original_retropie_image}" ]]; then
    exitonerror "Le fichier image Retropie d'entrée est introuvable"
  fi

  if [[ -z "${result_image}" ]]; then
    exitonerror "Pas d'image de destination"
  fi

  # Delete old result if any
  if [[ -f "${result_image}" ]]; then
    trace "Suppression de l'ancienne image résultat ${result_image}"
    rm "${result_image}"
  fi

  # Delete old working image if any
  if [[ -f "${TEMP_IMAGE}" ]]; then
    trace "Suppression de l'ancienne image de travail ${TEMP_IMAGE}"
    rm "${TEMP_IMAGE}"
  fi

  # temporary duplicate to local directory (useful if executing the script inside a VM)
  trace "Copie de ${original_retropie_image} vers ${TEMP_IMAGE}"
  cp "${original_retropie_image}" "${TEMP_IMAGE}"

  # check if result file is present
  if ! [[ -f "${TEMP_IMAGE}" ]]; then
     exitonerror "Impossible de créer le fichier ${TEMP_IMAGE}"
  fi

  # End successfully
  trace "L'image de travail ${TEMP_IMAGE} a été correctement générée"
}

function prepare_result() {
  trace "##########################"
  trace "prepare_result ###########"

  # check if result file is present
  if ! [[ -f "${TEMP_IMAGE}" ]]; then
     exitonerror "L'image de travail ${TEMP_IMAGE} n'existe pas"
  fi

  # copy the result to the given destination
  trace "Copie de ${TEMP_IMAGE} vers ${result_image}"
  cp "${TEMP_IMAGE}" "${result_image}"
}

function mount_image() {
  trace "##########################"
  trace "mount_image ##############"

  # Associate image to the first available device, in one step to avoid a race on the device
  loop=$(sudo losetup -f --show -P "${TEMP_IMAGE}")
  if [[ -z "${loop}" ]]; then
    exitonerror "Impossible d'associer l'image ${TEMP_IMAGE} à un pseudo périphérique (losetup -f error)"
  fi
  trace "Association de ${loop} avec l'image ${TEMP_IMAGE}"

  # from now on, always free the image on exit (error, Ctrl-C or normal end)
  trap umount_image EXIT
  trap 'exit 1' INT TERM

  # Create temporary directory
  trace "Création du répertoire de travail ${WORKING_DIRECTORY}"
  mkdir "${WORKING_DIRECTORY}"
  if [ $? -ne 0 ]; then
    exitonerror "Impossible de créer le répertoire de travail sur le disque"
  fi

  # Mount the image and map on the working directory
  trace "Montage de ${loop}p2 sur ${WORKING_DIRECTORY}"
  sudo mount "${loop}p2" "${WORKING_DIRECTORY}"
  if [ $? -ne 0 ]; then
    exitonerror "Impossible de monter ${loop}p2 sur ${WORKING_DIRECTORY}"
  fi
  trace "Montage de ${loop}p1 sur ${WORKING_DIRECTORY}/boot"
  sudo mount "${loop}p1" "${WORKING_DIRECTORY}/boot"
  if [ $? -ne 0 ]; then
    exitonerror "Impossible de monter ${loop}p1 sur ${WORKING_DIRECTORY}/boot"
  fi
}

function umount_image() {
  # nothing to free (never mounted, or already freed)
  if [[ -z "${loop}" ]]; then
    return
  fi

  trace "##########################"
  trace "umount_image #############"

  if mountpoint -q "${BOOT_DIRECTORY}"; then
    trace "Démontage de ${loop}p1"
    sudo umount "${BOOT_DIRECTORY}"
  fi
  if mountpoint -q "${WORKING_DIRECTORY}"; then
    trace "Démontage de ${loop}p2"
    sudo umount "${WORKING_DIRECTORY}"
  fi

  # never delete the working directory while the image is still mounted on it
  if mountpoint -q "${BOOT_DIRECTORY}" || mountpoint -q "${WORKING_DIRECTORY}"; then
    warning "Image encore montée sur ${WORKING_DIRECTORY} : répertoire conservé, lancer work/target/clean.sh"
  else
    trace "Suppression du répertoire de travail ${WORKING_DIRECTORY}"
    rm -rf "${WORKING_DIRECTORY}"
  fi

  trace "Désassociation du périphérique ${loop} et de l'image ${TEMP_IMAGE}"
  sudo losetup -d "${loop}"
  loop=
}

# SD Creation Management ######################################################

# remove a setting (commented or not) from a file, then append the given line at the end
function replace_setting() {
  local filename="$1"
  local key="$2"
  local line="$3"

  trace "set '${line}' in file ${filename}"
  sudo sed -i -E '/^#* *'"${key}"' *=/d' "${filename}"
  sudo sed -i '$a'"${line}" "${filename}"
}

# copy the boot-time launcher, owned like its directory (pi) instead of root
function install_autolaunch_script() {
  local filename="$(dirname "${BASH_SOURCE[0]}")/../launch-game/$1"
  local autolaunch_user_group="$(stat -c "%U:%G" "${AUTOLAUNCH_DIRECTORY}")"

  trace "## Autolaunch script"
  trace "Copy autolaunch script from ${filename} to ${AUTOLAUNCH_DIRECTORY}/${AUTOLAUNCH_SCRIPT_FILENAME}"
  sudo cp "${filename}" "${AUTOLAUNCH_DIRECTORY}/${AUTOLAUNCH_SCRIPT_FILENAME}"
  trace "chown ${autolaunch_user_group} ${AUTOLAUNCH_DIRECTORY}/${AUTOLAUNCH_SCRIPT_FILENAME}"
  sudo chown "${autolaunch_user_group}" "${AUTOLAUNCH_DIRECTORY}/${AUTOLAUNCH_SCRIPT_FILENAME}"
}

function apply_common_modifications_on_SD () {
  trace "####################################"
  trace "apply_common_modifications_on_SD ###"

  #
  # boot/cmdline.txt
  #
  local filename="${BOOT_DIRECTORY}/cmdline.txt"
  trace "## Apply modifications to ${filename}"

  # replace "console=tty1" by "console=tty3 quiet logo.nologo loglevel=3 vt.global_cursor_default=0 plymouth.enable=0"
  local pattern_to_remove="console=tty1"
  local pattern_to_add="console=tty3 quiet logo.nologo loglevel=3 vt.global_cursor_default=0 plymouth.enable=0"

  #command : sed '0,/tata/ s//zaza/' in.txt
  trace "replace ${pattern_to_remove} by ${pattern_to_add} in file ${filename}"
  sudo sed -i '0,/'"${pattern_to_remove}"'/ s//'"${pattern_to_add}"'/' "${filename}"

  #
  # boot/config.txt
  #
  filename="${BOOT_DIRECTORY}/config.txt"
  trace "## Apply modifications to ${filename}"

  # no black border, except on a composite output where the firmware default overscan suits CRT TVs
  if [[ -z "${tv_output}" ]]; then
    # uncomment "disable_overscan=1"
    trace "uncomment disable_overscan=1"
    sudo sed -i '0,/#disable_overscan/ s//disable_overscan/' "${filename}"
  fi

  #     Overscan margins computed from a percentage (option -r) or given in pixels (option -b)
  if ! [[ -z "${shrink}" ]] || ! [[ -z "${borders}" ]]; then
    trace "## Overscan ${shrink}${borders}"
    replace_setting "${filename}" disable_overscan "disable_overscan=0"
    replace_setting "${filename}" overscan_left "overscan_left=${overscan_left}"
    replace_setting "${filename}" overscan_right "overscan_right=${overscan_right}"
    replace_setting "${filename}" overscan_top "overscan_top=${overscan_top}"
    replace_setting "${filename}" overscan_bottom "overscan_bottom=${overscan_bottom}"
    # apply the overscan to the RetroArch layer too
    replace_setting "${filename}" overscan_scale "overscan_scale=1"
  fi

  # Disable large rainbow screen on initial boot
  trace "add disable_splash=1"
  sudo sed -i '$adisable_splash=1' "${filename}"

  # disable warnings such as undervoltage/overheating
  trace "add avoid_warnings=1"
  sudo sed -i '$aavoid_warnings=1' "${filename}"

  # no firmware delay before loading the kernel
  trace "add boot_delay=0"
  sudo sed -i '$aboot_delay=0' "${filename}"

  # no bluetooth on cabinets
  trace "add dtoverlay=disable-bt"
  sudo sed -i '$adtoverlay=disable-bt' "${filename}"

  #     Display rotation (option -R)
  if ! [[ -z "${display_rotate}" ]]; then
    trace "add display_rotate=${display_rotate} (${rotation}°)"
    sudo sed -i '$adisplay_rotate='"${display_rotate}" "${filename}"
  fi

  #     Forced HDMI mode (option -m)
  if ! [[ -z "${hdmi_format}" ]]; then
    trace "add hdmi_group=${hdmi_group} hdmi_mode=${hdmi_mode} (${hdmi_format})"
    sudo sed -i '$ahdmi_group='"${hdmi_group}" "${filename}"
    sudo sed -i '$ahdmi_mode='"${hdmi_mode}" "${filename}"
  fi

  #     Composite output, 4:3 (option -t)
  if ! [[ -z "${tv_output}" ]]; then
    trace "add enable_tvout=1"
    sudo sed -i '$aenable_tvout=1' "${filename}"
    trace "add sdtv_mode=${sdtv_mode} (${tv_output})"
    sudo sed -i '$asdtv_mode='"${sdtv_mode}" "${filename}"
    trace "add sdtv_aspect=1 for 4:3"
    sudo sed -i '$asdtv_aspect=1' "${filename}"
  fi

  #
  # retropie/opt/retropie/configs/all/runcommand.cfg
  #
  filename="${WORKING_DIRECTORY}/opt/retropie/configs/all/runcommand.cfg"
  trace "## Apply modifications to ${filename}"

  # add "disable_joystick=1"
  trace "replace disable_joystick=0 by disable_joystick=1 in file ${filename}"
  sudo sed -i '/disable_joystick/ s/"0"/"1"/g' "${filename}"

  # add "disable_menu=1"
  trace "replace disable_menu=0 by disable_menu=1 in file ${filename}"
  sudo sed -i '/disable_menu/ s/"0"/"1"/g' "${filename}"

  #
  # both retroarch.cfg files (RetroArch default and RetroPie): no on-screen messages
  #
  for filename in "${WORKING_DIRECTORY}/opt/retropie/emulators/retroarch/retroarch.cfg" "${WORKING_DIRECTORY}/opt/retropie/configs/all/retroarch.cfg"; do
    trace "## Apply modifications to ${filename}"
    replace_setting "${filename}" video_font_enable 'video_font_enable = "false"'
  done


  #
  # retropie/opt/retropie/configs/all/retroarch.cfg
  #
  filename="${WORKING_DIRECTORY}/opt/retropie/configs/all/retroarch.cfg"

  #     No smoothing for sharp pixels (option -n, or needed by scanlines). Otherwise RetroArch default (smoothing) is kept
  if ! [[ -z "${nosmooth}" ]] || ! [[ -z "${shader_file}" ]]; then
    replace_setting "${filename}" video_smooth 'video_smooth = "false"'
  fi

  #     Scanlines with a crt-pi shader
  if ! [[ -z "${shader_file}" ]]; then
    trace "## Scanlines ${scanlines} with shader ${SHADERS_DIRECTORY}/${shader_file}"
    if ! [[ -f "${WORKING_DIRECTORY}${SHADERS_DIRECTORY}/${shader_file}" ]]; then
      exitonerror "Shader introuvable dans l'image : ${SHADERS_DIRECTORY}/${shader_file}"
    fi

    replace_setting "${filename}" video_shader_enable 'video_shader_enable = "true"'
    replace_setting "${filename}" video_shader 'video_shader = "'"${SHADERS_DIRECTORY}/${shader_file}"'"'
  fi

  #
  # Splash screen management
  #
  filename="${WORKING_DIRECTORY}/etc/splashscreen.list"
  trace "## Splash Screen"
  trace "No Splash Screen. Empty ${filename}"
  sudo truncate -s 0 "${filename}"

  #
  # enable ssh by default
  #
  filename="${BOOT_DIRECTORY}/ssh"
  trace "## SSH enabling"
  trace "touch ${filename} to activate the SSH"
  sudo touch "${filename}"

  #
  # Audio setup
  #
  filename="${WORKING_DIRECTORY}/etc/asound.conf"

  #     Sound on the jack output instead of HDMI (option -a jack). hdmi keeps the default output
  if [[ "${audio_output}" == "jack" ]]; then
    trace "add 'pcm.!default {type hw card 1}' in file ${filename}"
    echo "pcm.!default {type hw card 1}" | sudo tee "${filename}"
    trace "add 'ctl.!default {type hw card 1}' in file ${filename}"
    echo "ctl.!default {type hw card 1}" | sudo tee --append "${filename}"
  fi

  #
  # No console output when launching games
  #
  trace "## Remove traces in console"
  trace "Empty ${WORKING_DIRECTORY}/etc/issue"
  sudo truncate -s 0 "${WORKING_DIRECTORY}/etc/issue"
  trace "Empty ${WORKING_DIRECTORY}/etc/motd"
  sudo truncate -s 0 "${WORKING_DIRECTORY}/etc/motd"
  filename="${WORKING_DIRECTORY}/home/pi/.bashrc"
  trace "Comment retropie_welcome line in ${filename}"
  sudo sed -i '/^retropie_welcome/ s/^#*/#/' "${filename}"
  filename="${WORKING_DIRECTORY}/etc/rc.local"
  trace "Add  sudo sh -c 'TERM=linux setterm -foreground black -clear all >/dev/tty0' in ${filename}"
  # i : add line before the line selected by search term
  sudo sed -i '/^exit 0/i\sudo sh -c "TERM=linux setterm -foreground black -clear all >\/dev\/tty0"' "${filename}"
  trace "Remove IP address display in ${filename}"
  sudo sed -i '/^_IP=\$(hostname -I)/,/^fi$/d' "${filename}"

  #
  # Faster boot
  #
  trace "## Faster boot"

  # do not wait for an IP address before rc.local and the autologin (up to 30s without network)
  filename="${WORKING_DIRECTORY}/etc/systemd/system/dhcpcd.service.d/wait.conf"
  trace "Remove ${filename}"
  sudo rm -f "${filename}"

  # disable useless services by removing their activation links (same as systemctl disable)
  local systemd_directory="${WORKING_DIRECTORY}/etc/systemd/system"
  local service_link
  for service_link in \
    multi-user.target.wants/hciuart.service \
    bluetooth.target.wants/bluetooth.service \
    dbus-org.bluez.service \
    multi-user.target.wants/smbd.service \
    multi-user.target.wants/nmbd.service \
    multi-user.target.wants/avahi-daemon.service \
    sockets.target.wants/avahi-daemon.socket \
    dbus-org.freedesktop.Avahi.service \
    multi-user.target.wants/dphys-swapfile.service \
    multi-user.target.wants/triggerhappy.service \
    sockets.target.wants/triggerhappy.socket \
    multi-user.target.wants/rsync.service \
    multi-user.target.wants/rpi-eeprom-update.service \
    multi-user.target.wants/nfs-client.target \
    remote-fs.target.wants/nfs-client.target \
    timers.target.wants/apt-daily.timer \
    timers.target.wants/apt-daily-upgrade.timer \
    timers.target.wants/man-db.timer
  do
    if [[ -L "${systemd_directory}/${service_link}" ]]; then
      trace "Disable ${service_link}"
      sudo rm "${systemd_directory}/${service_link}"
    else
      warning "Service déjà désactivé ou absent : ${service_link}"
    fi
  done
}

function create_Generic_SD () {
  trace "##########################"
  trace "create_Generic_SD ########"

  #
  # apply basics modifications
  #
  apply_common_modifications_on_SD

  install_autolaunch_script "${AUTOLAUNCH_SCRIPT_FILENAME_GenericLaunch}"
}

function create_Specific_SD () {
  trace "###########################"
  trace "create_Specific_SD ########"

  #
  # apply basics modifications
  #
  apply_common_modifications_on_SD

  # get user & group of roms directory in mounting situation
  local user_group="$(stat -c "%U:%G" "${ROMS_DIRECTORY}")"

  install_autolaunch_script "${AUTOLAUNCH_SCRIPT_FILENAME_SpecificLaunch}"

  #
  # game installation
  #
  trace "## Install game into Core directory"
  local gamename=$(basename -- "${gamefile}")
  local corename=$(basename -- "$(dirname -- "${gamefile}")")
  trace "Game to install is ${gamename} in core ${corename}"

  # check if roms directory exists in the SD
  trace "check if the core is known --> ${ROMS_DIRECTORY}/${corename}"
  if [[ -d "${ROMS_DIRECTORY}/${corename}" ]]; then
    trace "Copy gamefile ${gamename} to core ${corename}"
    sudo cp "${gamefile}" "${ROMS_DIRECTORY}/${corename}/"
    sudo chown "${user_group}" "${ROMS_DIRECTORY}/${corename}/${gamename}"
  else
    read -p "Le jeu est dans un répertoire core inconnu. Time to check " -n1 -s
    exitonerror "Le jeu est dans un répertoire core inconnu : ${corename}"
  fi

  # check the emulator so that runcommand never asks to choose one at boot
  filename="${WORKING_DIRECTORY}/opt/retropie/configs/${corename}/emulators.cfg"
  trace "check emulator in ${filename}"
  if ! [[ -f "${filename}" ]]; then
    exitonerror "Aucun émulateur installé pour ${corename} : ${filename} introuvable"
  fi
  if ! [[ -z "${emulatorname}" ]]; then
    if ! grep -q "^${emulatorname} *=" "${filename}"; then
      exitonerror "L'émulateur ${emulatorname} n'est pas installé pour ${corename} (voir ${filename})"
    fi
  else
    if ! grep -q "^default *= *\"..*\"" "${filename}"; then
      exitonerror "Pas d'émulateur par défaut pour ${corename} : un choix serait demandé au démarrage. Utiliser l'option -e (voir ${filename})"
    fi
    trace "default emulator : $(grep "^default *=" "${filename}")"
  fi

  # Samples installation
  if ! [[ -z "${samples_dir}" ]]; then

    trace "Copy Samples directory ${samples_dir} to ${ROMS_DIRECTORY}/${corename}/samples"
    sudo cp -r "${samples_dir}" "${ROMS_DIRECTORY}/${corename}/samples"
    sudo chown -R "${user_group}" "${ROMS_DIRECTORY}/${corename}/samples"

  fi

  # Controller file
  if [[ ! -z "${controller_file}" ]]; then

    local controller_filename=$(basename -- "${controller_file}")
    trace "Copy controller file ${controller_file} to ${JOYPAD_CONFIGURATION_DIRECTORY}/${controller_filename}"
    sudo cp "${controller_file}" "${JOYPAD_CONFIGURATION_DIRECTORY}/${controller_filename}"
    sudo chown "${user_group}" "${JOYPAD_CONFIGURATION_DIRECTORY}/${controller_filename}"
  fi

  #
  # core and game name replacement
  #
  trace "## Put Core and Game name into the launcher file"
  filename="${AUTOLAUNCH_DIRECTORY}/${AUTOLAUNCH_SCRIPT_FILENAME}"
  local placeholder value
  for placeholder in CORE_NAME GAME_NAME EMULATOR_NAME; do
    case "${placeholder}" in
      CORE_NAME) value="${corename}" ;;
      GAME_NAME) value="${gamename}" ;;
      EMULATOR_NAME) value="${emulatorname}" ;;
    esac
    trace "replace ${placeholder} by '${value}' in file ${filename}"
    # escape the characters that are special in a sed replacement (\ / &)
    value=$(printf '%s' "${value}" | sed 's/[\\/&]/\\&/g')
    sudo sed -i '0,/'"${placeholder}"'/ s//'"${value}"'/' "${filename}"
  done
}

# Parameters Management #################################################

function usage() {
  echo
  echo "USAGE:"
  echo "image générique : $(basename "$0") --generic --input <image> --output <image> (options d'affichage et de son)"
  echo "image spécifique : $(basename "$0") --specific <rom> --input <image> --output <image> (options du jeu) (options d'affichage et de son)"
  echo
  echo "Chaque option a une forme courte (-s rom) et une forme longue (--specific rom ou --specific=rom)."
  echo
  echo "  -g, --generic                     image générique (jeu sur clé USB)"
  echo "  -s, --specific <rom>              image spécifique : jeu à installer"
  echo "  -i, --input <image>               image RetroPie d'origine"
  echo "  -o, --output <image>              image à générer"
  echo "  -h, --help                        cette aide"
  echo
  echo "options du jeu :"
  echo "  -e, --emulator <émulateur>        émulateur forcé, par exemple lr-mame2003"
  echo "  -c, --controller <fichier.cfg>    configuration de manette à installer"
  echo "  -S, --samples <répertoire>        samples à installer à côté du jeu"
  echo
  echo "options d'affichage et de son :"
  echo "  -l, --scanlines horizontal|vertical"
  echo "  -n, --no-smoothing                pas de lissage de l'image"
  echo "  -r, --reduce <pourcentage>:<largeur>x<hauteur>[:<alignement>]"
  echo "                                    réduction de l'écran, alignement : top, bottom, left, right, top-left, top-right, bottom-left, bottom-right"
  echo "  -b, --border left=N,right=N,top=N,bottom=N"
  echo "                                    bordures noires en pixels (côtés absents : 0), ne se combine pas avec -r"
  echo "  -m, --hdmi-mode monitor_640x480_60hz|monitor_800x600_60hz|monitor_1024x768_60hz|monitor_1280x1024_60hz|tv_720p_60hz|tv_1080p_60hz"
  echo "                                    mode HDMI forcé"
  echo "  -t, --tv-out pal|ntsc             sortie composite 4:3, ne se combine pas avec -m"
  echo "  -R, --rotate 90|180|270           rotation de l'écran dans le sens horaire"
  echo "  -a, --audio jack|hdmi             sortie du son"
  echo
}

# long option names (without --) and their short equivalent
declare -A LONG_OPTIONS=(
  [generic]=g [specific]=s [input]=i [output]=o [help]=h
  [emulator]=e [controller]=c [samples]=S
  [scanlines]=l [no-smoothing]=n [reduce]=r [border]=b [hdmi-mode]=m [tv-out]=t [rotate]=R [audio]=a
)
# short options without value
FLAG_OPTIONS="ghn"

# "-s (--specific)" for error messages
function option_names() {
  local name
  for name in "${!LONG_OPTIONS[@]}"; do
    if [[ "${LONG_OPTIONS[${name}]}" == "$1" ]]; then
      echo "-$1 (--${name})"
      return
    fi
  done
  echo "-$1"
}

# translate the long options (--name value or --name=value) into the short ones read by getopts
function translate_long_options() {
  translated_options=()
  local arg name short
  while (( $# > 0 )); do
    arg="$1"
    shift
    case "${arg}" in
      --)
        translated_options+=("$@")
        break
        ;;
      --*)
        name="${arg%%=*}"
        name="${name#--}"
        short="${LONG_OPTIONS[${name}]}"
        if [[ -z "${short}" ]]; then
          usage
          exitonerror "L'option \"--${name}\" est invalide"
        fi
        if [[ "${arg}" == *=* ]]; then
          if [[ "${FLAG_OPTIONS}" == *"${short}"* ]]; then
            exitonerror "L'option $(option_names "${short}") ne prend pas de valeur"
          fi
          translated_options+=("-${short}" "${arg#*=}")
        else
          translated_options+=("-${short}")
        fi
        ;;
      *)
        translated_options+=("${arg}")
        ;;
    esac
  done
}

function get_options() {

  while getopts ":gc:e:S:s:i:o:l:r:b:a:t:m:R:nh" option ;
  do
    trace "getopts OPTIND=$OPTIND, Option=$option, OPTARG=$OPTARG, OPTERR=$OPTERR"
    case "${option}" in

      #Input Retropie Image
      i)
        original_retropie_image="${OPTARG}"
        trace "Le fichier d'entrée est ${original_retropie_image}"
	      ;;

      #Ouput image result
      o)
        result_image="${OPTARG}"
	      trace "Le fichier de sortie est ${result_image}"
        ;;

      #Specific with filepath to game to install
      s)
        trace "Specific Mode ON"
        gamefile=${OPTARG}
        specific="ON"
        ;;

      #Specific samples directory to copy beside the game
      S)
        trace "Samples directory"
        samples_dir=${OPTARG}
        ;;

      #Specific controller file name to copy onto SD Card
      c)
        trace "Controller filename"
        controller_file=${OPTARG}
        ;;

      # Emulator name
      e)
        trace "Emulator name"
        emulatorname=${OPTARG}
        ;;

      g)
        trace "Generic Mode ON"
        generic="ON"
        ;;

      a)
        trace "Audio output"
        audio_output=${OPTARG}
        ;;

      t)
        trace "Composite output"
        tv_output=${OPTARG}
        ;;

      m)
        trace "HDMI mode"
        hdmi_format=${OPTARG}
        ;;

      R)
        trace "Rotation"
        rotation=${OPTARG}
        ;;

      b)
        trace "Borders"
        borders=${OPTARG}
        ;;

      l)
        trace "Scanlines"
        scanlines=${OPTARG}
        ;;

      n)
        trace "No smoothing"
        nosmooth="ON"
        ;;

      r)
        trace "Shrink"
        shrink=${OPTARG}
        ;;

      #Missing Arguments
      :)
        exitonerror "L'option $(option_names "${OPTARG}") requiert un argument"
        ;;

      #Invalid Option
      \?)
        usage
        exitonerror "L'option \"-${OPTARG}\" est invalide"
        ;;

      # Help
      h)
        usage
        exit 0
        ;;
    esac
  done
}

# Main start here #######################################################

translate_long_options "$@"
get_options "${translated_options[@]}"

install_prerequisites

check_parameters

prepare_image

mount_image

if ! [[ -z ${generic} ]]; then
  create_Generic_SD
fi

if ! [[ -z ${specific} ]]; then
  create_Specific_SD
fi

read -p $'Les modifications ont été appliquées.\nVérifiez le résultat avant démontage des répertoires... ' -n1 -s
echo
umount_image

prepare_result

exit 0
