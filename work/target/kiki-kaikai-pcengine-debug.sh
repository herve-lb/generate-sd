../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output kiki-kai-kai-pcengine-specific.img \
    --specific ../origin/game-to-install/pcengine/Kiki-Kai-Kai.pce \
    --controller "../origin/game-to-install/pcengine/Mega World.cfg" \
    2>&1 \
    | tee
