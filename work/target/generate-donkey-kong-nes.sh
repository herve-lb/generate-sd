../../source/generate-image/generate-generic-image.sh \
    -d \
    -i ../origin/origin.img \
    -o donkey-kong-world-nes.img \
    -s '../origin/game-to-install/nes/Donkey Kong (World) (Rev 1).nes' \
    -c ../origin/game-to-install/nes/USB-gamepad.cfg \
    -l scanlines_horizontal \
    2>&1 \
    | tee
