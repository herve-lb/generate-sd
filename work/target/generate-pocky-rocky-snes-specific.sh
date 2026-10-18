../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output pocky-rocky-snes-specific.img \
    --specific ../origin/game-to-install/snes/Pocky-Rocky.smc \
    --controller "../origin/game-to-install/snes/USB gamepad.cfg" \
    2>&1 \
    | tee
