../../source/generate-image/generate-generic-image.sh \
    -d \
    -i ../origin/origin.img \
    -o zelda-links-awakening-dx-gbc.img \
    -s "../origin/game-to-install/gbc/Legend of Zelda, The - Link's Awakening DX (France) (Rev 1) (SGB Enhanced) (GB Compatible).zip" \
    -c ../origin/game-to-install/gbc/USB-gamepad.cfg \
    -e lr-gambatte \
    -n \
    2>&1 \
    | tee
