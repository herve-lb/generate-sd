../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output jacky-chan-pcengine-specific.img \
    --specific "../origin/game-to-install/pcengine/Jackie Chan's Action Kung Fu (USA).pce" \
    --controller "../origin/game-to-install/pcengine/Mega World.cfg" \
    2>&1 \
    | tee
