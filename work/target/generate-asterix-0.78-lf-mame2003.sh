../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output asterix.mame.2003.img \
    --specific ../origin/game-to-install/arcade/asterix.zip \
    --emulator lr-mame2003 \
    2>&1 \
    | tee
