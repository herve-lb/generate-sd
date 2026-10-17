../../source/generate-image/generate-generic-image.sh \
    -d \
    -i ../origin/origin.img \
    -o donkey-kong-world-arcade-version-nes-emul.img \
    -s '../origin/game-to-install/nes/Donkey Kong - Original Edition (USA, Europe) (3DS Virtual Console).nes' \
    -c ../origin/game-to-install/nes/USB-gamepad.cfg \
    -l scanlines_horizontal \
    2>&1 \
    | tee
