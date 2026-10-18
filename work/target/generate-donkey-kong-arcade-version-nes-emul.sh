../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output donkey-kong-world-arcade-version-nes-emul.img \
    --specific "../origin/game-to-install/nes/Donkey Kong - Original Edition (USA, Europe) (3DS Virtual Console).nes" \
    --controller "../origin/game-to-install/nes/Mega World.cfg" \
    --scanlines horizontal \
    2>&1 \
    | tee
