# borne Pac-Man GameStory Versailles : téléviseur cathodique en sortie composite PAL 4:3,
# avec l'overscan par défaut du firmware

../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output GameStoryVersailles_invaders.mame2003.img \
    --specific ../origin/game-to-install/arcade/invaders.zip \
    --samples ../origin/game-to-install/arcade/samples.space.invaders/ \
    --controller "../origin/game-to-install/arcade/Mega World.cfg" \
    --emulator lr-mame2003 \
    --tv-out pal \
    2>&1 \
    | tee
