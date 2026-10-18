# borne Pac-Man MO5 : aucun réglage particulier
# l'ancien viewport 366x476 à x=149, y=5 n'a jamais eu d'effet. Équivalent à essayer si l'écran fait 640x480 :
# --border left=149,right=125,top=5

../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output pacman.mame2003.mo5.img \
    --specific ../origin/game-to-install/arcade/pacman.zip \
    --controller "../origin/game-to-install/arcade/Mega World.borne.1 bouton-boutongauche-2.cfg" \
    --emulator lr-mame2003 \
    2>&1 \
    | tee
