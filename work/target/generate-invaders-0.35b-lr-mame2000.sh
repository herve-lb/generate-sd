../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output invaders.mame2000.img \
    --specific ../origin/game-to-install/arcade/invaders.zip \
    --samples ../origin/game-to-install/arcade/samples.space.invaders/ \
    --emulator lr-mame2000 \
    2>&1 \
    | tee
