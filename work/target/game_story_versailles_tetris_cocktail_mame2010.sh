# borne René Pierre (cocktail) : écran tourné de 90° (display_rotate=1), moniteur VGA 800x600, son sur la prise jack

# installer le core mame 0.139 pour Tetris : sudo ./retropie_packages.sh lr-mame2010 install

../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output tetris.cocktail.mame2010.img \
    --specific ../origin/game-to-install/arcade/atetrisc.zip \
    --controller "../origin/game-to-install/arcade/DragonRise Inc.   Generic   USB  Joystick  .cfg" \
    --emulator lr-mame2010 \
    --rotate 90 \
    --hdmi-mode monitor_800x600_60hz \
    --audio jack \
    2>&1 \
    | tee
