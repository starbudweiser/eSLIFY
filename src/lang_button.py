"""Bouton drapeau de la langue et son menu (Automatique, français, anglais, italien, espagnol).

Même présentation que kEYKODES. Le choix est mémorisé dans les QSettings de l'appli
(clé « language », « auto » = langue du Mac).
"""
from PyQt6.QtCore import QCoreApplication, QLibraryInfo, QLocale, QSettings, Qt, QTranslator
from PyQt6.QtGui import QActionGroup
from PyQt6.QtWidgets import QMenu, QPushButton

import i18n
import socle_qt
from i18n import L

AUTO = "auto"  # langue du système


def detect_system_lang() -> str:
    """Langue de l'interface du Mac (Réglages > Général > Langue et région)."""
    return i18n.system_lang(QLocale.system().uiLanguages())


_qt_tr = None


def qt_lang(code: str) -> None:
    """Boutons standard de Qt (Oui/Non, Annuler, OK…) dans la langue de l'appli : traductions de Qt embarquées."""
    global _qt_tr
    app = QCoreApplication.instance()
    if app is None:
        return
    if _qt_tr is not None:
        app.removeTranslator(_qt_tr)
        _qt_tr = None
    if code != "en":
        tr = QTranslator(app)
        if tr.load(f"qtbase_{code}", QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath)):
            app.installTranslator(tr)
            _qt_tr = tr


def init_lang(settings: QSettings) -> None:
    """Active la langue mémorisée (à appeler avant de construire l'interface)."""
    choice = settings.value("language", AUTO)
    qt_lang(i18n.set_lang(detect_system_lang() if choice == AUTO else choice))


class LangButton(QPushButton):
    """Drapeau de la langue active ; un clic ouvre le menu de choix, puis appelle on_change()."""

    def __init__(self, settings: QSettings, on_change, parent=None):
        super().__init__(parent)
        self.settings = settings
        self.on_change = on_change
        self.setObjectName("LangButton")
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        size = round(18 * socle_qt.SCALE)
        self.setStyleSheet(
            f"QPushButton#LangButton {{ background: transparent; border: none; border-radius: {socle_qt.m('radius')}px;"
            f" padding: 0; min-height: 0; font-size: {size}px; }}"
            f"QPushButton#LangButton:hover {{ background: {socle_qt.c('surface-hover')}; }}")
        self.setFixedSize(size + 12, size + 8)
        self.clicked.connect(self._open_menu)
        self.refresh()

    def refresh(self):
        code = i18n.get_lang()
        self.setText(i18n.FLAGS[code])
        self.setToolTip(L("Langue : {name}", name=i18n.LANGS[code]))

    def _open_menu(self):
        menu = QMenu(self)
        group = QActionGroup(menu)
        chosen = self.settings.value("language", AUTO)
        system = detect_system_lang()
        auto = menu.addAction(L("Automatique ({lang})", lang=f"{i18n.FLAGS[system]} {i18n.LANGS[system]}"))
        auto.setData(AUTO)
        menu.addSeparator()
        actions = [auto]
        for code, name in i18n.LANGS.items():
            act = menu.addAction(f"{i18n.FLAGS[code]}  {name}")
            act.setData(code)
            actions.append(act)
        for act in actions:
            act.setCheckable(True)
            act.setChecked(act.data() == chosen)
            group.addAction(act)
        picked = menu.exec(self.mapToGlobal(self.rect().bottomLeft()))
        if picked is not None:
            self.settings.setValue("language", picked.data())
            qt_lang(i18n.set_lang(detect_system_lang() if picked.data() == AUTO else picked.data()))
            self.refresh()
            self.on_change()
