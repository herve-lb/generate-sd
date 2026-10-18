../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output zelda-links-awakening-dx-gbc.img \
    --specific "../origin/game-to-install/gbc/Legend of Zelda, The - Link's Awakening DX (France) (Rev 1) (SGB Enhanced) (GB Compatible).zip" \
    --controller "../origin/game-to-install/gbc/Mega World.cfg" \
    --emulator lr-gambatte \
    --reduce 5:1024x768:bottom \
    --no-smoothing \
    2>&1 \
    | tee
