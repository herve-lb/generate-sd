../../source/generate-image/generate-generic-image.sh \
    -d \
    -i ../origin/origin.img \
    -o zelda-links-awakening-gb.img \
    -s "../origin/game-to-install/gb/Legend of Zelda, The - Link's Awakening (France).zip" \
    -c ../origin/game-to-install/gb/USB-gamepad.cfg \
    -e lr-gambatte \
    -n \
    2>&1 \
    | tee
