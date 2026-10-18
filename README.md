# Génération des cartes SD des bornes MO5.com

Ce dépôt produit des images de carte SD pour Raspberry Pi, destinées aux bornes de jeu rétro des expositions MO5.com.
Chaque image part d'une image RetroPie d'origine. Elle est modifiée pour démarrer sans aucun message, directement sur un jeu (mode **spécifique**) ou sur un lanceur qui lit une clé USB (mode **générique**).

Sommaire :
1. [Construire une image](#1-construire-une-image)
2. [Écrire l'image sur une carte SD](#2-écrire-limage-sur-une-carte-sd)
3. [Modifications appliquées à l'image](#3-modifications-appliquées-à-limage)
4. [Répertoires utiles sur la carte](#4-répertoires-utiles-sur-la-carte)
5. [Poste Ubuntu et connexion SSH à une borne](#5-poste-ubuntu-et-connexion-ssh-à-une-borne)

---

## 1. Construire une image

### 1.1 Prérequis

- Un poste **Linux** : le script utilise `losetup` et `mount`, et ne fonctionne pas sous macOS ni Windows. Pour préparer un poste Ubuntu, voir la [section 5](#5-poste-ubuntu-et-connexion-ssh-à-une-borne).
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
- **Les fichiers de manette** (`.cfg` RetroArch) et **les répertoires de samples** peuvent être placés n'importe où. Leurs chemins sont passés au script avec `-c` et `-S`.

### 1.3 Lancer la génération avec un script de jeu

Chaque jeu a un script prêt à l'emploi dans `work/target/`. Ces scripts utilisent des chemins relatifs, ils doivent donc être **lancés depuis ce répertoire** :

```
cd work/target
./generate-pacman-0.78-lf-mame2003.sh
```

L'image est produite dans `work/target/` sous le nom donné par `--output` (ici `pacman.mame2003.mo5.img`).

Pour ajouter un jeu, copiez un script existant et adaptez sa ligne de commande. Chaque script est autonome : il contient toutes les options du jeu et de la borne (affichage, son), une par ligne, sous leur forme longue pour rester lisibles. Exemple : `game_story_versailles_tetris_cocktail_mame2010.sh`.

```
# borne René Pierre (cocktail) : écran tourné de 90° (display_rotate=1), moniteur VGA 800x600, son sur la prise jack

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
```

### 1.4 Appeler directement le script

```
# image générique (le jeu est fourni plus tard sur une clé USB)
source/generate-image/generate-generic-image.sh --generic \
  --input <image d'origine> --output <image résultat> \
  [<options d'affichage et de son>]

# image spécifique (un jeu installé sur la carte)
source/generate-image/generate-generic-image.sh --specific <rom> \
  --input <image d'origine> --output <image résultat> \
  [--emulator <émulateur>] [--controller <fichier .cfg>] [--samples <répertoire>] \
  [<options d'affichage et de son>]

# modification d'une image générée ou d'une carte SD (voir §1.10)
source/generate-image/generate-generic-image.sh --modify <image.img ou /dev/sdX> \
  [--controller <fichier .cfg>] [<options d'affichage et de son>]

# options d'affichage et de son
  [--scanlines <scanlines>] [--no-smoothing] \
  [--reduce <pourcentage>:<largeur>x<hauteur>[:<alignement>] | --border <bordures>] \
  [--hdmi-mode <mode HDMI> | --tv-out <sortie composite>] [--rotate <degrés>] [--audio <sortie audio>]
```

Chaque option a une forme courte et une forme longue, au choix : `-s <rom>`, `--specific <rom>` ou `--specific=<rom>`. Les formes longues suivent la convention GNU (POSIX ne définit que les options courtes) : le script les traduit en options courtes avant de les lire avec `getopts`. Une forme longue inconnue, ou une valeur donnée à une option qui n'en prend pas (`--no-smoothing=oui`), arrête le script.

| Option | Rôle |
|---|---|
| `-i <image>`<br>`--input <image>` | Image RetroPie source. Elle n'est **jamais modifiée** : le script travaille sur une copie (`$HOME/out.img`). |
| `-o <image>`<br>`--output <image>` | Fichier résultat. Il est supprimé au début s'il existe déjà. |
| `-g`<br>`--generic` | Mode **générique** : modifications communes + lanceur clé USB. |
| `-s <rom>`<br>`--specific <rom>` | Mode **spécifique** : modifications communes + jeu installé + lanceur du jeu. |
| `-e <émulateur>`<br>`--emulator <émulateur>` | (avec `-s`) Émulateur forcé au lancement du jeu, par ex. `lr-mame2003` ou `lr-mame2010`. Le nom doit figurer dans `/opt/retropie/configs/<système>/emulators.cfg`. Recommandé : sans `-e`, runcommand peut demander de choisir un émulateur au démarrage (voir [§3.3](#33-mode-spécifique--s-rom)). |
| `-c <fichier .cfg>`<br>`--controller <fichier .cfg>` | (avec `-s`) Configuration de manette à installer. |
| `-S <répertoire>`<br>`--samples <répertoire>` | (avec `-s`) Répertoire de samples à installer à côté du jeu. |
| `-l <scanlines>`<br>`--scanlines <scanlines>` | Effet scanlines par shader RetroArch : `horizontal` (shader `crt-pi`) ou `vertical` (shader `crt-pi-vertical`). Voir [§1.8](#18-choisir-les-scanlines--l) pour choisir. Une autre valeur arrête le script avant toute modification. |
| `-n`<br>`--no-smoothing` | Désactive le lissage de l'image (`video_smooth`) : pixels nets. Utile pour les jeux en basse résolution très agrandis, comme la Game Boy. Implicite avec `-l`. |
| `-r <pourcentage>:<largeur>x<hauteur>[:<alignement>]`<br>`--reduce <pourcentage>:<largeur>x<hauteur>[:<alignement>]` | Réduit tout l'affichage (splash, EmulationStation, jeu) de ce pourcentage, avec une bordure noire autour, par overscan dans `config.txt`. La résolution est celle de l'écran de la borne, par exemple `-r 5:1024x768`. Elle sert à convertir le pourcentage en pixels : si l'écran a une autre résolution, la réduction réelle sera différente. L'image est centrée, sauf si un alignement la cale contre un bord ou dans un coin : `top`, `bottom`, `left`, `right`, `top-left`, `top-right`, `bottom-left` ou `bottom-right`, par exemple `-r 5:1024x768:bottom`. Le pourcentage peut être décimal (`2.5`) et doit être inférieur à 50. Ne se combine pas avec `-b`. |
| `-b left=N,right=N,top=N,bottom=N`<br>`--border left=N,right=N,top=N,bottom=N` | Bordures noires autour de tout l'affichage, en pixels, par overscan dans `config.txt`. Les côtés absents valent 0 : `-b left=20,right=20`. Des marges différentes décalent l'image, par exemple pour compenser un écran décalé. Ne se combine pas avec `-r`. |
| `-m <mode HDMI>`<br>`--hdmi-mode <mode HDMI>` | Force le mode de la sortie HDMI (voir le tableau ci-dessous). Ne se combine pas avec `-t`. |
| `-t pal\|ntsc`<br>`--tv-out pal\|ntsc` | Sortie vidéo composite en 4:3, pour un téléviseur cathodique. L'overscan par défaut du firmware est conservé (bordure de 32 px), sauf avec `-r` ou `-b`. Ne se combine pas avec `-m`. |
| `-R 90\|180\|270`<br>`--rotate 90\|180\|270` | Rotation de tout l'affichage, dans le sens horaire. |
| `-a jack\|hdmi`<br>`--audio jack\|hdmi` | Sortie du son. `jack` envoie le son sur la prise jack. `hdmi` garde la sortie par défaut de l'image (HDMI) : c'est le comportement sans `-a`. |
| `-M <image ou carte>`<br>`--modify <image ou carte>` | Modifie les réglages de manette, d'affichage et de son d'une image générée (`.img`) ou d'une carte SD (`/dev/sdX`). Voir [§1.10](#110-modifier-une-image-générée-ou-une-carte-sd---modify). |
| `-I <image ou carte>`<br>`--inspect <image ou carte>` | Lit l'état réel d'une image générée ou d'une carte SD, en lecture seule, et affiche ses réglages au format `nom=valeur`. Voir [§1.10](#110-modifier-une-image-générée-ou-une-carte-sd---modify). |
| `-B`<br>`--batch` | Sans pause : le script ne demande pas de vérifier l'image avant le démontage, et s'arrête sans attendre sur un système inconnu. Utilisé par l'éditeur de configuration. |
| `-d`<br>`--describe` | Décrit toutes les options au format JSON (noms, type, valeurs possibles, catégorie, incompatibilités) et s'arrête. L'éditeur de configuration construit son formulaire à partir de cette description. |
| `-h`<br>`--help` | Affiche la syntaxe d'appel et s'arrête. |

Il faut choisir exactement un mode : `-g`, `-s`, `-M` ou `-I`. `-e` et `-S` ne servent qu'en mode spécifique. `-i` et `-o` sont obligatoires pour une génération. Une valeur inconnue, ou une combinaison interdite (`-r` avec `-b`, `-t` avec `-m`), arrête le script avant toute modification.

Modes HDMI de `-m`. Le firmware connaît deux familles de modes : **moniteur** (norme VESA DMT, *Display Monitor Timings*, `hdmi_group=2`) et **téléviseur** (norme CEA-861, *Consumer Electronics Association*, `hdmi_group=1`). Le numéro `hdmi_mode` dépend de la famille. Source : documentation Raspberry Pi, *legacy config.txt options*.

| Valeur de `-m` | Famille | `hdmi_group` | `hdmi_mode` |
|---|---|---|---|
| `monitor_640x480_60hz` | moniteur (DMT) | 2 | 4 |
| `monitor_800x600_60hz` | moniteur (DMT) | 2 | 9 |
| `monitor_1024x768_60hz` | moniteur (DMT) | 2 | 16 |
| `monitor_1280x1024_60hz` | moniteur (DMT) | 2 | 35 |
| `tv_720p_60hz` | téléviseur (CEA) | 1 | 4 |
| `tv_1080p_60hz` | téléviseur (CEA) | 1 | 16 |

### 1.5 Déroulement d'une génération

1. L'image d'origine est copiée dans `$HOME/out.img`.
2. Cette copie est associée à un périphérique loop. La partition 2 est montée sur `work_temp/` dans le répertoire courant, la partition 1 sur `work_temp/boot`. Le mot de passe `sudo` est demandé.
3. Les modifications décrites dans la [section 3](#3-modifications-appliquées-à-limage) sont appliquées.
4. Les options utilisées sont enregistrées dans `/boot/mo5-options.conf` (voir [§3.1](#31-modifications-communes--g-et--s)).
5. **Le script fait une pause** : « Les modifications ont été appliquées… ». Vous pouvez alors inspecter l'image montée dans `work_temp/`. Appuyez sur une touche pour continuer. Avec `--batch`, il n'y a pas de pause.
6. Les partitions sont démontées, `work_temp/` est supprimé et le périphérique loop est libéré. Ce démontage a lieu aussi si le script s'arrête sur une erreur ou sur un Ctrl-C après le montage. `work_temp/` n'est jamais supprimé si un montage est encore actif.
7. `$HOME/out.img` est copié vers le fichier passé à `-o`. Si le script est lancé avec `sudo`, l'image de travail est celle de l'utilisateur qui a lancé `sudo`, et l'image résultat lui appartient.

Le script fait aussi une pause, puis s'arrête, si le système de la ROM est inconnu, c'est-à-dire si `roms/<système>` n'existe pas dans l'image. Sans `--batch`, le script est interactif et n'est pas prévu pour tourner sans surveillance.

Le journal est écrit dans `source/generate-image/generate-generic-image.log`.

### 1.6 Nettoyer après un arrêt brutal

Le script démonte l'image lui-même s'il s'arrête sur une erreur ou sur un Ctrl-C. Mais si le démontage échoue (fichier ouvert dans `work_temp/`, par exemple) ou si le processus est tué (`kill -9`, coupure du terminal), des montages ou un périphérique loop peuvent rester actifs. Pour les libérer :

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

### 1.7 Réglages des bornes

Le générateur ne connaît aucune borne : les réglages d'affichage et de son sont des options, écrites dans chaque script de `work/target/`. Options utilisées aujourd'hui :

| Borne | Options | Scripts |
|---|---|---|
| Arcade1Up | `--border left=20,right=20 --audio jack` | `generate-pocky-rockey-snes-arcade1un.sh` |
| Borne Pac-Man MO5 | aucune | `generate-pacman-0.78-lf-mame2003.sh` |
| Table cocktail René Pierre | `--rotate 90 --hdmi-mode monitor_800x600_60hz --audio jack` | `game_story_versailles_tetris_cocktail_mame2010.sh`, `game_story_versailles_spaceinvaders_II_cocktail_mame2003.sh` |
| TV en sortie composite (Game Story Versailles) | `--tv-out pal` | `GameStoryVersailles_pacman-0.78-mame2003.sh`, `GameStoryVersailles_space-invaders-0.35b-lr-mame2003.sh` |

Pour un nouveau jeu sur une borne existante, reprenez les options de ce tableau.

**À vérifier sur la borne René Pierre :** la rotation est de 90° (`display_rotate=1`), mais d'anciens commentaires des scripts parlent de 270° (`display_rotate=3`).

**Borne Pac-Man MO5 :** l'ancien profil prévoyait un viewport RetroArch de 366×476 px à x=149, y=5, pour compenser un écran décalé. Il n'a jamais eu d'effet, car les lignes visées n'existent pas dans l'image d'origine. Si l'écran fait 640×480, l'équivalent serait `--border left=149,right=125,top=5`, à essayer sur la borne.

### 1.8 Choisir les scanlines (`-l`)

Choisissez selon l'orientation du **jeu d'origine**, pas selon l'écran de la borne :

- **Jeu horizontal** (image plus large que haute) : `-l horizontal`. Cela couvre toutes les consoles (NES, SNES, PC Engine…) et la plupart des jeux d'arcade.
- **Jeu vertical** (image plus haute que large, l'écran de la borne d'arcade était monté tourné de 90°) : `-l vertical`.

**Pourquoi.** Sur la borne d'origine, les lignes du tube cathodique suivaient toujours le grand côté du tube. Pour un jeu vertical, le moniteur était tourné, donc le joueur voyait des lignes **verticales**. `lr-mame2003` produit l'image d'un jeu vertical déjà dans le bon sens, en portrait. Le shader doit donc tracer ses lignes dans le sens des colonnes : c'est le rôle de `crt-pi-vertical`. La rotation de l'écran par `-R` (borne René Pierre) s'applique ensuite à l'image entière, scanlines comprises. Elle ne change donc pas le choix.

**Jeux du dépôt.** Ce classement n'a pas été vérifié dans les fichiers ROM.

| Jeu | Orientation | Option |
|---|---|---|
| Pac-Man, Space Invaders, Space Invaders II cocktail, Tetris cocktail (Atari), Kiki Kaikai (arcade) | Vertical | `vertical` |
| Astérix, Bubble Bobble, Snow Bros, Street Fighter II Turbo | Horizontal | `horizontal` |
| Donkey Kong NES, Pocky & Rocky, jeux PC Engine | Horizontal | `horizontal` |

**En cas de doute :**
- dans MAME, un jeu vertical est marqué `ROT90` ou `ROT270` dans ses informations de pilote ; un jeu horizontal est marqué `ROT0` ;
- à l'écran, regardez de près : sur un jeu vertical, les lignes doivent aller de haut en bas, telles que le joueur les voit. Si elles coupent les sprites dans le mauvais sens, changez d'option ;
- exception : si on active le mode « TATE » de MAME, qui laisse l'image non tournée, la règle s'inverse. Ce mode n'est pas utilisé dans ce dépôt.

Pour une sortie composite vers un téléviseur cathodique (`-t`), n'utilisez pas `-l` : le téléviseur produit déjà ses propres scanlines.

N'utilisez pas `-l` non plus pour les consoles portables à écran LCD (Game Boy…) : elles n'ont jamais eu de scanlines.

### 1.9 Créer la configuration d'une manette depuis le PC

Branchez la manette, ou l'encodeur USB de la borne, sur le PC Linux, puis lancez :

```
source/controller-config/create-controller-cfg.py -l                       # liste les manettes branchées
source/controller-config/create-controller-cfg.py -o "work/origin/game-to-install/<système>/<nom>.cfg"
```

L'outil demande chaque commande dans l'ordre : directions, A, B, X, Y, L, R, L2, R2, Select, Start. Appuyez sur la commande demandée, ou sur Entrée si elle n'existe pas. Le fichier écrit est prêt pour l'option `-c`.

- Le PC et le Pi utilisent le même pilote du noyau Linux. L'outil numérote les boutons et les axes comme le pilote `udev` de RetroArch, donc les numéros sont les mêmes sur la borne.
- Le fichier contient le nom du périphérique (`input_device`) et ses identifiants USB (`input_vendor_id`, `input_product_id`).
- S'il y a plusieurs manettes branchées, l'outil demande laquelle utiliser. On peut aussi la désigner avec `-d /dev/input/eventN`.
- Si aucune manette n'est trouvée alors qu'elle est branchée, relancez avec `sudo` : les droits de `/dev/input/event*` dépendent de la distribution.

RetroArch choisit le fichier d'après `input_device`, pas d'après le nom du fichier. Si l'encodeur de la borne et vos manettes de test portent le même nom (par ex. « Mega World »), une même image ne peut être correcte que pour l'un des deux.

---

### 1.10 Modifier une image générée ou une carte SD (`--modify`)

```
# image générée
source/generate-image/generate-generic-image.sh --modify work/target/pacman.mame2003.mo5.img \
  --border left=149,right=125,top=5

# carte SD gravée, insérée dans le PC
source/generate-image/generate-generic-image.sh --modify /dev/sdb --rotate 270 --hdmi-mode monitor_800x600_60hz --audio jack
```

`--modify` applique à nouveau les réglages de **manette, d'affichage et de son**, directement sur l'image ou sur la carte : il n'y a ni copie ni nouvelle image. Le jeu, l'émulateur et les samples ne changent pas. Les options de génération (`-s`, `-e`, `-S`, `-i`, `-o`) sont refusées.

- **Tous les réglages d'affichage et de son sont remplacés** par ceux donnés sur la ligne de commande. Un réglage absent revient à sa valeur par défaut : par exemple, sans `--audio jack`, le son revient sur la sortie HDMI. Pour changer un seul réglage, redonnez aussi les autres. Ils sont dans `/boot/mo5-options.conf`, que l'éditeur de configuration relit.
- **La manette :** avec `--controller`, la nouvelle configuration remplace celle installée à la génération. Sans `--controller`, la manette ne change pas.
- **`/boot/mo5-options.conf`** est mis à jour, avec la date de modification. Les options de génération (jeu, émulateur) y sont conservées.
- **Une image** ne doit pas être déjà associée à un périphérique loop (ouverte par un autre programme) : le script refuse de la modifier.
- **Une carte SD** doit être indiquée comme disque entier (`/dev/sdb`, pas `/dev/sdb1`). Par sécurité, le script refuse un disque qui n'est ni amovible ni USB, ou qui contient le système en cours d'exécution. Les partitions montées automatiquement par le bureau à l'insertion sont démontées d'abord.
- Le mot de passe `sudo` est demandé, comme pour une génération.

Une image générée avant l'enregistrement des options n'a pas de `/boot/mo5-options.conf`. `--modify` fonctionne quand même, avec un avertissement.

**Lire les réglages (`--inspect`)**

```
source/generate-image/generate-generic-image.sh --inspect /dev/mmcblk0
```

`--inspect` relit l'**état réel** de l'image ou de la carte, sur ses deux partitions, en lecture seule. Il lit `config.txt` (overscan, rotation, mode HDMI, sortie composite), `/etc/asound.conf` (son), `retroarch.cfg` (scanlines, lissage), les manettes installées et le lanceur (jeu, système, émulateur). Une image est associée à un périphérique loop en lecture seule. Une partition déjà montée par le bureau est lue sur place, sans être démontée. Le mot de passe `sudo` est demandé.

Il compare ensuite cet état aux options enregistrées dans `/boot/mo5-options.conf`, en recalculant leur effet avec le même code que la génération :
- **Conforme :** les réglages sont affichés sous leur forme d'origine, par exemple `reduce=5:1024x768:bottom`.
- **Écart** (modification à la main en SSH, par exemple) : l'état réel est affiché, en bordures en pixels pour l'overscan, et la ligne `differs=` liste les réglages concernés.
- **Pas de `mo5-options.conf` :** l'état réel est affiché. Une réduction en pourcentage apparaît en bordures (`border=left=51,right=51,top=38,bottom=38`).

Les lignes `note=` signalent un réglage que les options ne savent pas produire (`asound.conf` personnalisé, autre shader, mode HDMI non géré…). Les informations s'affichent sur la sortie standard, et les traces sur la sortie d'erreur.

### 1.11 Éditeur de configuration (interface graphique)

```
python3 source/config-editor/mo5-config-editor.py
```

Prérequis : un poste Ubuntu avec bureau, Python 3 et PySide6 (Qt) :

```
sudo apt install python3-pyside6.qtwidgets
```

L'éditeur est une interface du script de génération : il lui demande la liste de ses options (`--describe`) et construit ses formulaires à partir d'elle. Chaque champ affiche le titre de l'option et son nom en ligne de commande (`--rotate`) ; sa description complète apparaît en infobulle. Une nouvelle option du script apparaît donc dans l'éditeur sans le modifier. Les valeurs possibles sont proposées en liste déroulante, et un champ rempli désactive les champs avec lesquels il ne se combine pas (`--reduce` et `--border`, `--tv-out` et `--hdmi-mode`).

**Page « Générer une image »**
- Le type d'image (générique ou spécifique avec sa ROM), les images, le jeu, la manette, l'affichage et le son.
- **Charger un script…** remplit le formulaire à partir d'un script de `work/target/`. **Enregistrer comme script…** écrit un script autonome au même format. Les chemins sont affichés et enregistrés relativement à `work/target/`, comme dans les scripts.
- **Générer l'image** lance le script avec `--batch`, sans pause. Le journal s'affiche en bas de la fenêtre. **Arrêter**, dans la barre d'état, interrompt la génération, et l'image est alors démontée proprement.

**Page « Modifier une image ou une carte SD »**
- Choisir une image (**Parcourir…**) ou une carte SD insérée (liste des disques amovibles ou USB qui contiennent une carte, sans le disque du système).
- Les réglages sont lus en deux temps. D'abord, sans mot de passe, ceux de la partition de démarrage (`mo5-options.conf`, ou `config.txt` pour une image plus ancienne). Ensuite, après le mot de passe `sudo`, l'**état réel** de toute l'image avec `--inspect` : son, scanlines, lissage, manettes installées, jeu. Un encadré résume le jeu, les manettes installées et la conformité avec `mo5-options.conf`. Il s'affiche en orange quand l'image a été modifiée à la main depuis la génération, ou quand un réglage est à vérifier. Si le mot de passe n'est pas donné, seule la première lecture est affichée, avec un avertissement.
- **Appliquer les réglages** lance `--modify` avec **tous** les réglages affichés : « Par défaut » ou un champ vide remet la valeur par défaut. Le champ Manette indique la manette installée ; il ne la remplace que si un nouveau fichier `.cfg` est choisi. Les réglages sont relus après la modification.

Le mot de passe `sudo` est demandé une fois, vérifié, puis gardé en mémoire jusqu'à la fermeture de l'éditeur. Il n'est pas demandé si `sudo` n'en a pas besoin.

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

Elles sont faites par la fonction `apply_common_modifications_on_SD`. Certaines dépendent des options d'affichage et de son.

#### `/boot/cmdline.txt` — démarrage silencieux

| Changement | Condition |
|---|---|
| Remplace la **première** occurrence de `console=tty1` par `console=tty3 quiet logo.nologo loglevel=3 vt.global_cursor_default=0 plymouth.enable=0` | Toujours |

Les messages du noyau sont envoyés sur tty3 (invisible) et réduits au minimum (`quiet`), le logo framboise est masqué, seuls les messages d'erreur sont affichés et le curseur clignotant est caché. `plymouth.enable=0` désactive l'écran de démarrage graphique Plymouth, s'il est installé.

#### `/boot/config.txt` — affichage

Lignes modifiées :

| Changement | Condition |
|---|---|
| Décommente `#disable_overscan=1` → `disable_overscan=1` (pas de bordure noire) | Toujours **sauf** avec `-t` |

Avec `-t` (sortie composite), `disable_overscan` reste commenté : le firmware applique son overscan par défaut, 32 px de chaque côté pour un mode télévision SD. Un téléviseur cathodique rogne lui-même les bords de l'image, et cette marge évite de perdre le bord du jeu.

Avec `-r <pourcentage>:<largeur>x<hauteur>[:<alignement>]` ou `-b <bordures>`, toutes les lignes `disable_overscan`, `overscan_left`, `overscan_right`, `overscan_top`, `overscan_bottom` et `overscan_scale` existantes, commentées ou non, sont supprimées. Ces lignes sont ensuite ajoutées à la fin du fichier :

```
disable_overscan=0
overscan_left=<marge gauche>
overscan_right=<marge droite>
overscan_top=<marge haut>
overscan_bottom=<marge bas>
overscan_scale=1
```

Avec `-b`, les marges sont celles données en pixels. Avec `-r` sans alignement, chaque marge vaut `largeur × pourcentage / 200` (gauche et droite) ou `hauteur × pourcentage / 200` (haut et bas), arrondi au pixel. Par exemple, `-r 5:1024x768` donne 26 px à gauche et à droite et 19 px en haut et en bas. Un alignement met toute la marge du côté opposé : avec `-r 5:1024x768:bottom`, la marge haute vaut 38 px et la marge basse 0, et l'image reste centrée horizontalement. Avec `bottom-left`, on a en plus 0 à gauche et 52 px à droite. `overscan_scale=1` applique aussi la réduction à l'image de RetroArch.

Lignes ajoutées à la fin du fichier, dans cet ordre :

| Ligne ajoutée | Rôle | Condition |
|---|---|---|
| `disable_splash=1` | Supprime l'écran arc-en-ciel au démarrage | Toujours |
| `avoid_warnings=1` | Masque les icônes de sous-tension / surchauffe | Toujours |
| `boot_delay=0` | Supprime l'attente du firmware avant le chargement du noyau | Toujours |
| `dtoverlay=disable-bt` | Désactive le Bluetooth | Toujours |
| `display_rotate=1`, `2` ou `3` | Rotation de l'affichage de 90°, 180° ou 270° dans le sens horaire | `-R 90`, `-R 180` ou `-R 270` |
| `hdmi_group=…` et `hdmi_mode=…` | Mode HDMI forcé (voir le tableau des modes au [§1.4](#14-appeler-directement-le-script)) | `-m <mode HDMI>` |
| `enable_tvout=1` | Active la sortie vidéo composite | `-t` |
| `sdtv_mode=2` ou `0` | Sortie composite en PAL ou en NTSC | `-t pal` ou `-t ntsc` |
| `sdtv_aspect=1` | Format 4:3 | `-t` |

#### `/boot/ssh` — accès SSH

| Changement | Condition |
|---|---|
| Crée le fichier vide `/boot/ssh` : le service SSH démarre au premier boot | Toujours |

#### `/boot/mo5-options.conf` — options utilisées

Ce fichier enregistre les options de génération et les réglages, une ligne `nom_long=valeur` par option donnée (pour un fichier, son nom seulement), plus la version du générateur et les dates. Il est sur la partition `/boot` (FAT), donc lisible depuis n'importe quel PC. L'éditeur de configuration le relit pour afficher les réglages d'une image ou d'une carte. Exemple :

```
# Options utilisées par generate-generic-image.sh, relues par l'éditeur de configuration
# Ne pas modifier à la main : utiliser --modify
generator_version=13d7ec7
specific=Legend of Zelda, The - Link's Awakening DX (France) (Rev 1) (SGB Enhanced) (GB Compatible).zip
emulator=lr-gambatte
controller=Mega World.cfg
no-smoothing=ON
reduce=5:1024x768:bottom
generated=2026-10-18T09:03:29Z
```

#### `/opt/retropie/configs/all/runcommand.cfg` — lanceur RetroPie

| Changement | Condition |
|---|---|
| Sur la ligne `disable_joystick` : `"0"` → `"1"` (le menu runcommand ne se pilote plus au joystick) | Toujours |
| Sur la ligne `disable_menu` : `"0"` → `"1"` (plus de menu « Press a button to configure » avant le lancement) | Toujours |

#### `/opt/retropie/emulators/retroarch/retroarch.cfg` — configuration RetroArch par défaut

| Changement | Condition |
|---|---|
| Les lignes `video_font_enable` existantes, commentées ou non, sont supprimées, puis `video_font_enable = "false"` est ajouté à la fin du fichier (pas de messages à l'écran) | Toujours |

#### `/opt/retropie/configs/all/retroarch.cfg` — configuration RetroArch commune

| Changement | Condition |
|---|---|
| Les lignes `video_font_enable` existantes, commentées ou non, sont supprimées, puis `video_font_enable = "false"` est ajouté à la fin du fichier | Toujours |
| Les lignes `video_smooth` existantes, commentées ou non, sont supprimées, puis `video_smooth = "false"` est ajouté à la fin du fichier (pixels nets) | `-n` ou `-l` |

Sans `-n` ni `-l`, `video_smooth` n'est pas modifié : RetroArch garde son réglage par défaut, le lissage bilinéaire.
| Les lignes `video_shader_enable` et `video_shader` existantes, commentées ou non, sont supprimées, puis ces lignes sont ajoutées à la fin du fichier :<br>`video_shader_enable = "true"`<br>`video_shader = "/opt/retropie/configs/all/retroarch/shaders/crt-pi.glslp"` | `-l horizontal` |
| Même chose avec `video_shader = "/opt/retropie/configs/all/retroarch/shaders/crt-pi-vertical.glslp"` | `-l vertical` |

Avec `-l`, le script vérifie que le fichier `.glslp` existe dans l'image. S'il est absent, il s'arrête et démonte l'image sans produire de résultat.

#### Splash screen

| Changement | Condition |
|---|---|
| `/etc/splashscreen.list` est vidé (taille 0) : aucune vidéo ou image de démarrage RetroPie | Toujours |

#### `/etc/asound.conf` — sortie audio

| Changement | Condition |
|---|---|
| Le fichier est **écrasé** avec :<br>`pcm.!default {type hw card 1}`<br>`ctl.!default {type hw card 1}`<br>Le son passe par la carte 1 (jack) au lieu de la carte 0 (HDMI) | `-a jack` |

Sans `-a jack`, le fichier n'est pas touché.

#### Messages console

| Changement | Condition |
|---|---|
| `/etc/issue` est vidé (plus de bannière avant le login) | Toujours |
| `/etc/motd` est vidé (plus de message du jour après le login) | Toujours |
| Dans `/home/pi/.bashrc`, la ligne commençant par `retropie_welcome` est commentée (plus d'écran d'accueil RetroPie en texte) | Toujours |
| Dans `/etc/rc.local`, ajout **avant** `exit 0` de :<br>`sudo sh -c "TERM=linux setterm -foreground black -clear all >/dev/tty0"`<br>Le texte de la console devient noir sur noir et l'écran est effacé | Toujours |
| Dans `/etc/rc.local`, suppression du bloc qui affiche l'adresse IP (`_IP=$(hostname -I)` … `fi`) | Toujours |

#### Démarrage plus rapide

| Changement | Condition |
|---|---|
| Suppression de `/etc/systemd/system/dhcpcd.service.d/wait.conf` (« Wait for network at boot »). Sans réseau, la connexion automatique, donc le jeu, attendait une adresse IP jusqu'à 30 s environ. dhcpcd tourne désormais en arrière-plan : SSH reste disponible dès qu'un réseau est branché | Toujours |
| Désactivation des services inutiles sur une borne, par suppression de leurs liens dans `/etc/systemd/system/` (équivalent de `systemctl disable`) :<br>Bluetooth : `hciuart`, `bluetooth` (+ `dbus-org.bluez.service`)<br>Samba : `smbd`, `nmbd`<br>Découverte réseau : `avahi-daemon` (service, socket, `dbus-org.freedesktop.Avahi.service`)<br>Fichier d'échange : `dphys-swapfile`<br>Divers : `triggerhappy` (service, socket), `rsync`, `rpi-eeprom-update`, `nfs-client.target`<br>Maintenance : timers `apt-daily`, `apt-daily-upgrade`, `man-db` | Toujours |

Un service déjà désactivé ou absent de l'image est signalé par un avertissement dans le journal, sans arrêter le script.

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

Le jeu est toujours lancé directement : EmulationStation n'est jamais démarré à la place du jeu, même si une manette n'est pas configurée.

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
| Le répertoire donné est copié récursivement vers `/home/pi/RetroPie/roms/<système>/samples` (propriétaire : celui de `roms`) | `-S <répertoire>` |

#### Manette

| Changement | Condition |
|---|---|
| Le fichier `.cfg` est copié dans `/opt/retropie/configs/all/retroarch/autoconfig/` sous le même nom (propriétaire : celui de ce répertoire, `pi`). Fonctionne aussi en mode générique | `-c <fichier .cfg>` |

### 3.4 Points d'attention

Ces remarques viennent de la lecture du script. Elles ne changent pas son comportement, mais elles aident à comprendre le résultat.

- **`display_rotate` :** la documentation Raspberry Pi le dit obsolète au profit de `display_hdmi_rotate`. Il fonctionne avec le firmware de l'image d'origine (RetroPie sur Raspberry Pi OS Buster). Les options `config.txt` de ce type ne fonctionnent plus à partir de Raspberry Pi OS Bookworm.
- **Pas de fichier d'échange :** `dphys-swapfile` est désactivé. Sur un Pi 3 (1 Go), c'est sans conséquence pour ces jeux. Sur un Pi Zero 2 W (512 Mo), un émulateur gourmand en mémoire (par ex. `lr-mame2010`) pourrait manquer de mémoire. À tester sur la borne.
- **Plus de partage Samba ni de `retropie.local` :** pour accéder à la borne, utilisez SSH avec son adresse IP.
- **Remplacements limités :** les remplacements de `cmdline.txt`, de l'overscan et des noms dans `autostart.sh` ne portent que sur la **première** occurrence trouvée dans le fichier (`sed '0,/motif/ s//.../'`). Les options `-r` et `-b` font exception : elles suppriment toutes les lignes d'overscan avant d'ajouter les leurs.
- **Scanlines et `video_smooth` :** avec `-l`, le lissage est désactivé, car il rendrait les lignes floues. Le choix du shader dépend de l'orientation du jeu d'origine, pas de celle de l'écran (voir [§1.8](#18-choisir-les-scanlines--l)).
- **Scanlines et sortie composite :** `-l` est déconseillé avec `-t`. Un téléviseur cathodique produit déjà ses propres scanlines.

---

## 4. Répertoires utiles sur la carte

Cette section liste les fichiers à connaître pour faire des réglages et des tests en direct sur une borne par SSH (voir la [section 5](#5-poste-ubuntu-et-connexion-ssh-à-une-borne) pour la connexion). Les modifications faites ainsi sur une borne sont perdues à la prochaine génération de l'image. Pour les garder, reportez-les dans `generate-generic-image.sh` ou dans les fichiers de `work/origin/`.

L'utilisateur est `pi`. Le mot de passe par défaut de RetroPie est `raspberry`, sauf s'il a été changé dans l'image d'origine. Les fichiers de `/boot` et `/etc` se modifient avec `sudo`.

### 4.1 Démarrage et matériel (partition `/boot`)

| Fichier | Contenu | Prise en compte |
|---|---|---|
| `/boot/config.txt` | Affichage (overscan, rotation, mode HDMI, sortie composite), Bluetooth, `boot_delay` | Au redémarrage |
| `/boot/cmdline.txt` | Paramètres du noyau (console, messages de démarrage). **Une seule ligne** : ne pas ajouter de retour à la ligne | Au redémarrage |
| `/boot/mo5-options.conf` | Options utilisées pour générer ou modifier l'image (voir [§3.1](#31-modifications-communes--g-et--s)) | Lu par l'éditeur de configuration |

### 4.2 Lancement du jeu

| Fichier | Contenu |
|---|---|
| `/opt/retropie/configs/all/autostart.sh` | Lanceur exécuté à la connexion automatique de `pi` sur l'écran : jeu, émulateur, système (voir [§3.3](#33-mode-spécifique--s-rom)) |
| `/etc/profile.d/10-retropie.sh` | Appelle `autostart.sh` quand `pi` se connecte sur l'écran (tty1) |
| `/opt/retropie/configs/<système>/emulators.cfg` | Émulateurs installés pour un système, avec leur ligne de commande, et l'émulateur par défaut (`default`) |
| `/opt/retropie/configs/all/runcommand.cfg` | Réglages de runcommand (menu de lancement, joystick) |
| `/etc/rc.local` | Commandes lancées en fin de démarrage (effacement de la console) |

### 4.3 RetroArch (image, son, manettes)

| Fichier ou répertoire | Contenu |
|---|---|
| `/opt/retropie/configs/all/retroarch.cfg` | Réglages RetroArch **communs à tous les systèmes** : lissage, shader, messages à l'écran… |
| `/opt/retropie/configs/<système>/retroarch.cfg` | Réglages **propres à un système**. Ils ne sont pris en compte que s'ils sont placés **au-dessus** de la ligne `#include "/opt/retropie/configs/all/retroarch.cfg"` |
| `/opt/retropie/emulators/retroarch/retroarch.cfg` | Configuration par défaut de RetroArch |
| `/opt/retropie/configs/all/retroarch-core-options.cfg` | Options des émulateurs (cores) : palette Game Boy, réglages MAME… |
| `/opt/retropie/configs/all/retroarch/autoconfig/` | Configurations des manettes (`.cfg`). `/opt/retropie/configs/all/retroarch-joypads` est un lien vers ce répertoire |
| `/opt/retropie/configs/all/retroarch/shaders/` | Shaders, dont `crt-pi.glslp` et `crt-pi-vertical.glslp` (option `-l`) |
| `/etc/asound.conf` | Sortie son par défaut (jack ou HDMI) |

### 4.4 Jeux et sauvegardes

| Répertoire | Contenu |
|---|---|
| `/home/pi/RetroPie/roms/<système>/` | ROMs. Les **sauvegardes des jeux** (`.srm`, par exemple pour Zelda) sont écrites à côté de la ROM |
| `/home/pi/RetroPie/BIOS/` | BIOS des systèmes qui en ont besoin (PC Engine CD, PlayStation…) |
| `/media/usb0/` | Clé USB, en mode générique |

### 4.5 Système

| Fichier ou répertoire | Contenu |
|---|---|
| `/etc/systemd/system/` | Services activés au démarrage (liens dans `*.target.wants/`). Voir [§3.1](#31-modifications-communes--g-et--s) pour ceux qui sont désactivés |
| `/etc/systemd/system/getty@tty1.service.d/autologin.conf` | Connexion automatique de `pi` sur l'écran |
| `/etc/dhcpcd.conf` | Configuration réseau (DHCP) |

### 4.6 Tester une modification sans redémarrer

1. Arrêtez le jeu : `killall retroarch`.
2. Modifiez le fichier, par exemple `nano /opt/retropie/configs/all/retroarch.cfg`.
3. Relancez la connexion automatique de l'écran, ce qui relance `autostart.sh` et donc le jeu :
   ```
   sudo systemctl restart getty@tty1
   ```

Après la modification d'un fichier de service (`/etc/systemd/system/...`, par exemple `autologin.conf`), rechargez la configuration de systemd avant de relancer le service. Sinon, systemd affiche l'avertissement « changed on disk. Run 'systemctl daemon-reload' » et garde l'ancienne version :
```
sudo systemctl daemon-reload
sudo systemctl restart getty@tty1
```

Les fichiers de `/boot` ne sont pris en compte qu'après un redémarrage : `sudo reboot`.

Pour diagnostiquer :

| Commande | Usage |
|---|---|
| `systemd-analyze` et `systemd-analyze critical-chain getty@tty1.service` | Durée du démarrage et ce qui retarde le lancement du jeu |
| `systemctl list-unit-files --state=enabled` | Services activés |
| `journalctl -b` | Journal du démarrage en cours |
| `cat /dev/shm/runcommand.log` | Journal du dernier lancement par runcommand (seulement sans option `-e`) |
| `grep Name /proc/bus/input/devices` | Nom des manettes branchées (la valeur de `input_device`) |
| `jstest --event /dev/input/js0` | Numéros des boutons et axes d'une manette |
| `vcgencmd measure_temp` et `vcgencmd get_throttled` | Température, et sous-tension (`0x0` = aucun problème) |

---

## 5. Poste Ubuntu et connexion SSH à une borne

### 5.1 Préparer le poste Ubuntu

Les outils nécessaires sont presque tous installés d'origine sur Ubuntu. Pour être sûr de les avoir :

```
sudo apt install git util-linux e2fsprogs python3 openssh-client
```

| Paquet | Utilisé pour |
|---|---|
| `util-linux` | `losetup`, `mount`, `lsblk` : génération des images et écriture sur carte SD |
| `e2fsprogs` | `debugfs` : lire le contenu d'une image sans la monter (facultatif) |
| `python3` | `create-controller-cfg.py` (configuration des manettes) |
| `openssh-client` | `ssh` et `scp` vers les bornes |

Il faut aussi un compte avec les droits `sudo`.

Pour `create-controller-cfg.py`, Ubuntu donne normalement accès aux manettes à l'utilisateur connecté à la session graphique. Si l'outil ne trouve pas la manette, lancez-le depuis la session graphique, pas par SSH, ou avec `sudo`.

### 5.2 Ce qu'il faut savoir sur le réseau des bornes

- La borne obtient son adresse par DHCP (`dhcpcd`). Elle annonce le nom `retropie` au serveur DHCP.
- `avahi-daemon` est désactivé dans les images (voir [§3.1](#31-modifications-communes--g-et--s)) : **le nom `retropie.local` ne fonctionne pas**. Il faut utiliser l'adresse IP.
- L'adresse IP n'est plus affichée à l'écran au démarrage.
- La borne n'attend plus le réseau pour lancer le jeu : on peut brancher le câble avant ou après le démarrage.

### 5.3 Câble Ethernet direct entre le PC et la borne (recommandé en exposition)

Le PC sert de serveur DHCP pour la borne, grâce au mode « partagé » de NetworkManager. Il n'y a besoin ni de routeur ni de box.

Le plus simple est d'utiliser **un adaptateur Ethernet USB dédié aux bornes**. La prise Ethernet principale du PC reste alors sur le réseau habituel, et la configuration partagée ne s'applique qu'à cet adaptateur.

#### Configuration (une seule fois)

1. Branchez l'adaptateur USB et repérez son interface. Un adaptateur USB s'appelle `enx…` suivi de son adresse MAC, par ex. `enx9cebe80cf5a9` :
   ```
   nmcli device status
   ```
   **L'interface d'un adaptateur USB n'apparaît que lorsqu'il est branché.**
2. Créez une connexion partagée sur cette interface, activée automatiquement dès que l'adaptateur est branché :
   ```
   nmcli connection add type ethernet ifname <interface> con-name borne-mo5 \
     ipv4.method shared ipv6.method ignore connection.autoconnect yes
   ```
   On peut aussi le faire dans l'interface graphique : Paramètres → Réseau → l'adaptateur → IPv4 → « Partagée avec d'autres ordinateurs ». La connexion porte alors un autre nom, souvent celui de l'interface : `nmcli connection show` l'affiche. Vérifiez qu'elle se réactive toute seule :
   ```
   nmcli connection modify <nom de la connexion> connection.autoconnect yes
   ```

#### À chaque utilisation

1. Branchez l'adaptateur USB sur le PC, puis le câble entre l'adaptateur et la borne.
2. Vérifiez que la connexion partagée est active :
   ```
   nmcli device status
   ```
   La ligne de l'adaptateur doit indiquer `connected` avec le nom de la connexion partagée. Si elle indique `disconnected`, activez-la : `nmcli connection up <nom de la connexion>`. Le PC prend alors l'adresse `10.42.0.1`.

   Pour vérifier le lien physique, `cat /sys/class/net/<interface>/carrier` doit afficher `1`, et `cat /sys/class/net/<interface>/speed` affiche `100` avec un Pi 2 ou 3. Le voyant de certains adaptateurs ne clignote pas même quand le lien est actif : ce n'est pas un signe de panne.
3. Démarrez (ou redémarrez) la borne, pour qu'elle demande une adresse au PC. Après quelques secondes, retrouvez son adresse :
   ```
   ip neigh show dev <interface> | grep -v FAILED
   ```
   L'adresse MAC d'un Raspberry Pi commence par `b8:27:eb`, `dc:a6:32`, `e4:5f:01`, `d8:3a:dd` ou `2c:cf:67`. Les baux DHCP du PC donnent aussi l'adresse et le nom (`retropie`), mais ils ne sont lisibles qu'avec `sudo` :
   ```
   sudo cat /var/lib/NetworkManager/dnsmasq-<interface>.leases
   ```
   NetworkManager distribue les adresses de `10.42.0.10` à `10.42.0.254`. Une borne garde en général la même adresse d'un démarrage à l'autre.
4. Connectez-vous :
   ```
   ssh pi@10.42.0.x
   ```

#### En cas de problème

- **La borne n'apparaît pas dans `ip neigh` :** la connexion partagée n'était sans doute pas active quand la borne a démarré. Activez-la, puis redémarrez la borne. Le premier démarrage d'une carte neuve redémarre aussi une fois tout seul (agrandissement de la partition) : attendez que le jeu soit affiché.
- **Le pare-feu `ufw`**, s'il est activé sur le PC, peut bloquer le DHCP. Autorisez l'interface avec `sudo ufw allow in on <interface>`.
- **Pour savoir si SSH répond sans se connecter :** `ssh -o ConnectTimeout=5 pi@10.42.0.x true`. Un message `Connection timed out` indique un problème réseau. Une demande de mot de passe indique que SSH fonctionne.

### 5.4 Borne branchée sur un réseau avec box ou routeur

La borne reçoit son adresse de la box. Pour la trouver :

- consultez la liste des appareils connectés de la box : la borne apparaît sous le nom `retropie` ;
- ou balayez le réseau depuis le PC (paquet `nmap`) :
  ```
  sudo nmap -sn 192.168.1.0/24      # adapter au réseau local
  ```
  La borne apparaît avec un fabricant « Raspberry Pi » à côté de son adresse MAC.

### 5.5 Astuces SSH

- **Message « REMOTE HOST IDENTIFICATION HAS CHANGED » :** chaque carte génère ses propres clés SSH au premier démarrage. Si une autre carte a déjà eu la même adresse IP, effacez l'ancienne clé avant de vous connecter :
  ```
  ssh-keygen -R 10.42.0.x
  ```
- **Ne plus taper le mot de passe :** `ssh-copy-id pi@10.42.0.x`. Ce réglage est propre à la carte : il est perdu si la carte est regénérée.
- **Copier des fichiers**, par exemple pour récupérer les configurations de manettes de la borne :
  ```
  scp "pi@10.42.0.x:/opt/retropie/configs/all/retroarch/autoconfig/*.cfg" .
  ```
- **Arrêter le jeu pour travailler sur la borne :** `killall retroarch`. Pour éteindre proprement la borne : `sudo poweroff`.
