#!/bin/bash

##########################################################################
#
# This script creates GENERIC or SPECIFIC retropie images starting from a brand new retropie image,
# and modifies the display, sound and controller settings of an image or SD card it generated.
#
# Requirements :
# - Linux OS
# - losetup, lsblk
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
# options used to generate the image, read back by the configuration editor
OPTIONS_RECORD_FILENAME="mo5-options.conf"
# mount points of the read-only inspection (--inspect)
INSPECT_DIRECTORY="work_temp_inspect"
JACK_AUDIO_LINES=$'pcm.!default {type hw card 1}\nctl.!default {type hw card 1}'

# the user who launched the script, even through sudo: owns the working and result images
REAL_USER="${SUDO_USER:-$(id -un)}"
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
TEMP_IMAGE="${REAL_HOME}/out.img"

# Options ###############################################################
#
# Single description of every option, used by getopts, the long names, the help, the value checks
# and --describe (read by the configuration editor).
# short|long|variable|type|values|label|category|title|description
#   type: flag (no value), file, dir, path, text, choice (one of the values)
#   values: the possible values of a choice, or the allowed extensions of a file
#   category: mode, image, game, controller, display, sound, run
#   title: short name shown by the configuration editor, description: its help
#   controller, display and sound options can also be changed on a generated image or SD card (--modify)

OPTIONS=(
  "g|generic|generic|flag|||mode|Image générique|image générique : le jeu est fourni plus tard sur une clé USB"
  "s|specific|gamefile|file||rom|mode|Image spécifique|image spécifique : jeu à installer. Le système est le nom du répertoire de la ROM (arcade, nes, snes…)"
  "I|inspect|inspect_target|path||image ou carte|mode|Image ou carte à lire|affiche les réglages réels d'une image générée (.img) ou d'une carte SD (/dev/sdX), lue en lecture seule, comparés à /boot/mo5-options.conf"
  "M|modify|modify_target|path||image ou carte|mode|Image ou carte à modifier|modifie les réglages d'affichage, de son et de manette d'une image générée (.img) ou d'une carte SD (/dev/sdX)"
  "i|input|original_retropie_image|file||image|image|Image RetroPie d'origine|image RetroPie d'origine (jamais modifiée)"
  "o|output|result_image|path||image|image|Image à générer|image à générer (remplacée si elle existe)"
  "e|emulator|emulatorname|text||émulateur|game|Émulateur|émulateur forcé, par exemple lr-mame2003. Sans cette option, l'émulateur par défaut du système"
  "S|samples|samples_dir|dir||répertoire|game|Samples|samples à installer à côté du jeu"
  "c|controller|controller_file|file|cfg|fichier.cfg|controller|Manette|configuration de manette RetroArch (.cfg) à installer"
  "l|scanlines|scanlines|choice|horizontal vertical||display|Scanlines|effet scanlines : horizontal pour un jeu horizontal, vertical pour un jeu vertical"
  "n|no-smoothing|nosmooth|flag|||display|Pas de lissage|pas de lissage de l'image : pixels nets"
  "r|reduce|shrink|text||pourcentage:largeurxhauteur[:alignement]|display|Réduction de l'écran|réduit l'affichage de ce pourcentage pour un écran de cette résolution, par exemple 5:1024x768:bottom. Alignement : top, bottom, left, right, top-left, top-right, bottom-left, bottom-right"
  "b|border|borders|text||left=N,right=N,top=N,bottom=N|display|Bordures|bordures noires en pixels, par exemple left=20,right=20 (côtés absents : 0)"
  "m|hdmi-mode|hdmi_format|choice|monitor_640x480_60hz monitor_800x600_60hz monitor_1024x768_60hz monitor_1280x1024_60hz tv_720p_60hz tv_1080p_60hz||display|Mode HDMI|mode HDMI forcé : monitor_* pour un moniteur (DMT), tv_* pour un téléviseur (CEA)"
  "t|tv-out|tv_output|choice|pal ntsc||display|Sortie composite|sortie composite 4:3 pour un téléviseur cathodique"
  "R|rotate|rotation|choice|90 180 270||display|Rotation|rotation de l'écran dans le sens horaire"
  "a|audio|audio_output|choice|jack hdmi||sound|Sortie du son|sortie du son (hdmi : sortie par défaut)"
  "B|batch|batch|flag|||run|Sans pause|sans pause : ne demande pas de vérifier l'image avant le démontage"
  "d|describe|describe|flag|||run|Description JSON|décrit les options au format JSON (pour l'éditeur de configuration)"
  "h|help|help|flag|||run|Aide|cette aide"
)

# pairs of long options that cannot be used together
CONFLICTS=(
  "generic specific"
  "generic modify"
  "specific modify"
  "generic inspect"
  "specific inspect"
  "modify inspect"
  "reduce border"
  "tv-out hdmi-mode"
)

# categories, in display order, and their label
CATEGORIES=(
  "mode|Type d'image"
  "image|Images"
  "game|Jeu"
  "controller|Manette"
  "display|Affichage"
  "sound|Son"
  "run|Exécution"
)

# categories that --modify can change on a generated image or SD card
SETTINGS_CATEGORIES="controller display sound"

# HDMI modes of -m: group 1 = CEA (TV modes), group 2 = DMT (computer monitor modes)
declare -A HDMI_MODES=(
  [monitor_640x480_60hz]="2 4"
  [monitor_800x600_60hz]="2 9"
  [monitor_1024x768_60hz]="2 16"
  [monitor_1280x1024_60hz]="2 35"
  [tv_720p_60hz]="1 4"
  [tv_1080p_60hz]="1 16"
)

# globals ################################################################

logFileName=
translated_options=()
loop=
loop_created=
inspect_mounts=()

# option values (see OPTIONS)
generic=
gamefile=
modify_target=
inspect_target=
original_retropie_image=
result_image=
emulatorname=
samples_dir=
controller_file=
scanlines=
nosmooth=
shrink=
borders=
hdmi_format=
tv_output=
rotation=
audio_output=
batch=
describe=
help=

# values computed from the options
shader_file=
sdtv_mode=
hdmi_group=
hdmi_mode=
display_rotate=
overscan_left=
overscan_right=
overscan_top=
overscan_bottom=

# Option table access ###################################################

# read the fields of an option line into opt_short, opt_long, opt_var, opt_type, opt_values, opt_label, opt_category, opt_title, opt_description
function read_option() {
  IFS='|' read -r opt_short opt_long opt_var opt_type opt_values opt_label opt_category opt_title opt_description <<< "$1"
}

# find an option by its short (-s) or long (--specific) name, then read its fields
function find_option() {
  local spec
  for spec in "${OPTIONS[@]}"; do
    read_option "${spec}"
    if [[ "$1" == "-${opt_short}" || "$1" == "--${opt_long}" ]]; then
      return 0
    fi
  done
  return 1
}

# value of an option, by its long name
function option_value() {
  find_option "--$1" && echo "${!opt_var}"
}

# "-s (--specific)" for messages
function option_names() {
  if find_option "$1"; then
    echo "-${opt_short} (--${opt_long})"
  else
    echo "$1"
  fi
}

# OS pre-requisite #######################################################

function install_prerequisites() {

  # check losetup installation
  if ! command -v losetup > /dev/null; then
    exitonerror "logiciel losetup manquant. Impossible de charger l'image de Retropie"
  fi
}

function check_parameters() {
  local spec pair first second value message

  # exactly one of generic, specific, modify or inspect
  if [[ -z "${generic}${gamefile}${modify_target}${inspect_target}" ]]; then
    usage
    exitonerror "Il faut choisir le mode : $(option_names --generic), $(option_names --specific), $(option_names --modify) ou $(option_names --inspect)"
  fi

  # options that cannot be used together
  for pair in "${CONFLICTS[@]}"; do
    read -r first second <<< "${pair}"
    if [[ -n "$(option_value "${first}")" && -n "$(option_value "${second}")" ]]; then
      usage
      exitonerror "Les options $(option_names "--${first}") et $(option_names "--${second}") ne se combinent pas"
    fi
  done

  # choice options: the value must be one of the listed values; file options: one of the listed extensions
  for spec in "${OPTIONS[@]}"; do
    read_option "${spec}"
    value="${!opt_var}"
    # the message is built before usage, which reads the option table again
    message=""
    if [[ "${opt_type}" == "choice" && -n "${value}" && " ${opt_values} " != *" ${value} "* ]]; then
      message="Option -${opt_short} (--${opt_long}) inconnue : ${value} (valeurs possibles : ${opt_values// /, })"
    fi
    if [[ "${opt_type}" == "file" && -n "${value}" && -n "${opt_values}" && " ${opt_values} " != *" ${value##*.} "* ]]; then
      message="Option -${opt_short} (--${opt_long}) : ${value} n'est pas un fichier ${opt_values// /, }"
    fi
    if [[ -n "${message}" ]]; then
      usage
      exitonerror "${message}"
    fi
  done

  # with --modify, only the settings can be given
  if [[ -n "${modify_target}" ]]; then
    for spec in "${OPTIONS[@]}"; do
      read_option "${spec}"
      if [[ -n "${!opt_var}" && " mode run ${SETTINGS_CATEGORIES} " != *" ${opt_category} "* ]]; then
        message="L'option -${opt_short} (--${opt_long}) ne sert qu'à la génération, pas avec $(option_names --modify)"
        usage
        exitonerror "${message}"
      fi
    done
    if ! [[ -f "${modify_target}" || -b "${modify_target}" ]]; then
      exitonerror "Image ou carte SD introuvable : ${modify_target}"
    fi
  elif [[ -n "${inspect_target}" ]]; then
    # with --inspect, nothing else than the target
    for spec in "${OPTIONS[@]}"; do
      read_option "${spec}"
      if [[ -n "${!opt_var}" && " mode run " != *" ${opt_category} "* ]]; then
        message="L'option -${opt_short} (--${opt_long}) ne sert pas avec $(option_names --inspect), qui ne fait que lire"
        usage
        exitonerror "${message}"
      fi
    done
    if ! [[ -f "${inspect_target}" || -b "${inspect_target}" ]]; then
      exitonerror "Image ou carte SD introuvable : ${inspect_target}"
    fi
  else
    if [[ -z "${original_retropie_image}" ]]; then
      usage
      exitonerror "Il faut préciser l'image RetroPie d'origine : $(option_names --input)"
    fi
    if [[ -z "${result_image}" ]]; then
      usage
      exitonerror "Il faut préciser l'image à générer : $(option_names --output)"
    fi
  fi

  # scanlines: matching shader
  case "${scanlines}" in
    horizontal) shader_file="crt-pi.glslp" ;;
    vertical) shader_file="crt-pi-vertical.glslp" ;;
  esac

  # check shrink option (percent:WIDTHxHEIGHT[:alignment]) and compute the overscan margins in pixels
  if ! [[ -z "${shrink}" ]]; then
    if ! reduce_margins "${shrink}"; then
      usage
      exitonerror "Option -r (--reduce) invalide : ${shrink} (format attendu : pourcentage:largeurxhauteur[:alignement], par exemple 5:1024x768 ou 5:1024x768:bottom, avec un pourcentage inférieur à 50 et un alignement parmi top, bottom, left, right, top-left, top-right, bottom-left, bottom-right)"
    fi
    trace "Shrink ${shrink} : overscan gauche ${overscan_left} px, droite ${overscan_right} px, haut ${overscan_top} px, bas ${overscan_bottom} px"
  fi

  # check border option (left=N,right=N,top=N,bottom=N in pixels, missing sides are 0)
  if ! [[ -z "${borders}" ]]; then
    if ! border_margins "${borders}"; then
      usage
      exitonerror "Option -b (--border) invalide : ${borders} (format attendu : left=N,right=N,top=N,bottom=N en pixels, par exemple left=20,right=20)"
    fi
    trace "Bordures ${borders} : overscan gauche ${overscan_left} px, droite ${overscan_right} px, haut ${overscan_top} px, bas ${overscan_bottom} px"
  fi

  # composite output
  case "${tv_output}" in
    pal) sdtv_mode=2 ;;
    ntsc) sdtv_mode=0 ;;
  esac

  # HDMI mode
  if ! [[ -z "${hdmi_format}" ]]; then
    read -r hdmi_group hdmi_mode <<< "${HDMI_MODES[${hdmi_format}]}"
  fi

  # rotation (clockwise)
  case "${rotation}" in
    90) display_rotate=1 ;;
    180) display_rotate=2 ;;
    270) display_rotate=3 ;;
  esac

  # check if the user specify a good filename for the game
  if ! [[ -z "${gamefile}" ]]; then
    if ! [[ -f "${gamefile}" ]]; then
      usage
      exitonerror "Il faut préciser un nom de fichier valide pour le jeu à installer"
    fi

    # if samples is provided then check samples directory existence
    if [[ ! -z "${samples_dir}" ]] && [[ ! -d "${samples_dir}" ]]; then
      usage
      exitonerror "Il faut préciser un répertoire de Samples valide pour accompagner le jeu à installer"
    fi
  fi

  # if controller filename is provided then check file exists
  if [[ ! -z "${controller_file}" ]] && [[ ! -f "${controller_file}" ]]; then
    usage
    exitonerror "Il faut préciser un nom de fichier valide pour la configuration du joystick"
  fi
}

# overscan margins of a --reduce value (percent:WIDTHxHEIGHT[:alignment]) in overscan_left/right/top/bottom; fails if invalid
function reduce_margins() {
  if ! [[ "$1" =~ ^([0-9]+)(\.[0-9]+)?:([0-9]+)x([0-9]+)(:(top|bottom|left|right|top-left|top-right|bottom-left|bottom-right))?$ ]] || (( 10#${BASH_REMATCH[1]} >= 50 )); then
    return 1
  fi
  local percent="${1%%:*}"
  local alignment="${BASH_REMATCH[6]}"
  local horizontal=$(awk -v p="${percent}" -v w="${BASH_REMATCH[3]}" 'BEGIN { printf "%d", w * p / 200 + 0.5 }')
  local vertical=$(awk -v p="${percent}" -v h="${BASH_REMATCH[4]}" 'BEGIN { printf "%d", h * p / 200 + 0.5 }')

  # centered by default, the whole margin goes to the opposite side of the alignment
  overscan_left=${horizontal}
  overscan_right=${horizontal}
  overscan_top=${vertical}
  overscan_bottom=${vertical}
  case "${alignment}" in
    top*) overscan_top=0 ; overscan_bottom=$((vertical * 2)) ;;
    bottom*) overscan_top=$((vertical * 2)) ; overscan_bottom=0 ;;
  esac
  case "${alignment}" in
    *left) overscan_left=0 ; overscan_right=$((horizontal * 2)) ;;
    *right) overscan_left=$((horizontal * 2)) ; overscan_right=0 ;;
  esac
}

# overscan margins of a --border value (left=N,right=N,top=N,bottom=N, missing sides are 0); fails if invalid
function border_margins() {
  local border
  overscan_left=0
  overscan_right=0
  overscan_top=0
  overscan_bottom=0
  for border in ${1//,/ }; do
    [[ "${border}" =~ ^(left|right|top|bottom)=([0-9]+)$ ]] || return 1
    case "${BASH_REMATCH[1]}" in
      left) overscan_left=$((10#${BASH_REMATCH[2]})) ;;
      right) overscan_right=$((10#${BASH_REMATCH[2]})) ;;
      top) overscan_top=$((10#${BASH_REMATCH[2]})) ;;
      bottom) overscan_bottom=$((10#${BASH_REMATCH[2]})) ;;
    esac
  done
}

# --border value of the current overscan margins: the non-zero sides
function margins_as_border() {
  local side value result=""
  for side in left right top bottom; do
    value="overscan_${side}"
    if (( ${!value:-0} != 0 )); then
      result+="${result:+,}${side}=${!value}"
    fi
  done
  echo "${result}"
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

  # display to console (on stderr with --inspect, whose output is the settings)
  if [[ -n "${inspect_target}" ]]; then
    echo "${message}" >&2
  else
    echo "${message}"
  fi

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

# pause so that the mounted image can be checked, except in batch mode
function pause() {
  if [[ -z "${batch}" ]]; then
    read -p "$1" -n1 -s
    echo
  fi
}

# Image file Management #######################################################

function prepare_image() {
  trace "##########################"
  trace "prepare_image ############"

  if ! [[ -f "${original_retropie_image}" ]]; then
    exitonerror "Le fichier image Retropie d'entrée est introuvable"
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

  # copy the result to the given destination, owned by the user even when run through sudo
  trace "Copie de ${TEMP_IMAGE} vers ${result_image}"
  cp "${TEMP_IMAGE}" "${result_image}"
  chown "${REAL_USER}:$(id -gn "${REAL_USER}")" "${TEMP_IMAGE}" "${result_image}" 2> /dev/null
}

# partitions of a disk, image loop device or SD card, in order: boot (FAT) then system (ext4)
function list_partitions() {
  lsblk -lnpo NAME,TYPE "$1" | awk '$2 == "part" { print $1 }'
}

# an SD card that can be modified: a whole removable, USB or built-in reader (mmc) disk, which does not hold the running system
function check_sd_card() {
  local device="$1"
  local type removable transport

  read -r type removable transport <<< "$(lsblk -dno TYPE,RM,TRAN "${device}")"
  if [[ "${type}" != "disk" ]]; then
    exitonerror "${device} n'est pas un disque entier : indiquer la carte (par exemple /dev/sdb), pas une partition"
  fi
  if [[ "${removable}" != "1" && "${transport}" != "usb" && "${transport}" != "mmc" ]]; then
    exitonerror "${device} n'est ni amovible, ni USB, ni dans un lecteur de carte SD : par sécurité, il n'est pas modifié"
  fi
  if lsblk -lno MOUNTPOINT "${device}" | grep -qxE '/|/boot|/boot/efi|/home|\[SWAP\]'; then
    exitonerror "${device} contient le système en cours d'exécution : il n'est pas modifié"
  fi
}

# unmount the partitions of a device mounted elsewhere (by the desktop when it appears)
function release_partitions() {
  local partition mountpoint
  for partition in $(list_partitions "$1"); do
    mountpoint="$(lsblk -lno MOUNTPOINT "${partition}" | head -n 1)"
    while [[ -n "${mountpoint}" ]]; do
      trace "Démontage de ${partition}, monté sur ${mountpoint}"
      sudo umount "${partition}" || exitonerror "Impossible de démonter ${partition} : fermer les fichiers ouverts dessus"
      mountpoint="$(lsblk -lno MOUNTPOINT "${partition}" | head -n 1)"
    done
  done
}

# mount the boot and system partitions of a device on the working directory
function mount_partitions() {
  local device="$1"
  local partitions
  release_partitions "${device}"
  mapfile -t partitions < <(list_partitions "${device}")
  if (( ${#partitions[@]} < 2 )); then
    exitonerror "${device} n'a pas les deux partitions d'une image RetroPie (démarrage et système)"
  fi

  # Create temporary directory
  trace "Création du répertoire de travail ${WORKING_DIRECTORY}"
  mkdir "${WORKING_DIRECTORY}"
  if [ $? -ne 0 ]; then
    exitonerror "Impossible de créer le répertoire de travail sur le disque"
  fi

  # Mount the image and map on the working directory
  trace "Montage de ${partitions[1]} sur ${WORKING_DIRECTORY}"
  sudo mount "${partitions[1]}" "${WORKING_DIRECTORY}"
  if [ $? -ne 0 ]; then
    exitonerror "Impossible de monter ${partitions[1]} sur ${WORKING_DIRECTORY}"
  fi
  trace "Montage de ${partitions[0]} sur ${BOOT_DIRECTORY}"
  sudo mount "${partitions[0]}" "${BOOT_DIRECTORY}"
  if [ $? -ne 0 ]; then
    exitonerror "Impossible de monter ${partitions[0]} sur ${BOOT_DIRECTORY}"
  fi
}

# mount an image file: associate it to a loop device first
function mount_image() {
  local image="$1"
  trace "##########################"
  trace "mount_image ##############"

  # an image already associated (opened by the configuration editor, or left by an aborted run) is not touched
  if [[ -n "$(losetup -j "${image}")" ]]; then
    exitonerror "L'image ${image} est déjà utilisée par un périphérique loop ($(losetup -j "${image}" | cut -d: -f1)) : la fermer avant"
  fi

  # Associate image to the first available device, in one step to avoid a race on the device
  loop=$(sudo losetup -f --show -P "${image}")
  if [[ -z "${loop}" ]]; then
    exitonerror "Impossible d'associer l'image ${image} à un pseudo périphérique (losetup -f error)"
  fi
  loop_created="ON"
  trace "Association de ${loop} avec l'image ${image}"

  # from now on, always free the image on exit (error, Ctrl-C or normal end)
  trap umount_image EXIT
  trap 'exit 1' INT TERM

  mount_partitions "${loop}"
}

# mount an SD card: free the partitions mounted by the desktop first
function mount_sd_card() {
  local device="$1"
  trace "##########################"
  trace "mount_sd_card ############"

  check_sd_card "${device}"
  loop="${device}"
  trap umount_image EXIT
  trap 'exit 1' INT TERM

  mount_partitions "${device}"
}

function umount_image() {
  # nothing to free (never mounted, or already freed)
  if [[ -z "${loop}" ]]; then
    return
  fi

  trace "##########################"
  trace "umount_image #############"

  if mountpoint -q "${BOOT_DIRECTORY}"; then
    trace "Démontage de ${BOOT_DIRECTORY}"
    sudo umount "${BOOT_DIRECTORY}"
  fi
  if mountpoint -q "${WORKING_DIRECTORY}"; then
    trace "Démontage de ${WORKING_DIRECTORY}"
    sudo umount "${WORKING_DIRECTORY}"
  fi

  # never delete the working directory while the image is still mounted on it
  if mountpoint -q "${BOOT_DIRECTORY}" || mountpoint -q "${WORKING_DIRECTORY}"; then
    warning "Image encore montée sur ${WORKING_DIRECTORY} : répertoire conservé, lancer work/target/clean.sh"
  elif [[ -d "${WORKING_DIRECTORY}" ]]; then
    trace "Suppression du répertoire de travail ${WORKING_DIRECTORY}"
    rm -rf "${WORKING_DIRECTORY}"
  fi

  if [[ -n "${loop_created}" ]]; then
    trace "Désassociation du périphérique ${loop}"
    sudo losetup -d "${loop}"
  else
    sync
  fi
  loop=
  loop_created=
}

# Settings helpers ######################################################

# remove a setting (commented or not) from a file, then append the given line at the end
function replace_setting() {
  local filename="$1"
  local key="$2"
  local line="$3"

  trace "set '${line}' in file ${filename}"
  sudo sed -i -E '/^#* *'"${key}"' *=/d' "${filename}"
  sudo sed -i '$a'"${line}" "${filename}"
}

# remove the active (uncommented) lines of a setting, then append the given line if any
function set_active_setting() {
  local filename="$1"
  local key="$2"
  local line="$3"

  sudo sed -i -E '/^'"${key}"' *=/d' "${filename}"
  if [[ -n "${line}" ]]; then
    trace "set '${line}' in file ${filename}"
    sudo sed -i '$a'"${line}" "${filename}"
  fi
}

# comment the active lines of a setting: the default value applies again
function comment_setting() {
  local filename="$1"
  local key="$2"

  sudo sed -i -E 's/^('"${key}"' *=)/#\1/' "${filename}"
}

# set a setting where it is: replace its active lines, or else uncomment its first commented line, or else append it
function set_setting_in_place() {
  local filename="$1"
  local key="$2"
  local line="$3"

  trace "set '${line}' in file ${filename}"
  if grep -qE '^'"${key}"' *=' "${filename}"; then
    sudo sed -i -E 's/^'"${key}"' *=.*/'"${line}"'/' "${filename}"
  elif grep -qE '^#+ *'"${key}"' *=' "${filename}"; then
    sudo sed -i -E '0,/^#+ *'"${key}"' *=.*/ s//'"${line}"'/' "${filename}"
  else
    sudo sed -i '$a'"${line}" "${filename}"
  fi
}

# append a line unless it is already in the file
function add_line_once() {
  local filename="$1"
  local line="$2"

  if ! grep -qxF "${line}" "${filename}"; then
    trace "add ${line} in file ${filename}"
    sudo sed -i '$a'"${line}" "${filename}"
  fi
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

# SD Creation Management ######################################################

# modifications made once, when the image is generated: silent and fast boot
function apply_base_modifications() {
  trace "####################################"
  trace "apply_base_modifications ###########"

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

  # Disable large rainbow screen on initial boot
  add_line_once "${filename}" "disable_splash=1"

  # disable warnings such as undervoltage/overheating
  add_line_once "${filename}" "avoid_warnings=1"

  # no firmware delay before loading the kernel
  add_line_once "${filename}" "boot_delay=0"

  # no bluetooth on cabinets
  add_line_once "${filename}" "dtoverlay=disable-bt"

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

# display settings (options -l -n -r -b -m -t -R): can be applied again on a generated image
function apply_display_settings() {
  trace "####################################"
  trace "apply_display_settings #############"

  local filename="${BOOT_DIRECTORY}/config.txt"
  trace "## Apply display settings to ${filename}"

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
  else
    # no margin left from a previous -r or -b
    comment_setting "${filename}" "overscan_(left|right|top|bottom)"
    if ! [[ -z "${tv_output}" ]]; then
      # composite output: the firmware default overscan suits CRT TVs
      comment_setting "${filename}" disable_overscan
    else
      # no black border
      set_setting_in_place "${filename}" disable_overscan "disable_overscan=1"
    fi
  fi

  #     Display rotation (option -R)
  set_active_setting "${filename}" display_rotate "${display_rotate:+display_rotate=${display_rotate}}"

  #     Forced HDMI mode (option -m)
  set_active_setting "${filename}" hdmi_group "${hdmi_group:+hdmi_group=${hdmi_group}}"
  set_active_setting "${filename}" hdmi_mode "${hdmi_mode:+hdmi_mode=${hdmi_mode}}"

  #     Composite output, 4:3 (option -t)
  set_active_setting "${filename}" enable_tvout "${tv_output:+enable_tvout=1}"
  set_active_setting "${filename}" sdtv_mode "${sdtv_mode:+sdtv_mode=${sdtv_mode}}"
  set_active_setting "${filename}" sdtv_aspect "${tv_output:+sdtv_aspect=1}"

  #
  # retropie/opt/retropie/configs/all/retroarch.cfg
  #
  filename="${WORKING_DIRECTORY}/opt/retropie/configs/all/retroarch.cfg"
  trace "## Apply display settings to ${filename}"

  #     No smoothing for sharp pixels (option -n, or needed by scanlines). Otherwise RetroArch default (smoothing)
  if ! [[ -z "${nosmooth}" ]] || ! [[ -z "${shader_file}" ]]; then
    replace_setting "${filename}" video_smooth 'video_smooth = "false"'
  else
    set_active_setting "${filename}" video_smooth
  fi

  #     Scanlines with a crt-pi shader
  if ! [[ -z "${shader_file}" ]]; then
    trace "## Scanlines ${scanlines} with shader ${SHADERS_DIRECTORY}/${shader_file}"
    if ! [[ -f "${WORKING_DIRECTORY}${SHADERS_DIRECTORY}/${shader_file}" ]]; then
      exitonerror "Shader introuvable dans l'image : ${SHADERS_DIRECTORY}/${shader_file}"
    fi

    replace_setting "${filename}" video_shader_enable 'video_shader_enable = "true"'
    replace_setting "${filename}" video_shader 'video_shader = "'"${SHADERS_DIRECTORY}/${shader_file}"'"'
  else
    set_active_setting "${filename}" video_shader
  fi
}

# sound settings (option -a): can be applied again on a generated image
function apply_sound_settings() {
  local filename="${WORKING_DIRECTORY}/etc/asound.conf"

  #     Sound on the jack output instead of HDMI (option -a jack). hdmi keeps the default output
  if [[ "${audio_output}" == "jack" ]]; then
    trace "write sound on the jack output in file ${filename}"
    echo "${JACK_AUDIO_LINES}" | sudo tee "${filename}" > /dev/null
  elif [[ -f "${filename}" && "$(cat "${filename}")" == "${JACK_AUDIO_LINES}" ]]; then
    trace "remove ${filename}: sound back on the default output"
    sudo rm "${filename}"
  fi
}

# controller (option -c): copy its RetroArch configuration, replacing the one installed before ($1)
function apply_controller_settings() {
  local previous_controller="$1"
  local user_group="$(stat -c "%U:%G" "${JOYPAD_CONFIGURATION_DIRECTORY}")"

  if [[ -z "${controller_file}" ]]; then
    return
  fi

  local controller_filename=$(basename -- "${controller_file}")
  if [[ -n "${previous_controller}" && "${previous_controller}" != "${controller_filename}" && -f "${JOYPAD_CONFIGURATION_DIRECTORY}/${previous_controller}" ]]; then
    trace "Remove the previous controller file ${previous_controller}"
    sudo rm "${JOYPAD_CONFIGURATION_DIRECTORY}/${previous_controller}"
  fi
  trace "Copy controller file ${controller_file} to ${JOYPAD_CONFIGURATION_DIRECTORY}/${controller_filename}"
  sudo cp "${controller_file}" "${JOYPAD_CONFIGURATION_DIRECTORY}/${controller_filename}"
  sudo chown "${user_group}" "${JOYPAD_CONFIGURATION_DIRECTORY}/${controller_filename}"
}

# value of a key in the options record of the mounted image
function recorded_option() {
  local filename="${BOOT_DIRECTORY}/${OPTIONS_RECORD_FILENAME}"
  if [[ -f "${filename}" ]]; then
    sed -n 's/^'"$1"'=//p' "${filename}" | tail -n 1
  fi
}

# write the options used in /boot, as long_name=value lines (files: name only).
# With --modify, the generation options (mode, game) of the previous record are kept.
function write_options_record() {
  local filename="${BOOT_DIRECTORY}/${OPTIONS_RECORD_FILENAME}"
  local spec value version
  local lines=()

  version="$(git -C "$(dirname "${BASH_SOURCE[0]}")" describe --always --dirty 2> /dev/null)"
  lines+=("# Options utilisées par generate-generic-image.sh, relues par l'éditeur de configuration")
  lines+=("# Ne pas modifier à la main : utiliser --modify")
  lines+=("generator_version=${version:-inconnue}")

  for spec in "${OPTIONS[@]}"; do
    read_option "${spec}"
    if [[ " mode game ${SETTINGS_CATEGORIES} " != *" ${opt_category} "* || "${opt_long}" == "modify" ]]; then
      continue
    fi
    if [[ -n "${modify_target}" && " ${SETTINGS_CATEGORIES} " != *" ${opt_category} "* ]]; then
      value="$(recorded_option "${opt_long}")"
    elif [[ -n "${modify_target}" && "${opt_category}" == "controller" && -z "${!opt_var}" ]]; then
      value="$(recorded_option "${opt_long}")"
    else
      value="${!opt_var}"
      if [[ -n "${value}" && " file dir " == *" ${opt_type} "* ]]; then
        value="$(basename -- "${value}")"
      fi
    fi
    if [[ -n "${value}" ]]; then
      lines+=("${opt_long}=${value}")
    fi
  done
  if [[ -n "${modify_target}" ]]; then
    lines+=("generated=$(recorded_option generated)")
    lines+=("modified=$(date -u +%Y-%m-%dT%H:%M:%SZ)")
  else
    lines+=("generated=$(date -u +%Y-%m-%dT%H:%M:%SZ)")
  fi

  trace "## Write the options used in ${filename}"
  printf '%s\n' "${lines[@]}" | sudo tee "${filename}" > /dev/null
}

function create_Generic_SD () {
  trace "##########################"
  trace "create_Generic_SD ########"

  apply_base_modifications
  apply_display_settings
  apply_sound_settings
  apply_controller_settings

  install_autolaunch_script "${AUTOLAUNCH_SCRIPT_FILENAME_GenericLaunch}"
}

function create_Specific_SD () {
  trace "###########################"
  trace "create_Specific_SD ########"

  apply_base_modifications
  apply_display_settings
  apply_sound_settings

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
    pause "Le jeu est dans un répertoire core inconnu. Time to check "
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
      exitonerror "Pas d'émulateur par défaut pour ${corename} : un choix serait demandé au démarrage. Utiliser l'option $(option_names --emulator) (voir ${filename})"
    fi
    trace "default emulator : $(grep "^default *=" "${filename}")"
  fi

  # Samples installation
  if ! [[ -z "${samples_dir}" ]]; then

    trace "Copy Samples directory ${samples_dir} to ${ROMS_DIRECTORY}/${corename}/samples"
    sudo cp -r "${samples_dir}" "${ROMS_DIRECTORY}/${corename}/samples"
    sudo chown -R "${user_group}" "${ROMS_DIRECTORY}/${corename}/samples"

  fi

  apply_controller_settings

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

# change the display, sound and controller settings of a generated image or SD card
function modify_SD () {
  trace "##########################"
  trace "modify_SD ################"

  if ! [[ -f "${BOOT_DIRECTORY}/${OPTIONS_RECORD_FILENAME}" ]]; then
    warning "Pas de ${OPTIONS_RECORD_FILENAME} : image générée avant l'enregistrement des options, ou non générée par ce script"
  fi

  apply_display_settings
  apply_sound_settings
  apply_controller_settings "$(recorded_option controller)"
}

# Inspection (--inspect) ###############################################

# read-only access to a partition: the mount point the desktop already gave it, or a read-only mount; result in inspect_mountpoint
function mount_for_inspection() {
  local partition="$1" name="$2"
  inspect_mountpoint="$(lsblk -lno MOUNTPOINT "${partition}" | head -n 1)"
  if [[ -z "${inspect_mountpoint}" ]]; then
    inspect_mountpoint="${INSPECT_DIRECTORY}/${name}"
    mkdir -p "${inspect_mountpoint}"
    trace "Montage de ${partition} en lecture seule sur ${inspect_mountpoint}"
    sudo mount -o ro "${partition}" "${inspect_mountpoint}" || exitonerror "Impossible de monter ${partition} en lecture seule"
    inspect_mounts+=("${inspect_mountpoint}")
  else
    trace "${partition} déjà monté sur ${inspect_mountpoint} : lu sur place"
  fi
}

function release_inspection() {
  local index
  for (( index = ${#inspect_mounts[@]} - 1; index >= 0; index-- )); do
    sudo umount "${inspect_mounts[index]}"
  done
  inspect_mounts=()
  if [[ -d "${INSPECT_DIRECTORY}" ]] && ! mountpoint -q "${INSPECT_DIRECTORY}/boot" && ! mountpoint -q "${INSPECT_DIRECTORY}/system"; then
    rm -rf "${INSPECT_DIRECTORY}"
  fi
  if [[ -n "${loop_created}" ]]; then
    sudo losetup -d "${loop}"
    loop_created=
  fi
}

# active value of a key in a key=value file (config.txt, retroarch.cfg): last uncommented line, quotes removed
function active_value() {
  [[ -f "$1" ]] || return 0
  sudo sed -n -E 's/^'"$2"' *= *"?([^"#]*)"?.*/\1/p' "$1" | tail -n 1 | sed 's/ *$//'
}

# one printed setting: name=value
function print_setting() {
  [[ -n "$2" ]] && echo "$1=$2"
}

# print the real settings of a mounted image, compared with the options recorded at generation
function inspect_settings() {
  local boot="$1" system="$2"
  local config="${boot}/config.txt"
  local retroarch="${system}/opt/retropie/configs/all/retroarch.cfg"
  local autostart="${system}/opt/retropie/configs/all/${AUTOLAUNCH_SCRIPT_FILENAME}"
  local autoconfig="${system}/opt/retropie/configs/all/retroarch/autoconfig"
  local record="${boot}/${OPTIONS_RECORD_FILENAME}"
  local value name differs=() notes=()

  # --- real state ---
  # overscan: none (disable_overscan=1), firmware default, or margins
  local real_overscan real_border=""
  value="$(active_value "${config}" disable_overscan)"
  if [[ "${value}" == "1" ]]; then
    real_overscan="none"
  elif [[ "${value}" == "0" ]] && [[ -n "$(active_value "${config}" overscan_left)" && -n "$(active_value "${config}" overscan_right)" \
          && -n "$(active_value "${config}" overscan_top)" && -n "$(active_value "${config}" overscan_bottom)" ]]; then
    overscan_left="$(active_value "${config}" overscan_left)"
    overscan_right="$(active_value "${config}" overscan_right)"
    overscan_top="$(active_value "${config}" overscan_top)"
    overscan_bottom="$(active_value "${config}" overscan_bottom)"
    real_border="$(margins_as_border)"
    real_overscan="border:${real_border}"
  else
    real_overscan="firmware"
  fi

  local real_rotate=""
  value="$(active_value "${config}" display_rotate)"
  case "${value}" in
    ""|0) ;;
    1) real_rotate=90 ;;
    2) real_rotate=180 ;;
    3) real_rotate=270 ;;
    *) notes+=("display_rotate=${value} : rotation non gérée par --rotate") ;;
  esac

  local real_hdmi="" group mode
  group="$(active_value "${config}" hdmi_group)"
  mode="$(active_value "${config}" hdmi_mode)"
  if [[ -n "${group}${mode}" ]]; then
    for name in "${!HDMI_MODES[@]}"; do
      [[ "${HDMI_MODES[${name}]}" == "${group} ${mode}" ]] && real_hdmi="${name}"
    done
    [[ -z "${real_hdmi}" ]] && notes+=("hdmi_group=${group} hdmi_mode=${mode} : mode HDMI non géré par --hdmi-mode")
  fi

  local real_tv=""
  if [[ "$(active_value "${config}" enable_tvout)" == "1" ]]; then
    case "$(active_value "${config}" sdtv_mode)" in
      2) real_tv=pal ;;
      ""|0) real_tv=ntsc ;;
      *) notes+=("sdtv_mode=$(active_value "${config}" sdtv_mode) : norme composite non gérée par --tv-out") ;;
    esac
  fi
  [[ "${real_overscan}" == "firmware" && -z "${real_tv}" ]] && notes+=("overscan par défaut du firmware sans sortie composite")

  local real_audio=""
  if [[ -f "${system}/etc/asound.conf" ]]; then
    if [[ "$(sudo cat "${system}/etc/asound.conf")" == "${JACK_AUDIO_LINES}" ]]; then
      real_audio=jack
    else
      notes+=("/etc/asound.conf personnalisé : sortie du son non gérée par --audio")
    fi
  fi

  local real_scanlines="" shader
  shader="$(active_value "${retroarch}" video_shader)"
  if [[ -n "${shader}" && "$(active_value "${retroarch}" video_shader_enable)" == "true" ]]; then
    case "$(basename -- "${shader}")" in
      crt-pi.glslp) real_scanlines=horizontal ;;
      crt-pi-vertical.glslp) real_scanlines=vertical ;;
      *) notes+=("shader ${shader} non géré par --scanlines") ;;
    esac
  fi
  local real_sharp=""
  [[ "$(active_value "${retroarch}" video_smooth)" == "false" ]] && real_sharp=ON

  local controllers=() file
  for file in "${autoconfig}"/*.cfg; do
    [[ -f "${file}" ]] && controllers+=("$(basename -- "${file}")")
  done

  # --- game, as installed ---
  if [[ -f "${autostart}" ]] && grep -q "launch-game.py" "${autostart}"; then
    print_setting generic ON
  elif [[ -f "${autostart}" ]]; then
    print_setting specific "$(sed -n 's/^ *gamename="\(.*\)" *#.*/\1/p' "${autostart}" | head -n 1)"
    print_setting system "$(sed -n 's/^ *corename="\(.*\)" *#.*/\1/p' "${autostart}" | head -n 1)"
    print_setting emulator "$(sed -n 's/^ *emulatorname="\(.*\)" *#.*/\1/p' "${autostart}" | head -n 1)"
  fi
  print_setting installed_controllers "$(IFS='|'; echo "${controllers[*]}")"

  # --- comparison with the recorded options ---
  local rec_shrink="" rec_borders="" rec_tv="" rec_rotate="" rec_hdmi="" rec_audio="" rec_scanlines="" rec_sharp="" rec_controller=""
  if [[ -f "${record}" ]]; then
    print_setting record yes
    rec_shrink="$(sed -n 's/^reduce=//p' "${record}" | tail -n 1)"
    rec_borders="$(sed -n 's/^border=//p' "${record}" | tail -n 1)"
    rec_tv="$(sed -n 's/^tv-out=//p' "${record}" | tail -n 1)"
    rec_rotate="$(sed -n 's/^rotate=//p' "${record}" | tail -n 1)"
    rec_hdmi="$(sed -n 's/^hdmi-mode=//p' "${record}" | tail -n 1)"
    rec_audio="$(sed -n 's/^audio=//p' "${record}" | tail -n 1)"
    rec_scanlines="$(sed -n 's/^scanlines=//p' "${record}" | tail -n 1)"
    rec_sharp="$(sed -n 's/^no-smoothing=//p' "${record}" | tail -n 1)"
    rec_controller="$(sed -n 's/^controller=//p' "${record}" | tail -n 1)"

    # overscan expected from the recorded options
    local rec_overscan
    if [[ -n "${rec_shrink}" ]] && reduce_margins "${rec_shrink}"; then
      rec_overscan="border:$(margins_as_border)"
    elif [[ -n "${rec_borders}" ]] && border_margins "${rec_borders}"; then
      rec_overscan="border:$(margins_as_border)"
    elif [[ -n "${rec_tv}" ]]; then
      rec_overscan="firmware"
    else
      rec_overscan="none"
    fi
    [[ "${rec_overscan}" != "${real_overscan}" ]] && differs+=(overscan)
    [[ "${rec_rotate}" != "${real_rotate}" ]] && differs+=(rotate)
    [[ "${rec_hdmi}" != "${real_hdmi}" ]] && differs+=(hdmi-mode)
    [[ "${rec_tv}" != "${real_tv}" ]] && differs+=(tv-out)
    [[ "${rec_audio}" != "${real_audio}" ]] && differs+=(audio)
    [[ "${rec_scanlines}" != "${real_scanlines}" ]] && differs+=(scanlines)
    # scanlines imply sharp pixels
    local rec_sharp_effect=""
    [[ -n "${rec_sharp}${rec_scanlines}" ]] && rec_sharp_effect=ON
    [[ "${rec_sharp_effect}" != "${real_sharp}" ]] && differs+=(no-smoothing)
    if [[ -n "${rec_controller}" && " ${controllers[*]} " != *" ${rec_controller} "* ]]; then
      differs+=(controller)
    fi
  else
    print_setting record no
  fi

  # --- settings: the recorded form when the image matches it, the real state otherwise ---
  if [[ -f "${record}" && " ${differs[*]} " != *" overscan "* ]]; then
    print_setting reduce "${rec_shrink}"
    print_setting border "${rec_borders}"
  else
    print_setting border "${real_border}"
  fi
  print_setting scanlines "${real_scanlines}"
  if [[ -f "${record}" && " ${differs[*]} " != *" no-smoothing "* ]]; then
    print_setting no-smoothing "${rec_sharp}"
  elif [[ -z "${real_scanlines}" ]]; then
    print_setting no-smoothing "${real_sharp}"
  fi
  print_setting hdmi-mode "${real_hdmi}"
  print_setting tv-out "${real_tv}"
  print_setting rotate "${real_rotate}"
  print_setting audio "${real_audio}"
  if [[ -n "${rec_controller}" && " ${differs[*]} " != *" controller "* ]]; then
    print_setting controller "${rec_controller}"
  elif (( ${#controllers[@]} == 1 )); then
    print_setting controller "${controllers[0]}"
  fi
  print_setting differs "$(IFS=','; echo "${differs[*]}")"
  for value in "${notes[@]}"; do
    print_setting note "${value}"
  done
}

# print the settings of an image file or an SD card, read-only
function inspect_SD() {
  local target="$1" device partitions
  trace "##########################"
  trace "inspect_SD ###############"

  trap release_inspection EXIT
  trap 'exit 1' INT TERM
  if [[ -b "${target}" ]]; then
    check_sd_card "${target}"
    device="${target}"
  elif [[ -n "$(losetup -j "${target}")" ]]; then
    # already associated (opened by the desktop or the editor): read through that device
    device="$(losetup -j "${target}" | head -n 1 | cut -d: -f1)"
  else
    loop="$(sudo losetup -r -f --show -P "${target}")"
    [[ -n "${loop}" ]] || exitonerror "Impossible d'associer l'image ${target} à un pseudo périphérique"
    loop_created="ON"
    device="${loop}"
  fi

  mapfile -t partitions < <(list_partitions "${device}")
  if (( ${#partitions[@]} < 2 )); then
    exitonerror "${target} n'a pas les deux partitions d'une image RetroPie (démarrage et système)"
  fi
  mount_for_inspection "${partitions[0]}" boot
  local boot="${inspect_mountpoint}"
  mount_for_inspection "${partitions[1]}" system
  local system="${inspect_mountpoint}"
  inspect_settings "${boot}" "${system}"
}

# Parameters Management #################################################

# escape a string for JSON
function json_string() {
  local value="${1//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "${value}"
}

# describe the options, categories and conflicts in JSON, for the configuration editor
function describe_options() {
  local spec entry name label pair first second separator value values

  echo "{"
  echo '  "categories": ['
  separator=""
  for entry in "${CATEGORIES[@]}"; do
    IFS='|' read -r name label <<< "${entry}"
    value="false"
    [[ " ${SETTINGS_CATEGORIES} " == *" ${name} "* ]] && value="true"
    echo "${separator}    {\"name\": $(json_string "${name}"), \"label\": $(json_string "${label}"), \"settings\": ${value}}"
    separator=","
  done
  echo '  ],'
  echo '  "options": ['
  separator=""
  for spec in "${OPTIONS[@]}"; do
    read_option "${spec}"
    values=""
    for value in ${opt_values}; do
      values+="${values:+, }$(json_string "${value}")"
    done
    echo "${separator}    {\"short\": $(json_string "${opt_short}"), \"long\": $(json_string "${opt_long}"), \"type\": $(json_string "${opt_type}"), \"values\": [${values}], \"label\": $(json_string "${opt_label}"), \"category\": $(json_string "${opt_category}"), \"title\": $(json_string "${opt_title}"), \"description\": $(json_string "${opt_description}")}"
    separator=","
  done
  echo '  ],'
  echo '  "conflicts": ['
  separator=""
  for pair in "${CONFLICTS[@]}"; do
    read -r first second <<< "${pair}"
    echo "${separator}    [$(json_string "${first}"), $(json_string "${second}")]"
    separator=","
  done
  echo '  ],'
  echo "  \"record\": $(json_string "/boot/${OPTIONS_RECORD_FILENAME}")"
  echo "}"
}

function usage() {
  local entry name label spec left

  echo
  echo "USAGE:"
  echo "image générique : $(basename "$0") --generic --input <image> --output <image> (options)"
  echo "image spécifique : $(basename "$0") --specific <rom> --input <image> --output <image> (options)"
  echo "modification : $(basename "$0") --modify <image.img ou /dev/sdX> (options de manette, d'affichage et de son)"
  echo
  echo "Chaque option a une forme courte (-s rom) et une forme longue (--specific rom ou --specific=rom)."
  for entry in "${CATEGORIES[@]}"; do
    IFS='|' read -r name label <<< "${entry}"
    echo
    echo "${label} :"
    for spec in "${OPTIONS[@]}"; do
      read_option "${spec}"
      [[ "${opt_category}" == "${name}" ]] || continue
      left="  -${opt_short}, --${opt_long}"
      if [[ "${opt_type}" == "choice" ]]; then
        left+=" ${opt_values// /|}"
      elif [[ "${opt_type}" != "flag" ]]; then
        left+=" <${opt_label}>"
      fi
      if (( ${#left} > 34 )); then
        echo "${left}"
        left=""
      fi
      # pad by characters, not bytes (accented labels)
      printf '%s%*s%s\n' "${left}" $((36 - ${#left})) "" "${opt_description}"
    done
  done
  echo
}

# translate the long options (--name value or --name=value) into the short ones read by getopts
function translate_long_options() {
  translated_options=()
  local arg name
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
        if ! find_option "${name}"; then
          usage
          exitonerror "L'option \"${name}\" est invalide"
        fi
        if [[ "${arg}" == *=* ]]; then
          if [[ "${opt_type}" == "flag" ]]; then
            exitonerror "L'option $(option_names "${name}") ne prend pas de valeur"
          fi
          translated_options+=("-${opt_short}" "${arg#*=}")
        else
          translated_options+=("-${opt_short}")
        fi
        ;;
      *)
        translated_options+=("${arg}")
        ;;
    esac
  done
}

function get_options() {
  local spec optstring=":" option

  # getopts string from the option table: a letter, followed by ":" when the option takes a value
  for spec in "${OPTIONS[@]}"; do
    read_option "${spec}"
    optstring+="${opt_short}"
    [[ "${opt_type}" != "flag" ]] && optstring+=":"
  done

  while getopts "${optstring}" option ;
  do
    case "${option}" in

      #Missing Arguments
      :)
        exitonerror "L'option $(option_names "-${OPTARG}") requiert un argument"
        ;;

      #Invalid Option
      \?)
        usage
        exitonerror "L'option \"-${OPTARG}\" est invalide"
        ;;

      # every other option sets its variable: ON for a flag, its value otherwise
      *)
        find_option "-${option}"
        if [[ "${opt_type}" == "flag" ]]; then
          printf -v "${opt_var}" '%s' "ON"
        else
          printf -v "${opt_var}" '%s' "${OPTARG}"
        fi
        trace "Option -${opt_short} (--${opt_long}) ${OPTARG}"
        ;;
    esac
  done
}

# Main start here #######################################################

translate_long_options "$@"
# --help and --describe only print, without trace nor log
if [[ " ${translated_options[*]} " == *" -h "* ]]; then
  usage
  exit 0
fi
if [[ " ${translated_options[*]} " == *" -d "* ]]; then
  describe_options
  exit 0
fi
get_options "${translated_options[@]}"

install_prerequisites

check_parameters

if ! [[ -z "${inspect_target}" ]]; then
  inspect_SD "${inspect_target}"
  exit 0
fi

if ! [[ -z "${modify_target}" ]]; then
  if [[ -b "${modify_target}" ]]; then
    mount_sd_card "${modify_target}"
  else
    mount_image "${modify_target}"
  fi
  modify_SD
  write_options_record
  pause $'Les modifications ont été appliquées.\nVérifiez le résultat avant démontage des répertoires... '
  umount_image
  exit 0
fi

prepare_image

mount_image "${TEMP_IMAGE}"

if ! [[ -z "${generic}" ]]; then
  create_Generic_SD
fi

if ! [[ -z "${gamefile}" ]]; then
  create_Specific_SD
fi

write_options_record

pause $'Les modifications ont été appliquées.\nVérifiez le résultat avant démontage des répertoires... '
umount_image

prepare_result

exit 0
