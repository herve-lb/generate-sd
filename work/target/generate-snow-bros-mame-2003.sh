../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output snowbros.mame.2003.img \
    --specific ../origin/game-to-install/arcade/snowbros.zip \
    --controller "../origin/game-to-install/arcade/Mega World.cfg" \
    --emulator lr-mame2003 \
    2>&1 \
    | tee
