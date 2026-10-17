#!/bin/bash

##########################################################################
#
# Nettoie ce qu'une génération interrompue de generate-generic-image.sh
# a pu laisser : montages dans work_temp/ et périphériques loop associés
# à l'image de travail $HOME/out.img.
#
# Les scripts de génération sont lancés depuis work/target : work_temp/
# est donc cherché à côté de ce script.

WORKING_DIRECTORY="$(dirname "${BASH_SOURCE[0]}")/work_temp"
TEMP_IMAGE="${HOME}/out.img"

# Démontage de la partition boot puis de la partition principale
for mount_point in "${WORKING_DIRECTORY}/boot" "${WORKING_DIRECTORY}"; do
  if mountpoint -q "${mount_point}"; then
    echo "Démontage de ${mount_point}"
    sudo umount "${mount_point}"
  fi
done

# Désassociation des périphériques loop liés à l'image de travail
if [[ -f "${TEMP_IMAGE}" ]]; then
  for loop in $(losetup -j "${TEMP_IMAGE}" -O NAME -n); do
    echo "Désassociation de ${loop} et de ${TEMP_IMAGE}"
    sudo losetup -d "${loop}"
  done
fi

# Suppression du répertoire de travail, seulement s'il n'est plus monté
if [[ -d "${WORKING_DIRECTORY}" ]]; then
  if mountpoint -q "${WORKING_DIRECTORY}" || mountpoint -q "${WORKING_DIRECTORY}/boot"; then
    echo "ERREUR : ${WORKING_DIRECTORY} est encore monté, il n'est pas supprimé"
    exit 1
  fi
  echo "Suppression de ${WORKING_DIRECTORY}"
  rm -rf "${WORKING_DIRECTORY}"
fi

echo "Nettoyage terminé"
