../../source/generate-image/generate-generic-image.sh \
    --input ../origin/origin.img \
    --output sf-ii-turbo-hyper-firghting-mame-specific.img \
    --specific ../origin/game-to-install/arcade/sf2hf.zip \
    --controller "../origin/game-to-install/arcade/Mega World.cfg" \
    --emulator lr-fbalpha \
    2>&1 \
    | tee
