../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output donkey-kong-world-nes.img \
    --specific "../origin/game-to-install/nes/Donkey Kong (World) (Rev 1).nes" \
    --controller ../origin/game-to-install/nes/USB-gamepad.cfg \
    --scanlines horizontal \
    2>&1 \
    | tee
