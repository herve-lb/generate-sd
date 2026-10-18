#!/usr/bin/env python3
"""MO5 configuration editor (Qt).

Graphical front-end of generate-generic-image.sh:
- generate an image, with a form built from the options described by the generator (--describe),
  and load or save the generation scripts of work/target;
- read and modify the controller, display and sound settings of a generated image or of an SD card.

The generator stays the single source of truth: this program knows no option by itself.
Requires PySide6 (Ubuntu: sudo apt install python3-pyside6.qtwidgets).
"""

import os
import shlex
import struct
import subprocess
import sys
import tempfile

try:
    import PySide6  # noqa: F401
except ModuleNotFoundError:
    sys.exit("PySide6 (Qt pour Python) n'est pas installé. Sur Ubuntu :\n"
             "    sudo apt install python3-pyside6.qtwidgets")

from PySide6.QtCore import QProcess, Qt, Signal
from PySide6.QtGui import QColor, QFont, QFontDatabase, QPainter, QPixmap, QPolygon, QTextCursor
from PySide6.QtCore import QPoint
from PySide6.QtWidgets import (QApplication, QButtonGroup, QCheckBox, QComboBox, QFileDialog, QFormLayout, QFrame,
                               QGridLayout, QHBoxLayout, QInputDialog, QLabel, QLineEdit, QListWidget, QMainWindow,
                               QMessageBox, QPlainTextEdit, QProgressBar, QPushButton, QRadioButton, QScrollArea,
                               QSplitter, QStackedWidget, QToolButton, QVBoxLayout, QWidget)

import mo5_core as core

STYLE = """
QMainWindow, QWidget#page { background: #f4f5f7; }
QListWidget#sidebar { background: #1f2430; color: #c9d1dd; border: none; font-size: 14px; padding: 12px 8px; outline: 0; }
QListWidget#sidebar::item { padding: 11px 14px; border-radius: 6px; margin-bottom: 4px; }
QListWidget#sidebar::item:selected { background: #2f6fed; color: white; }
QListWidget#sidebar::item:hover:!selected { background: #2a3140; }
QLabel#appTitle { color: white; font-size: 16px; font-weight: 600; padding: 18px 16px 6px 16px; background: #1f2430; }
QLabel#appSubtitle { color: #8b95a7; padding: 0 16px 14px 16px; background: #1f2430; }
QLabel#pageTitle { font-size: 22px; font-weight: 600; color: #1f2430; }
QLabel#pageSubtitle { color: #6b7280; }
QFrame#card { background: white; border: 1px solid #e3e6eb; border-radius: 10px; }
QLabel#cardTitle { font-size: 15px; font-weight: 600; color: #1f2430; }
QLabel#optionName { color: #9aa1ad; font-family: monospace; font-size: 11px; }
QLabel#info { background: #eef4ff; border: 1px solid #c9dafc; border-radius: 8px; padding: 10px 12px; color: #1f3b73; }
QLabel#warning { background: #fff7e6; border: 1px solid #f5d38f; border-radius: 8px; padding: 10px 12px; color: #6b4a00; }
QPushButton { padding: 7px 14px; border: 1px solid #cfd4dc; border-radius: 6px; background: white; color: #1f2430; }
QPushButton:hover { background: #f0f2f5; }
QPushButton:disabled { color: #a0a6b0; background: #f4f5f7; }
QPushButton#primary { background: #2f6fed; color: white; border: none; font-weight: 600; padding: 8px 18px; }
QPushButton#primary:hover { background: #255fd0; }
QPushButton#primary:disabled { background: #9db8f5; }
QLineEdit, QComboBox { padding: 5px 8px; border: 1px solid #cfd4dc; border-radius: 6px; background: white; min-height: 20px; }
QLineEdit:focus, QComboBox:focus { border-color: #2f6fed; }
QComboBox::drop-down { border: none; width: 26px; }
QComboBox::down-arrow { image: url(ARROW); width: 10px; height: 6px; }
QComboBox::down-arrow:disabled { image: url(ARROW_DISABLED); }
QComboBox QAbstractItemView { border: 1px solid #cfd4dc; selection-background-color: #2f6fed; selection-color: white; }
QLineEdit:disabled, QComboBox:disabled { background: #f0f1f3; color: #a0a6b0; }
QToolButton { padding: 5px 10px; border: 1px solid #cfd4dc; border-radius: 6px; background: white; }
QToolButton:hover { background: #f0f2f5; }
QPlainTextEdit#log { background: #1e1f22; color: #d4d4d4; border: none; border-radius: 8px; padding: 6px; }
QLabel#logTitle { font-weight: 600; color: #1f2430; }
QScrollArea { border: none; background: transparent; }
QStatusBar { background: white; border-top: 1px solid #e3e6eb; }
"""


# Fields ###############################################################


class OptionField(QWidget):
    """Input widget for one option of the generator description."""

    changed = Signal()

    def __init__(self, option, browse_directory):
        super().__init__()
        self.option = option
        self.browse_directory = browse_directory
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)
        kind = option["type"]
        if kind == "flag":
            self.widget = QCheckBox(option["title"])
            self.widget.toggled.connect(self.changed)
        elif kind == "choice":
            self.widget = QComboBox()
            self.widget.addItem("Par défaut", "")
            for value in option["values"]:
                self.widget.addItem(value, value)
            self.widget.currentIndexChanged.connect(self.changed)
        else:
            self.widget = QLineEdit()
            self.widget.setPlaceholderText(option["label"])
            self.widget.textChanged.connect(self.changed)
        layout.addWidget(self.widget, 1)
        if kind in core.PATH_TYPES:
            button = QToolButton()
            button.setText("Parcourir…")
            button.clicked.connect(self._browse)
            layout.addWidget(button)
        self.reset_tooltip()

    def reset_tooltip(self):
        self.setToolTip(f"{self.option['description']}\n\n-{self.option['short']}, --{self.option['long']}")

    def _browse(self):
        current = self.value() or ""
        directory = os.path.dirname(current) if current else self.browse_directory(self.option)
        title = self.option["title"]
        if self.option["type"] == "dir":
            path = QFileDialog.getExistingDirectory(self, title, directory)
        elif self.option["type"] == "path":
            path, _ = QFileDialog.getSaveFileName(self, title, current or directory)
        else:
            # file options may list their allowed extensions
            filters = [f"*.{extension} (*.{extension})" for extension in self.option["values"]] + ["Tous les fichiers (*)"]
            path, _ = QFileDialog.getOpenFileName(self, title, directory, ";;".join(filters))
        if path:
            self.set_value(path)

    def value(self):
        if self.option["type"] == "flag":
            return True if self.widget.isChecked() else None
        if self.option["type"] == "choice":
            return self.widget.currentData() or None
        return self.widget.text().strip() or None

    def set_value(self, value):
        if self.option["type"] == "flag":
            self.widget.setChecked(value in (True, "ON"))
        elif self.option["type"] == "choice":
            index = self.widget.findData(value or "")
            self.widget.setCurrentIndex(max(index, 0))
        else:
            # paths inside the repository are shown relative to work/target, like in the scripts
            if value and self.option["type"] in core.PATH_TYPES and os.path.isabs(value) and \
                    value.startswith(core.REPOSITORY + os.sep):
                value = os.path.relpath(value, core.TARGET_DIRECTORY)
            self.widget.setText(value or "")

    def set_placeholder(self, text):
        if isinstance(self.widget, QLineEdit):
            self.widget.setPlaceholderText(text)


def card(title):
    """A white rounded panel with a title; returns (frame, content layout)."""
    frame = QFrame()
    frame.setObjectName("card")
    layout = QVBoxLayout(frame)
    layout.setContentsMargins(18, 14, 18, 16)
    layout.setSpacing(10)
    label = QLabel(title)
    label.setObjectName("cardTitle")
    layout.addWidget(label)
    return frame, layout


def field_label(option):
    """Title of an option, with its command line name below."""
    widget = QWidget()
    layout = QVBoxLayout(widget)
    layout.setContentsMargins(0, 0, 0, 0)
    layout.setSpacing(0)
    layout.addWidget(QLabel(option["title"]))
    name = QLabel(f"--{option['long']}")
    name.setObjectName("optionName")
    layout.addWidget(name)
    widget.setToolTip(option["description"])
    return widget


class OptionsForm(QWidget):
    """Cards of option fields, built from the generator description, for the given categories."""

    changed = Signal()

    def __init__(self, description, categories, browse_directory, excluded=()):
        super().__init__()
        self.description = description
        self.fields = {}
        self.mode_buttons = None
        self.mode_fields = {}
        labels = {category["name"]: category["label"] for category in description["categories"]}
        by_category = {category: [option for option in description["options"]
                                  if option["category"] == category and option["long"] not in excluded]
                       for category in categories}
        by_category = {category: options for category, options in by_category.items() if options}

        # two columns: the biggest category on the right, the others on the left
        grid = QGridLayout(self)
        grid.setContentsMargins(0, 0, 0, 0)
        grid.setHorizontalSpacing(16)
        columns = [QVBoxLayout(), QVBoxLayout()]
        for column in columns:
            column.setSpacing(16)
        biggest = max(by_category, key=lambda category: len(by_category[category])) if len(by_category) > 1 else None
        for category, options in by_category.items():
            frame, layout = card(labels.get(category, category))
            if category == "mode":
                self._mode_card(layout, options, browse_directory)
            else:
                form = QFormLayout()
                form.setHorizontalSpacing(16)
                form.setVerticalSpacing(12)
                form.setLabelAlignment(Qt.AlignLeft | Qt.AlignVCenter)
                for option in options:
                    field = self._field(option, browse_directory)
                    if option["type"] == "flag":
                        form.addRow(QLabel(""), field)
                    else:
                        form.addRow(field_label(option), field)
                layout.addLayout(form)
            columns[1 if category == biggest else 0].addWidget(frame)
        for column in columns:
            column.addStretch(1)
        grid.addLayout(columns[0], 0, 0)
        grid.addLayout(columns[1], 0, 1)
        grid.setColumnStretch(0, 3)
        grid.setColumnStretch(1, 2)
        self._update_conflicts()

    def _field(self, option, browse_directory):
        field = OptionField(option, browse_directory)
        field.changed.connect(self._update_conflicts)
        field.changed.connect(self.changed)
        self.fields[option["long"]] = field
        return field

    def _mode_card(self, layout, options, browse_directory):
        """Image type: one radio button per mode, the mode field (if any) enabled when selected."""
        self.mode_buttons = QButtonGroup(self)
        for option in options:
            radio = QRadioButton(option["title"])
            radio.setToolTip(option["description"])
            self.mode_buttons.addButton(radio)
            layout.addWidget(radio)
            if option["type"] != "flag":
                field = self._field(option, browse_directory)
                field.setContentsMargins(24, 0, 0, 0)
                layout.addWidget(field)
                self.mode_fields[radio] = field
            else:
                self.mode_fields[radio] = option["long"]
            radio.toggled.connect(self._update_modes)
        self.mode_buttons.buttons()[0].setChecked(True)
        self._update_modes()

    def _update_modes(self):
        for radio, field in self.mode_fields.items():
            if isinstance(field, OptionField):
                field.setEnabled(radio.isChecked())
        self.changed.emit()

    def _update_conflicts(self):
        """A filled field disables the fields it cannot be combined with."""
        values = self.values()
        titles = {option["long"]: option["title"] for option in self.description["options"]}
        for name, field in self.fields.items():
            if field in self.mode_fields.values():
                continue
            blocking = [other for first, second in self.description["conflicts"]
                        for this, other in ((first, second), (second, first)) if this == name and other in values]
            field.setEnabled(not blocking)
            if blocking:
                field.setToolTip(f"Incompatible avec « {titles[blocking[0]]} » : videz ce champ pour utiliser celui-ci")
            else:
                field.reset_tooltip()

    def values(self):
        """{long name: value} of the filled and enabled fields, mode included."""
        values = {}
        for radio, field in self.mode_fields.items():
            if radio.isChecked() and isinstance(field, str):
                values[field] = True
        for name, field in self.fields.items():
            value = field.value()
            if value is not None and field.isEnabled():
                values[name] = value
        return values

    def clear(self):
        for field in self.fields.values():
            field.set_value(None)
        if self.mode_buttons:
            self.mode_buttons.buttons()[0].setChecked(True)

    def set_values(self, values):
        for name, value in values.items():
            if name in self.fields:
                self.fields[name].set_value(value)
        # mode: the radio of the given mode option
        for radio, field in self.mode_fields.items():
            name = field if isinstance(field, str) else field.option["long"]
            if name in values:
                radio.setChecked(True)
        self._update_conflicts()


# Pages ################################################################


def page_header(title, subtitle):
    widget = QWidget()
    layout = QVBoxLayout(widget)
    layout.setContentsMargins(0, 0, 0, 0)
    layout.setSpacing(2)
    label = QLabel(title)
    label.setObjectName("pageTitle")
    layout.addWidget(label)
    label = QLabel(subtitle)
    label.setObjectName("pageSubtitle")
    label.setWordWrap(True)
    layout.addWidget(label)
    return widget


def scrolled(widget):
    area = QScrollArea()
    area.setWidgetResizable(True)
    container = QWidget()
    container.setObjectName("page")
    layout = QVBoxLayout(container)
    layout.setContentsMargins(0, 0, 8, 0)
    layout.addWidget(widget)
    layout.addStretch(1)
    area.setWidget(container)
    return area


def browse_directory(option):
    if option["long"] == "input":
        return core.ORIGIN_DIRECTORY
    if option["category"] in ("mode", "game", "controller"):
        return os.path.join(core.ORIGIN_DIRECTORY, "game-to-install")
    return core.TARGET_DIRECTORY


class GenerationPage(QWidget):

    def __init__(self, window):
        super().__init__()
        self.setObjectName("page")
        self.main_window = window
        self.description = window.description
        layout = QVBoxLayout(self)
        layout.setContentsMargins(28, 22, 28, 12)
        layout.setSpacing(16)

        layout.addWidget(page_header("Générer une image",
                                     "Une image prête à graver, à partir de l'image RetroPie d'origine. "
                                     "Les chemins relatifs partent de work/target. Survolez un champ pour son aide."))
        actions = QHBoxLayout()
        for text, slot in (("Charger un script…", self.load_script), ("Enregistrer comme script…", self.save_script),
                           ("Réinitialiser", self.reset)):
            button = QPushButton(text)
            button.clicked.connect(lambda checked=False, slot=slot: slot())
            actions.addWidget(button)
        actions.addStretch(1)
        self.run_button = QPushButton("Générer l'image")
        self.run_button.setObjectName("primary")
        self.run_button.clicked.connect(self.generate)
        actions.addWidget(self.run_button)
        layout.addLayout(actions)

        categories = [category["name"] for category in self.description["categories"] if category["name"] != "run"]
        self.form = OptionsForm(self.description, categories, browse_directory, excluded=("modify",))
        layout.addWidget(scrolled(self.form), 1)
        self.reset()

    def reset(self):
        self.form.clear()
        self.form.set_values({"input": os.path.join(core.ORIGIN_DIRECTORY, "origin.img")})

    def check(self, values):
        if "output" not in values or "input" not in values:
            return "Indiquer l'image RetroPie d'origine et l'image à générer."
        if "generic" not in values and "specific" not in values:
            return "Indiquer la ROM du jeu à installer."
        pair = core.conflict(self.description, values)
        if pair:
            return f"--{pair[0]} et --{pair[1]} ne se combinent pas."
        return None

    def load_script(self, path=None):
        if not path:
            path, _ = QFileDialog.getOpenFileName(self, "Script de génération", core.TARGET_DIRECTORY,
                                                  "Scripts (*.sh);;Tous les fichiers (*)")
        if not path:
            return
        try:
            values, unknown = core.script_values(self.description, path)
        except (OSError, ValueError) as error:
            QMessageBox.critical(self, "Script", str(error))
            return
        self.form.clear()
        self.form.set_values(values)
        if unknown:
            QMessageBox.warning(self, "Script", "Options inconnues ignorées :\n" + " ".join(unknown))
        self.main_window.statusBar().showMessage(f"Script chargé : {os.path.basename(path)}", 8000)

    def save_script(self, path=None):
        values = self.form.values()
        error = self.check(values)
        if error:
            QMessageBox.warning(self, "Options", error)
            return
        if not path:
            path, _ = QFileDialog.getSaveFileName(self, "Enregistrer le script", core.TARGET_DIRECTORY,
                                                  "Scripts (*.sh)")
        if not path:
            return
        if not path.endswith(".sh"):
            path += ".sh"
        with open(path, "w", encoding="utf-8") as file:
            file.write(core.script_text(self.description, values, os.path.dirname(path)))
        os.chmod(path, 0o755)
        self.main_window.statusBar().showMessage(f"Script enregistré : {os.path.basename(path)}", 8000)

    def generate(self):
        values = self.form.values()
        error = self.check(values)
        if error:
            QMessageBox.warning(self, "Options", error)
            return
        options = {option["long"]: option for option in self.description["options"]}
        # paths relative to work/target, like the scripts
        for name, value in values.items():
            if options[name]["type"] in core.PATH_TYPES:
                values[name] = os.path.abspath(os.path.join(core.TARGET_DIRECTORY, value))
        if os.path.exists(values["output"]) and QMessageBox.question(
                self, "Image existante", f"{os.path.basename(values['output'])} existe déjà et sera remplacée. Continuer ?"
        ) != QMessageBox.Yes:
            return
        self.main_window.run(core.generator_arguments(options, values), f"Génération de {os.path.basename(values['output'])}")


class ModificationPage(QWidget):

    def __init__(self, window):
        super().__init__()
        self.setObjectName("page")
        self.main_window = window
        self.description = window.description
        self.modes = core.hdmi_modes()
        self.cards = []
        self.target = None
        self.installed_controller = None
        layout = QVBoxLayout(self)
        layout.setContentsMargins(28, 22, 28, 12)
        layout.setSpacing(16)

        top = QHBoxLayout()
        top.addWidget(page_header("Modifier une image ou une carte SD",
                                  "Manette, affichage et son d'une image générée ou d'une carte gravée. "
                                  "Le jeu ne change pas."), 1)
        self.run_button = QPushButton("Appliquer les réglages")
        self.run_button.setObjectName("primary")
        self.run_button.clicked.connect(self.apply)
        top.addWidget(self.run_button, 0, Qt.AlignBottom)
        layout.addLayout(top)

        content = QWidget()
        content_layout = QVBoxLayout(content)
        content_layout.setContentsMargins(0, 0, 0, 0)
        content_layout.setSpacing(16)

        frame, frame_layout = card("Image ou carte SD")
        grid = QGridLayout()
        grid.setHorizontalSpacing(10)
        grid.setVerticalSpacing(10)
        self.image = QLineEdit()
        self.image.setPlaceholderText("Fichier .img généré")
        self.image.returnPressed.connect(lambda: self.set_target(self.image.text(), os.path.basename(self.image.text())))
        button = QToolButton()
        button.setText("Parcourir…")
        button.clicked.connect(self.choose_image)
        grid.addWidget(QLabel("Image"), 0, 0)
        grid.addWidget(self.image, 0, 1)
        grid.addWidget(button, 0, 2)
        self.card_list = QComboBox()
        self.card_list.activated.connect(self.choose_card)
        button = QToolButton()
        button.setText("Actualiser")
        button.clicked.connect(self.refresh_cards)
        grid.addWidget(QLabel("Carte SD"), 1, 0)
        grid.addWidget(self.card_list, 1, 1)
        grid.addWidget(button, 1, 2)
        grid.setColumnStretch(1, 1)
        frame_layout.addLayout(grid)
        row = QHBoxLayout()
        self.target_label = QLabel("Aucune image ni carte choisie.")
        self.target_label.setObjectName("pageSubtitle")
        row.addWidget(self.target_label, 1)
        read_button = QPushButton("Relire les réglages")
        read_button.clicked.connect(self.read_settings)
        row.addWidget(read_button)
        frame_layout.addLayout(row)
        self.summary = QLabel()
        self.summary.setWordWrap(True)
        self.summary.setTextFormat(Qt.RichText)
        self.summary.hide()
        frame_layout.addWidget(self.summary)
        content_layout.addWidget(frame)

        categories = [category["name"] for category in self.description["categories"] if category["settings"]]
        self.form = OptionsForm(self.description, categories, browse_directory)
        content_layout.addWidget(self.form)
        note = QLabel("Tous les réglages affichés sont appliqués : « Par défaut » ou un champ vide remet la valeur par "
                      "défaut. La manette n'est remplacée que si un nouveau fichier est choisi.")
        note.setObjectName("pageSubtitle")
        note.setWordWrap(True)
        content_layout.addWidget(note)
        layout.addWidget(scrolled(content), 1)
        self.refresh_cards()

    def set_target(self, target, label):
        if not target:
            return
        self.target = target
        self.target_label.setText(f"Cible : {label}")
        self.read_settings()

    def choose_image(self):
        path, _ = QFileDialog.getOpenFileName(self, "Image générée", core.TARGET_DIRECTORY,
                                              "Images (*.img);;Tous les fichiers (*)")
        if path:
            self.image.setText(path)
            self.card_list.setCurrentIndex(0)
            self.set_target(path, os.path.basename(path))

    def refresh_cards(self):
        try:
            self.cards = core.list_sd_cards()
        except (subprocess.CalledProcessError, ValueError):
            self.cards = []
        self.card_list.clear()
        self.card_list.addItem("Aucune carte détectée" if not self.cards else "Choisir une carte…", None)
        for path, label in self.cards:
            self.card_list.addItem(label, path)

    def choose_card(self, index):
        path = self.card_list.itemData(index)
        if path:
            self.image.clear()
            self.set_target(path, self.card_list.itemText(index))

    def show_summary(self, text, warning=False):
        self.summary.setObjectName("warning" if warning else "info")
        self.summary.style().unpolish(self.summary)
        self.summary.style().polish(self.summary)
        self.summary.setText(text)
        self.summary.show()

    def read_settings(self):
        if not self.target:
            return
        try:
            files = core.read_target_boot_files(self.target, [core.RECORD_NAME, "config.txt"])
        except (OSError, RuntimeError, struct.error, subprocess.CalledProcessError) as error:
            self.show_summary(f"Impossible de lire {self.target} : {error}", warning=True)
            return
        self.form.clear()
        self.installed_controller = None
        settings_categories = [category["name"] for category in self.description["categories"] if category["settings"]]
        options = {option["long"]: option for option in self.description["options"]}
        if core.RECORD_NAME in files:
            record = core.parse_record(files[core.RECORD_NAME])
            self.installed_controller = record.get("controller")
            settings = {name: value for name, value in record.items()
                        if name in options and options[name]["category"] in settings_categories and name != "controller"}
            self.form.set_values(settings)
            game = f"<b>{record['specific']}</b>" if record.get("specific") else "<b>image générique</b>"
            lines = [f"Jeu : {game}" + (f" — émulateur {record['emulator']}" if record.get("emulator") else "")]
            lines.append(f"Manette installée : {record.get('controller', 'aucune')}")
            dates = f"Générée le {record.get('generated', '?')}"
            if record.get("modified"):
                dates += f", modifiée le {record['modified']}"
            lines.append(dates + f" (générateur {record.get('generator_version', '?')})")
            self.show_summary("<br>".join(lines))
        elif "config.txt" in files:
            self.form.set_values(core.settings_from_config_txt(files["config.txt"], self.modes))
            self.show_summary(f"Pas de /boot/{core.RECORD_NAME} : image générée avant son introduction. Seuls les "
                              "réglages de config.txt ont été relus ; le son, les scanlines et le lissage sont à vérifier.",
                              warning=True)
        else:
            self.show_summary("Ni mo5-options.conf ni config.txt : ce n'est pas une image RetroPie ?", warning=True)
        controller = self.form.fields.get("controller")
        if controller:
            controller.set_placeholder(f"Garder {self.installed_controller}" if self.installed_controller
                                       else "Aucune manette installée")

    def apply(self):
        if not self.target:
            QMessageBox.warning(self, "Cible", "Choisir une image ou une carte SD.")
            return
        values = self.form.values()
        pair = core.conflict(self.description, values)
        if pair:
            QMessageBox.warning(self, "Options", f"--{pair[0]} et --{pair[1]} ne se combinent pas.")
            return
        if not os.path.isfile(self.target) and QMessageBox.question(
                self, "Carte SD", f"Modifier la carte {self.target} ? Ses partitions vont être démontées.") != QMessageBox.Yes:
            return
        options = {option["long"]: option for option in self.description["options"]}
        self.main_window.run(["--modify", self.target] + core.generator_arguments(options, values),
                        f"Modification de {os.path.basename(self.target)}", after=self.read_settings)


# Main window ##########################################################


class MainWindow(QMainWindow):

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Éditeur de configuration MO5")
        self.resize(1200, 860)
        self.password = None
        self.process = None
        self.after_run = None
        self.label = ""
        try:
            self.description = core.describe_generator()
        except (subprocess.CalledProcessError, ValueError) as error:
            QMessageBox.critical(None, "Générateur", f"Impossible de lire la description des options :\n{error}")
            raise SystemExit(1)

        central = QWidget()
        root = QHBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        side = QWidget()
        side.setFixedWidth(240)
        side.setStyleSheet("background: #1f2430;")
        side_layout = QVBoxLayout(side)
        side_layout.setContentsMargins(0, 0, 0, 0)
        side_layout.setSpacing(0)
        title = QLabel("Bornes MO5")
        title.setObjectName("appTitle")
        side_layout.addWidget(title)
        subtitle = QLabel("Éditeur de configuration")
        subtitle.setObjectName("appSubtitle")
        side_layout.addWidget(subtitle)
        self.sidebar = QListWidget()
        self.sidebar.setObjectName("sidebar")
        self.sidebar.addItems(["Générer une image", "Modifier une image\nou une carte SD"])
        side_layout.addWidget(self.sidebar, 1)
        root.addWidget(side)

        splitter = QSplitter(Qt.Vertical)
        self.pages = QStackedWidget()
        self.generation = GenerationPage(self)
        self.modification = ModificationPage(self)
        self.pages.addWidget(self.generation)
        self.pages.addWidget(self.modification)
        self.sidebar.currentRowChanged.connect(self.pages.setCurrentIndex)
        self.sidebar.setCurrentRow(0)
        splitter.addWidget(self.pages)
        splitter.addWidget(self._log_panel())
        splitter.setStretchFactor(0, 4)
        splitter.setStretchFactor(1, 1)
        splitter.setSizes([640, 200])
        root.addWidget(splitter, 1)
        self.setCentralWidget(central)

        self.progress = QProgressBar()
        self.progress.setRange(0, 0)
        self.progress.setMaximumWidth(160)
        self.progress.hide()
        self.statusBar().addPermanentWidget(self.progress)
        self.stop_button = QPushButton("Arrêter")
        self.stop_button.clicked.connect(self.stop)
        self.stop_button.hide()
        self.statusBar().addPermanentWidget(self.stop_button)
        self.statusBar().showMessage("Prêt.")

    def _log_panel(self):
        panel = QWidget()
        panel.setObjectName("page")
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(28, 6, 28, 12)
        layout.setSpacing(6)
        header = QHBoxLayout()
        label = QLabel("Journal")
        label.setObjectName("logTitle")
        header.addWidget(label)
        header.addStretch(1)
        clear = QToolButton()
        clear.setText("Effacer")
        clear.clicked.connect(lambda: self.log.clear())
        header.addWidget(clear)
        layout.addLayout(header)
        self.log = QPlainTextEdit()
        self.log.setObjectName("log")
        self.log.setReadOnly(True)
        self.log.setFont(QFontDatabase.systemFont(QFontDatabase.FixedFont))
        self.log.setMaximumBlockCount(20000)
        layout.addWidget(self.log)
        return panel

    def append_log(self, text):
        self.log.moveCursor(QTextCursor.End)
        self.log.insertPlainText(text)
        self.log.moveCursor(QTextCursor.End)

    def ask_password(self):
        """sudo password, checked then kept for the session (None if cancelled, "" if sudo needs none)."""
        if not core.sudo_needs_password():
            return ""
        prompt = "Mot de passe sudo (pour monter les images) :"
        while self.password is None:
            password, accepted = QInputDialog.getText(self, "sudo", prompt, QLineEdit.Password)
            if not accepted:
                return None
            if core.sudo_password_is_valid(password):
                self.password = password
            else:
                prompt = "Mot de passe incorrect. Mot de passe sudo :"
        return self.password

    def run(self, arguments, label, after=None):
        if self.process is not None:
            QMessageBox.warning(self, "Générateur", "Une opération est déjà en cours.")
            return
        password = self.ask_password()
        if password is None:
            return
        program, program_arguments = core.sudo_command(arguments)
        self.log.clear()
        self.append_log("$ generate-generic-image.sh --batch " + " ".join(shlex.quote(a) for a in arguments) + "\n")
        self.label = label
        self.after_run = after
        self.process = QProcess(self)
        self.process.setWorkingDirectory(core.TARGET_DIRECTORY)
        self.process.setProcessChannelMode(QProcess.MergedChannels)
        self.process.readyReadStandardOutput.connect(
            lambda: self.append_log(bytes(self.process.readAllStandardOutput()).decode("utf-8", errors="replace")))
        self.process.finished.connect(self.finished)
        self.process.start(program, program_arguments)
        self.process.write((password + "\n").encode())
        self.process.closeWriteChannel()
        for page in (self.generation, self.modification):
            page.run_button.setEnabled(False)
        self.progress.show()
        self.stop_button.show()
        self.statusBar().showMessage(label + "…")

    def finished(self, code, _status):
        if code == 0:
            self.statusBar().showMessage(f"{self.label} : terminé.")
        else:
            self.statusBar().showMessage(f"{self.label} : échec (code {code}), voir le journal.")
        self.process = None
        for page in (self.generation, self.modification):
            page.run_button.setEnabled(True)
        self.progress.hide()
        self.stop_button.hide()
        if code == 0 and self.after_run:
            self.after_run()

    def stop(self):
        if self.process is not None:
            self.process.terminate()


def arrow_image(directory, name, color):
    """A small down arrow for the combo boxes, drawn by Qt (no SVG plugin needed)."""
    pixmap = QPixmap(10, 6)
    pixmap.fill(Qt.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setPen(Qt.NoPen)
    painter.setBrush(QColor(color))
    painter.drawPolygon(QPolygon([QPoint(0, 0), QPoint(10, 0), QPoint(5, 6)]))
    painter.end()
    path = os.path.join(directory, name)
    pixmap.save(path)
    return path


def style_sheet(directory):
    return (STYLE.replace("ARROW_DISABLED", arrow_image(directory, "arrow-disabled.png", "#c3c8d0"))
            .replace("ARROW", arrow_image(directory, "arrow.png", "#6b7280")))


def main():
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    images = tempfile.TemporaryDirectory(prefix="mo5-editor-")
    app.setStyleSheet(style_sheet(images.name))
    font = QFont(app.font())
    font.setPointSize(10)
    app.setFont(font)
    window = MainWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
