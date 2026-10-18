# borne Arcade1Up : bordures de 20 px à gauche et à droite, son sur la prise jack

../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output pocky-rocky-snes-arcade1up.img \
    --specific ../origin/game-to-install/snes/Pocky-Rocky.smc \
    --controller ../origin/game-to-install/nes/USB-gamepad.cfg \
    --border left=20,right=20 \
    --audio jack \
    2>&1 \
    | tee
