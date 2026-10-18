../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output zelda-links-awakening-gb.img \
    --specific "../origin/game-to-install/gb/Legend of Zelda, The - Link's Awakening (France).zip" \
    --controller ../origin/game-to-install/gb/USB-gamepad.cfg \
    --emulator lr-gambatte \
    --no-smoothing \
    2>&1 \
    | tee
