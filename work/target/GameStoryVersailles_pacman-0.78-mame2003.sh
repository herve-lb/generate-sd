# borne Pac-Man GameStory Versailles : téléviseur cathodique en sortie composite PAL 4:3,
# avec l'overscan par défaut du firmware

../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output pacman.mame2003.gamestory.img \
    --specific ../origin/game-to-install/arcade/pacman.zip \
    --controller "../origin/game-to-install/arcade/Mega World.cfg" \
    --emulator lr-mame2003 \
    --tv-out pal \
    2>&1 \
    | tee
