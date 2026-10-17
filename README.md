# Génération des cartes SD des bornes MO5.com

Ce dépôt produit des images de carte SD pour Raspberry Pi, destinées aux bornes de jeu rétro des expositions MO5.com.
Chaque image part d'une image RetroPie d'origine. Elle est modifiée pour démarrer sans aucun message, directement sur un jeu (mode **spécifique**) ou sur un lanceur qui lit une clé USB (mode **générique**).

Sommaire :
1. [Construire une image](#1-construire-une-image)
2. [Écrire l'image sur une carte SD](#2-écrire-limage-sur-une-carte-sd)
3. [Modifications appliquées à l'image](#3-modifications-appliquées-à-limage)
4. [Répertoires utiles sur la carte](#4-répertoires-utiles-sur-la-carte)

---

## 1. Construire une image

### 1.1 Prérequis

- Un poste **Linux** : le script utilise `losetup` et `mount`, et ne fonctionne pas sous macOS ni Windows.
- `losetup` installé (paquet `util-linux`) et un compte avec les droits `sudo`.
- De la place disque : l'image d'origine est copiée dans `$HOME/out.img`, puis vers le fichier résultat. Il faut donc environ deux fois la taille de l'image.

### 1.2 Préparer les fichiers d'entrée

Tout ce qui sert d'entrée est rangé dans `work/origin/` :

```
work/origin/
├── origin.img                     # image RetroPie d'origine (non versionnée)
└── game-to-install/
    ├── arcade/                    # ROMs arcade (.zip), samples, .cfg de manettes
    ├── nes/
    ├── pcengine/
    └── snes/
```

- **L'image RetroPie** est copiée sous le nom `work/origin/origin.img`. Les fichiers `*.img` sont ignorés par git.
- **Les ROMs** sont rangées dans un sous-répertoire de `game-to-install/`. **Son nom doit être celui du répertoire de ROMs dans RetroPie** (`arcade`, `nes`, `snes`, `pcengine`, `megadrive`…), car le script en déduit le système. Par exemple, `game-to-install/snes/Pocky-Rocky.smc` est installé dans `/home/pi/RetroPie/roms/snes/`.
- **Les fichiers de manette** (`.cfg` RetroArch) et **les répertoires de samples** peuvent être placés n'importe où. Leurs chemins sont passés au script avec `-c` et `-p`.

### 1.3 Lancer la génération avec un script de jeu

Chaque jeu a un script prêt à l'emploi dans `work/target/`. Ces scripts utilisent des chemins relatifs, ils doivent donc être **lancés depuis ce répertoire** :

```
cd work/target
./generate-pacman-0.78-lf-mame2003.sh
```

L'image est produite dans `work/target/` sous le nom donné par `-o` (ici `pacman.mame2003.img`).

Pour ajouter un jeu, copiez un script existant et adaptez sa ligne de commande. Exemple : `generate-pacman-0.78-lf-mame2003.sh`.

```
../../source/generate-image/generate-generic-image.sh -d \
  -i ../origin/origin.img \
  -o pacman.mame2003.img \
  -s ../origin/game-to-install/arcade/pacman.zip \
  -c "../origin/game-to-install/arcade/Mega World.borne.1 bouton-boutongauche-2.cfg" \
  -e lr-mame2003 \
  -x borne_pacman_mo5
```

### 1.4 Appeler directement le script

```
# image générique (le jeu est fourni plus tard sur une clé USB)
source/generate-image/generate-generic-image.sh -d -g -i <image d'origine> -o <image résultat> \
  [-x <profil borne>] [-l <scanlines>] [-n]

# image spécifique (un jeu installé sur la carte)
source/generate-image/generate-generic-image.sh -d -i <image d'origine> -o <image résultat> \
  -s <rom> [-e <émulateur>] [-c <fichier .cfg manette>] [-p <répertoire samples>] [-x <profil borne>] [-l <scanlines>] [-n]
```

| Option | Rôle |
|---|---|
| `-i <image>` | Image RetroPie source. Elle n'est **jamais modifiée** : le script travaille sur une copie (`$HOME/out.img`). |
| `-o <image>` | Fichier résultat. Il est supprimé au début s'il existe déjà. |
| `-g` | Mode **générique** : modifications communes + lanceur clé USB. |
| `-s <rom>` | Mode **spécifique** : modifications communes + jeu installé + lanceur du jeu. |
| `-e <émulateur>` | (avec `-s`) Émulateur forcé au lancement du jeu, par ex. `lr-mame2003` ou `lr-mame2010`. Le nom doit figurer dans `/opt/retropie/configs/<système>/emulators.cfg`. Recommandé : sans `-e`, runcommand peut demander de choisir un émulateur au démarrage (voir [§3.3](#33-mode-spécifique--s-rom)). |
| `-c <fichier .cfg>` | (avec `-s`) Configuration de manette à installer. |
| `-p <répertoire>` | (avec `-s`) Répertoire de samples à installer à côté du jeu. |
| `-x <profil>` | Réglages propres à une borne : `borne_arcade_1_up`, `borne_rene_pierre`, `borne_pacman_mo5`, `pacman_GameStoryVersailles`. Un nom inconnu n'est pas signalé comme une erreur : seules les modifications communes sont appliquées. |
| `-l <scanlines>` | Effet scanlines par shader RetroArch : `scanlines_horizontal` (shader `crt-pi`) ou `scanlines_vertical` (shader `crt-pi-vertical`). Voir [§1.8](#18-choisir-les-scanlines--l) pour choisir. Une autre valeur arrête le script avant toute modification. |
| `-n` | Désactive le lissage de l'image (`video_smooth`) : pixels nets. Utile pour les jeux en basse résolution très agrandis, comme la Game Boy. Implicite avec `-l`. |
| `-d` | Mode debug (traces à l'écran). Aucun effet sur l'image. |

`-g` et `-s` s'excluent mutuellement, et l'un des deux est obligatoire. `-e`, `-c` et `-p` ne sont pris en compte qu'en mode spécifique.

### 1.5 Déroulement d'une génération

1. L'image d'origine est copiée dans `$HOME/out.img`.
2. Cette copie est associée à un périphérique loop. La partition 2 est montée sur `work_temp/` dans le répertoire courant, la partition 1 sur `work_temp/boot`. Le mot de passe `sudo` est demandé.
3. Les modifications décrites dans la [section 3](#3-modifications-appliquées-à-limage) sont appliquées.
4. **Le script fait une pause** : « Les modifications ont été appliquées… ». Vous pouvez alors inspecter l'image montée dans `work_temp/`. Appuyez sur une touche pour continuer.
5. Les partitions sont démontées, `work_temp/` est supprimé et le périphérique loop est libéré.
6. `$HOME/out.img` est copié vers le fichier passé à `-o`.

Le script fait aussi une pause, puis s'arrête, si le système de la ROM est inconnu, c'est-à-dire si `roms/<système>` n'existe pas dans l'image. Le script est interactif et n'est pas prévu pour tourner sans surveillance.

Le journal est écrit dans `source/generate-image/generate-generic-image.log`.

### 1.6 Nettoyer après un arrêt brutal

Si une génération s'interrompt, des montages ou un périphérique loop peuvent rester actifs. Pour les libérer :

```
cd work/target
./clean.sh
```

Le script démonte `work_temp/boot` puis `work_temp/` s'ils sont montés. Il libère ensuite les périphériques loop associés à `$HOME/out.img` et supprime `work_temp/`. Il ne supprime jamais `work_temp/` si un montage est encore actif. `$HOME/out.img` est conservé : il sera remplacé à la prochaine génération.

`clean.sh` cherche `work_temp/` dans `work/target/`, là où les scripts de génération le créent. Si la génération a été lancée depuis un autre répertoire, faites le nettoyage à la main depuis ce répertoire :

```
losetup -j $HOME/out.img       # repérer le périphérique, ex. /dev/loop0
sudo umount work_temp/boot
sudo umount work_temp
sudo losetup -d /dev/loop0
rm -rf work_temp
```

### 1.7 Profils `-x` utilisés dans `work/target/`

| Profil | Borne | Scripts |
|---|---|---|
| `borne_arcade_1_up` | Arcade1Up | `generate-pocky-rockey-snes-arcade1un.sh` |
| `borne_pacman_mo5` | Borne Pac-Man MO5 | `generate-pacman-0.78-lf-mame2003.sh` |
| `borne_rene_pierre` | Table cocktail René Pierre | `game_story_versailles_tetris_cocktail_mame2010.sh`, `game_story_versailles_spaceinvaders_II_cocktail_mame2003.sh` |
| `pacman_GameStoryVersailles` | TV en sortie composite (Game Story Versailles) | `GameStoryVersailles_pacman-0.78-mame2003.sh`, `GameStoryVersailles_space-invaders-0.35b-lr-mame2003.sh` |

Pour une nouvelle borne, ajoutez un bloc `if [[ "${specific_console}" == "<profil>" ]]` dans la fonction `apply_common_modifications_on_SD` de `generate-generic-image.sh`.

### 1.8 Choisir les scanlines (`-l`)

Choisissez selon l'orientation du **jeu d'origine**, pas selon l'écran de la borne :

- **Jeu horizontal** (image plus large que haute) : `-l scanlines_horizontal`. Cela couvre toutes les consoles (NES, SNES, PC Engine…) et la plupart des jeux d'arcade.
- **Jeu vertical** (image plus haute que large, l'écran de la borne d'arcade était monté tourné de 90°) : `-l scanlines_vertical`.

**Pourquoi.** Sur la borne d'origine, les lignes du tube cathodique suivaient toujours le grand côté du tube. Pour un jeu vertical, le moniteur était tourné, donc le joueur voyait des lignes **verticales**. `lr-mame2003` produit l'image d'un jeu vertical déjà dans le bon sens, en portrait. Le shader doit donc tracer ses lignes dans le sens des colonnes : c'est le rôle de `crt-pi-vertical`. La rotation de l'écran par `display_rotate` (profil `borne_rene_pierre`) s'applique ensuite à l'image entière, scanlines comprises. Elle ne change donc pas le choix.

**Jeux du dépôt.** Ce classement n'a pas été vérifié dans les fichiers ROM.

| Jeu | Orientation | Option |
|---|---|---|
| Pac-Man, Space Invaders, Space Invaders II cocktail, Tetris cocktail (Atari), Kiki Kaikai (arcade) | Vertical | `scanlines_vertical` |
| Astérix, Bubble Bobble, Snow Bros, Street Fighter II Turbo | Horizontal | `scanlines_horizontal` |
| Donkey Kong NES, Pocky & Rocky, jeux PC Engine | Horizontal | `scanlines_horizontal` |

**En cas de doute :**
- dans MAME, un jeu vertical est marqué `ROT90` ou `ROT270` dans ses informations de pilote ; un jeu horizontal est marqué `ROT0` ;
- à l'écran, regardez de près : sur un jeu vertical, les lignes doivent aller de haut en bas, telles que le joueur les voit. Si elles coupent les sprites dans le mauvais sens, changez d'option ;
- exception : si on active le mode « TATE » de MAME, qui laisse l'image non tournée, la règle s'inverse. Ce mode n'est pas utilisé dans ce dépôt.

Pour une sortie composite vers un téléviseur cathodique (`pacman_GameStoryVersailles`), n'utilisez pas `-l` : le téléviseur produit déjà ses propres scanlines.

N'utilisez pas `-l` non plus pour les consoles portables à écran LCD (Game Boy…) : elles n'ont jamais eu de scanlines.

### 1.9 Autres méthodes

- `source/packer-generation/` contient une autre chaîne de génération, basée sur Packer (`packer-builder-arm-image`). `generate-generic-image-with-packer.sh` accepte les mêmes options. Voir le README de ce répertoire.
- `source/generate-image/retropie.sh` et `generate-retropie-image(obsolete).sh` sont d'anciennes versions, remplacées par `generate-generic-image.sh`.

---

## 2. Écrire l'image sur une carte SD

Sous Linux, après avoir inséré une carte (formatée sous Windows ou macOS si besoin) :

1. Repérez le périphérique de la carte avec `lsblk`, par exemple `/dev/sdb`. **Vérifiez-le bien** : `dd` écrase tout le périphérique cible.
2. Démontez ses partitions :
   ```
   sudo umount /dev/sdb*
   ```
3. Copiez l'image :
   ```
   sudo dd bs=4M if=game.img of=/dev/sdb status=progress conv=fsync
   ```

---

## 3. Modifications appliquées à l'image

Cette section liste **exactement** les changements faits par `generate-generic-image.sh`, dans l'ordre d'exécution. Pour chaque changement, elle dit s'il est systématique ou s'il dépend d'une option de la ligne de commande.

Les chemins sont donnés **relativement à la racine de l'image** :
- `/boot/...` désigne la partition 1 (FAT), montée sur `work_temp/boot` pendant la génération ;
- tous les autres chemins sont sur la partition 2 (ext4), montée sur `work_temp/`.

### 3.1 Modifications communes (`-g` et `-s`)

Elles sont faites par la fonction `apply_common_modifications_on_SD`. Certaines sont modifiées ou complétées par le profil `-x`.

#### `/boot/cmdline.txt` — démarrage silencieux

| Changement | Condition |
|---|---|
| Remplace la **première** occurrence de `console=tty1` par `console=tty3 logo.nologo loglevel=3 vt.global_cursor_default=0 plymouth.enable=0` | Toujours |

Les messages du noyau sont envoyés sur tty3 (invisible), le logo framboise est masqué, seuls les messages d'erreur sont affichés et le curseur clignotant est caché. `plymouth.enable=0` désactive l'écran de démarrage graphique Plymouth, s'il est installé.

#### `/boot/config.txt` — affichage

Lignes modifiées :

| Changement | Condition |
|---|---|
| Décommente `#disable_overscan=1` → `disable_overscan=1` (pas de bordure noire) | Toujours **sauf** `-x pacman_GameStoryVersailles` |
| `disable_overscan=1` → `disable_overscan=0` | `-x borne_arcade_1_up` |
| `#overscan_left=16` → `overscan_left=20` | `-x borne_arcade_1_up` |
| `#overscan_right=16` → `overscan_right=20` | `-x borne_arcade_1_up` |
| `#overscan_top=16` → `overscan_top=0` | `-x borne_arcade_1_up` |
| `#overscan_bottom=16` → `overscan_bottom=0` | `-x borne_arcade_1_up` |

Pour `borne_arcade_1_up`, l'overscan est donc réactivé avec des marges de 20 px à gauche et à droite et sans marge en haut ni en bas. Cela donne un léger zoom vertical adapté à l'écran de la borne.

Lignes ajoutées à la fin du fichier, dans cet ordre :

| Ligne ajoutée | Rôle | Condition |
|---|---|---|
| `disable_splash=1` | Supprime l'écran arc-en-ciel au démarrage | Toujours |
| `avoid_warnings=1` | Masque les icônes de sous-tension / surchauffe | Toujours |
| `display_rotate=1` | Rotation de l'affichage de 90° (écran vertical) | `-x borne_rene_pierre` |
| `hdmi_group=2` | Mode HDMI de type DMT (moniteur) | `-x borne_rene_pierre` |
| `hdmi_mode=9` | 800×600 à 60 Hz, 4:3 | `-x borne_rene_pierre` |
| `enable_tvout=1` | Active la sortie vidéo composite | `-x pacman_GameStoryVersailles` |
| `sdtv_mode=2` | Sortie composite en PAL | `-x pacman_GameStoryVersailles` |
| `sdtv_aspect=1` | Format 4:3 | `-x pacman_GameStoryVersailles` |

#### `/boot/ssh` — accès SSH

| Changement | Condition |
|---|---|
| Crée le fichier vide `/boot/ssh` : le service SSH démarre au premier boot | Toujours |

#### `/opt/retropie/configs/all/runcommand.cfg` — lanceur RetroPie

| Changement | Condition |
|---|---|
| Sur la ligne `disable_joystick` : `"0"` → `"1"` (le menu runcommand ne se pilote plus au joystick) | Toujours |
| Sur la ligne `disable_menu` : `"0"` → `"1"` (plus de menu « Press a button to configure » avant le lancement) | Toujours |

#### `/opt/retropie/emulators/retroarch/retroarch.cfg` — configuration RetroArch par défaut

| Changement | Condition |
|---|---|
| Ligne `video_font_enable` : tous les `#` sont retirés et `true` devient `false` (pas de messages à l'écran) | Toujours |
| Ligne `aspect_ratio_index` : `19` → `22` (ratio personnalisé « Custom ») | `-x borne_pacman_mo5` |
| Ligne `custom_viewport_width` : décommentée, `0` → `"366"` | `-x borne_pacman_mo5` |
| Ligne `custom_viewport_height` : décommentée, `0` → `"476"` | `-x borne_pacman_mo5` |
| Ligne `custom_viewport_x` : décommentée, `0` → `"149"` | `-x borne_pacman_mo5` |
| Ligne `custom_viewport_y` : décommentée, `0` → `"5"` | `-x borne_pacman_mo5` |

Pour `borne_pacman_mo5`, l'image du jeu occupe donc une zone de 366×476 px, placée à x=149 et y=5. Cela compense l'écran légèrement décalé de la borne.

#### `/opt/retropie/configs/all/retroarch.cfg` — configuration RetroArch commune

| Changement | Condition |
|---|---|
| Ligne `video_font_enable` : tous les `#` sont retirés et `true` devient `false` | Toujours |
| Ligne `video_smooth` : `false` → `true` (lissage bilinéaire de l'image) | Toujours **sauf** avec `-n` ou `-l` |
| Les lignes `video_smooth` existantes, commentées ou non, sont supprimées, puis `video_smooth = "false"` est ajouté à la fin du fichier (pixels nets) | `-n` ou `-l` |
| Les lignes `video_shader_enable` et `video_shader` existantes, commentées ou non, sont supprimées, puis ces lignes sont ajoutées à la fin du fichier :<br>`video_shader_enable = "true"`<br>`video_shader = "/opt/retropie/configs/all/retroarch/shaders/crt-pi.glslp"` | `-l scanlines_horizontal` |
| Même chose avec `video_shader = "/opt/retropie/configs/all/retroarch/shaders/crt-pi-vertical.glslp"` | `-l scanlines_vertical` |

Avec `-l`, le script vérifie que le fichier `.glslp` existe dans l'image. S'il est absent, il s'arrête et démonte l'image sans produire de résultat.

#### Splash screen

| Changement | Condition |
|---|---|
| `/etc/splashscreen.list` est vidé (taille 0) : aucune vidéo ou image de démarrage RetroPie | Toujours |

#### `/etc/asound.conf` — sortie audio

| Changement | Condition |
|---|---|
| Le fichier est **écrasé** avec :<br>`pcm.!default {type hw card 1}`<br>`ctl.!default {type hw card 1}`<br>Le son passe par la carte 1 (jack) au lieu de la carte 0 (HDMI) | `-x borne_arcade_1_up` **ou** `-x borne_rene_pierre` |

Sans l'un de ces profils, le fichier n'est pas touché.

#### Messages console

| Changement | Condition |
|---|---|
| `/etc/issue` est vidé (plus de bannière avant le login) | Toujours |
| `/etc/motd` est vidé (plus de message du jour après le login) | Toujours |
| Dans `/home/pi/.bashrc`, la ligne commençant par `retropie_welcome` est commentée (plus d'écran d'accueil RetroPie en texte) | Toujours |
| Dans `/etc/rc.local`, ajout **avant** `exit 0` de :<br>`sudo sh -c "TERM=linux setterm -foreground black -clear all >/dev/tty0"`<br>Le texte de la console devient noir sur noir et l'écran est effacé | Toujours |

### 3.2 Mode générique (`-g`)

| Changement | Condition |
|---|---|
| `/opt/retropie/configs/all/autostart.sh` est **remplacé** par `source/launch-game/10-retropie.sh.generic`. Son propriétaire devient celui du répertoire `/opt/retropie/configs/all` (`pi`) | `-g` |

Au démarrage, ce script :
- lance `python3 /media/usb0/bin/launch-game.py` si ce fichier existe sur une clé USB (la sortie est jetée) ;
- lance sinon EmulationStation.

Aucun jeu n'est installé sur la carte SD. La clé USB doit contenir `bin/` (le lanceur Python de `source/launch-game/`) et `roms/<SYSTÈME>/` avec le jeu et le `.cfg` de la manette.

### 3.3 Mode spécifique (`-s <rom>`)

#### Lanceur

| Changement | Condition |
|---|---|
| `/opt/retropie/configs/all/autostart.sh` est **remplacé** par `source/launch-game/10-retropie.sh.specific`. Son propriétaire devient celui du répertoire `/opt/retropie/configs/all` (`pi`) | `-s` |
| Dans ce fichier, `CORE_NAME` est remplacé par le nom du répertoire parent de la ROM (ex. `arcade`, `snes`) | `-s` |
| `GAME_NAME` est remplacé par le nom du fichier de la ROM | `-s` |
| `EMULATOR_NAME` est remplacé par le nom de l'émulateur | `-e <émulateur>` |
| `EMULATOR_NAME` est remplacé par une chaîne vide | `-s` sans `-e` |

Au démarrage, ce script :
- lance `runcommand.sh 0 _SYS_ <système> <rom>` si `-e` n'a pas été donné. C'est l'émulateur par défaut du système qui est utilisé ;
- avec `-e`, cherche la ligne de commande de l'émulateur dans `/opt/retropie/configs/<système>/emulators.cfg`, y remplace `%ROM%` par le chemin du jeu, puis l'exécute.

Le script contient un contrôle des manettes connues (`retroarch-joypads`), mais il est **désactivé** : `check_Controllers=1` est forcé. EmulationStation n'est donc jamais lancé à la place du jeu.

#### Jeu

| Changement | Condition |
|---|---|
| La ROM est copiée dans `/home/pi/RetroPie/roms/<système>/`. `<système>` est le nom du répertoire qui contient la ROM. Son propriétaire devient celui du répertoire `roms` | `-s <rom>` |

Si `/home/pi/RetroPie/roms/<système>` n'existe pas dans l'image, le script s'arrête après une pause et l'image n'est pas générée.

#### Contrôle de l'émulateur

Le script lit `/opt/retropie/configs/<système>/emulators.cfg` dans l'image, sans le modifier. Il s'arrête et l'image n'est pas générée :
- si ce fichier n'existe pas (aucun émulateur installé pour ce système) ;
- avec `-e` : si l'émulateur demandé n'y figure pas. Le jeu ne pourrait pas démarrer (écran noir) ;
- sans `-e` : s'il n'y a pas de ligne `default = "…"`. Au démarrage, runcommand afficherait alors un menu de choix de l'émulateur.

Pour qu'aucun choix d'émulateur ne puisse jamais apparaître, il est préférable de toujours donner `-e`. Le lanceur exécute alors directement la commande de l'émulateur, sans passer par runcommand.

#### Samples

| Changement | Condition |
|---|---|
| Le répertoire donné est copié récursivement vers `/home/pi/RetroPie/roms/<système>/samples` (propriétaire : celui de `roms`) | `-p <répertoire>` |

#### Manette

| Changement | Condition |
|---|---|
| Le fichier `.cfg` est copié dans `/opt/retropie/configs/all/retroarch/autoconfig/` sous le même nom (propriétaire : celui de `roms`) | `-c <fichier .cfg>` |

### 3.4 Points d'attention

Ces remarques viennent de la lecture du script. Elles ne changent pas son comportement, mais elles aident à comprendre le résultat.

- **Profil `pacman_GameStoryVersailles` :** `disable_overscan` reste commenté, donc l'overscan par défaut du firmware s'applique. C'est voulu pour la sortie composite sur un téléviseur.
- **Profil `borne_pacman_mo5` :** le script ne décommente pas la ligne `aspect_ratio_index`. Si elle est commentée dans l'image d'origine, le passage à `22` n'a pas d'effet et RetroArch garde son ratio par défaut.
- **Viewport et `video_font_enable` :** ces réglages sont faits dans `/opt/retropie/emulators/retroarch/retroarch.cfg`, qui est le fichier par défaut de RetroArch. Ce n'est pas `/opt/retropie/configs/all/retroarch.cfg`, le fichier lu en priorité par RetroPie.
- **Remplacements larges :** les `sed` de type `s/#//g` et `s/0/.../g` portent sur **toute la ligne**. Une ligne qui contient plusieurs `#` ou plusieurs `0` est entièrement modifiée.
- **Remplacements limités :** les remplacements de `cmdline.txt`, de l'overscan et des noms dans `autostart.sh` ne portent que sur la **première** occurrence trouvée dans le fichier (`sed '0,/motif/ s//.../'`).
- **Scanlines et `video_smooth` :** avec `-l`, le lissage est désactivé, car il rendrait les lignes floues. Le choix du shader dépend de l'orientation du jeu d'origine, pas de celle de l'écran (voir [§1.8](#18-choisir-les-scanlines--l)).
- **Scanlines et viewport :** avec `borne_pacman_mo5`, la zone de 366×476 px n'est pas un multiple entier de la résolution du jeu. Les lignes peuvent être irrégulières (moiré). À vérifier à l'écran.
- **Scanlines et sortie composite :** `-l` est déconseillé avec `pacman_GameStoryVersailles`. Un téléviseur cathodique produit déjà ses propres scanlines.

---

## 4. Répertoires utiles sur la carte

| Contenu | Répertoire |
|---|---|
| Fichiers de configuration des manettes | `/opt/retropie/configs/all/retroarch/autoconfig` |
| Script de démarrage (`autostart.sh`) | `/opt/retropie/configs/all` |
| ROMs | `/home/pi/RetroPie/roms/<système>` |
| Émulateurs disponibles par système | `/opt/retropie/configs/<système>/emulators.cfg` |

L'accès SSH est activé : `ssh pi@<adresse de la borne>`. Le mot de passe par défaut de RetroPie est `raspberry`, sauf s'il a été changé dans l'image d'origine.
