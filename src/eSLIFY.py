"""eSLIFY — marque des plugins Skyrim SE comme ESL (light master), en vérifiant d'abord qu'ils sont éligibles."""
import sys
from pathlib import Path

from PyQt6.QtCore import QSettings, Qt
from PyQt6.QtGui import QBrush, QColor, QIcon
from PyQt6.QtWidgets import (
    QAbstractItemView, QApplication, QCheckBox, QFileDialog, QFrame, QHBoxLayout, QLabel, QMessageBox,
    QPushButton, QTreeWidget, QTreeWidgetItem, QVBoxLayout, QWidget,
)

import eslify_core as core
import socle_qt
import update_check
from i18n import get_lang
from i18n import L
from lang_button import LangButton, init_lang

APP_NAME = "eSLIFY"
EXTS = (".esp", ".esm", ".esl")
# Icône : à côté du script (assets/) ou dans le bundle PyInstaller (sys._MEIPASS).
ICON = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent)) / "assets" / "icon.png"


class ESLifyApp(QWidget):
    def __init__(self, settings: QSettings):
        super().__init__()
        self.settings = settings
        self.setWindowTitle(APP_NAME)
        self.resize(860, 560)
        self.setAcceptDrops(True)
        self.results: dict[Path, core.Eligibility] = {}

        lay = QVBoxLayout(self)
        m = socle_qt.m
        lay.setContentsMargins(m("space-3"), m("space-3"), m("space-3"), m("space-3"))
        lay.setSpacing(m("space-3"))

        head = QFrame()
        head.setObjectName("HeaderBar")
        hh = QHBoxLayout(head)
        hh.setContentsMargins(m("space-3"), m("space-2"), m("space-3"), m("space-2"))
        hl = QVBoxLayout()
        hl.setSpacing(2)
        hl.addWidget(socle_qt.role(QLabel(APP_NAME), "title"))
        self.subtitle = socle_qt.role(QLabel(), "meta")
        hl.addWidget(self.subtitle)
        hh.addLayout(hl, 1)
        self.btn_lang = LangButton(settings, self.apply_texts)
        hh.addWidget(self.btn_lang, 0, Qt.AlignmentFlag.AlignTop)
        lay.addWidget(head)

        row = QHBoxLayout()
        row.setSpacing(m("space-2"))
        self.btn_files = socle_qt.variant(QPushButton(), "action")
        self.btn_files.setStyleSheet(f"min-height: {m('size-control') - 2}px;")
        self.btn_files.clicked.connect(self.pick_files)
        self.btn_dir = QPushButton()
        self.btn_dir.clicked.connect(self.pick_dir)
        self.btn_clear = QPushButton()
        self.btn_clear.clicked.connect(self.clear)
        for b in (self.btn_files, self.btn_dir, self.btn_clear):
            b.setCursor(Qt.CursorShape.PointingHandCursor)
            row.addWidget(b)
        row.addStretch(1)
        lay.addLayout(row)

        self.tree = QTreeWidget()
        self.tree.setRootIsDecorated(False)
        self.tree.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
        self.tree.setAlternatingRowColors(False)
        hdr = self.tree.header()
        hdr.setSectionResizeMode(0, hdr.ResizeMode.ResizeToContents)
        hdr.setSectionResizeMode(1, hdr.ResizeMode.ResizeToContents)
        hdr.setSectionResizeMode(2, hdr.ResizeMode.ResizeToContents)
        hdr.setSectionResizeMode(3, hdr.ResizeMode.ResizeToContents)
        hdr.setStretchLastSection(True)
        self.tree.itemSelectionChanged.connect(self.show_reason)
        lay.addWidget(self.tree, 1)

        self.reason = socle_qt.role(QLabel(), "muted")
        self.reason.setWordWrap(True)
        lay.addWidget(self.reason)

        bottom = QHBoxLayout()
        self.chk_backup = QCheckBox()
        self.chk_backup.setChecked(True)
        bottom.addWidget(self.chk_backup)
        bottom.addStretch(1)
        self.btn_apply = socle_qt.variant(QPushButton(), "primary")
        self.btn_apply.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_apply.clicked.connect(self.apply)
        bottom.addWidget(self.btn_apply)
        lay.addLayout(bottom)
        self.apply_texts()

    def apply_texts(self):
        """(Re)traduit l'interface dans la langue active ; les verdicts sont recalculés."""
        self.btn_lang.refresh()
        self.subtitle.setText(L("Marque des plugins comme ESL (light master) après avoir vérifié leurs FormID."))
        self.btn_files.setText(L("Ajouter des plugins"))
        self.btn_dir.setText(L("Ajouter un dossier"))
        self.btn_clear.setText(L("Vider la liste"))
        self.tree.setHeaderLabels([L("Plugin"), L("Statut"), L("Nouveaux enr."), L("FormID propres"), L("Dossier")])
        self.chk_backup.setText(L("Créer une copie de sauvegarde (.bak) avant modification"))
        for path in list(self.results):
            self.results[path] = self._check(path)
        self._rebuild()
        if not self.tree.selectedItems():
            socle_qt.status(self.reason, "none")
            self.reason.setText(L("Ajoutez ou glissez-déposez des fichiers .ESP, .ESM, .ESL ou un dossier."))
        self.show_reason()

    # -- ajout de fichiers
    def pick_files(self):
        files, _ = QFileDialog.getOpenFileNames(self, L("Ajouter des plugins"), "", L("Plugins Skyrim") + " (*.esp *.esm *.esl)")
        self.add_paths(files)

    def pick_dir(self):
        d = QFileDialog.getExistingDirectory(self, L("Ajouter un dossier"))
        if d:
            self.add_paths([d])

    def dragEnterEvent(self, e):
        if e.mimeData().hasUrls():
            e.acceptProposedAction()

    def dropEvent(self, e):
        self.add_paths([u.toLocalFile() for u in e.mimeData().urls()])

    def add_paths(self, paths):
        files = []
        for p in map(Path, paths):
            if p.is_dir():
                files += sorted(x for x in p.iterdir() if x.suffix.lower() in EXTS and x.is_file())
            elif p.suffix.lower() in EXTS and p.is_file():
                files.append(p)
        for f in files:
            if f in self.results:
                continue
            res = self.results[f] = self._check(f)
            self.tree.addTopLevelItem(self._item(res))
        self.refresh_button()

    @staticmethod
    def _check(f: Path) -> core.Eligibility:
        try:
            return core.check_eligibility(f)
        except OSError as e:
            return core.Eligibility(path=f, reason=L("Lecture impossible : {err}.", err=e.strerror))
        except Exception as e:  # fichier tronqué ou corrompu
            return core.Eligibility(path=f, reason=L("Plugin illisible : {err}.", err=e))

    def _item(self, r: core.Eligibility) -> QTreeWidgetItem:
        if r.already_esl:
            status, token = L("Déjà ESL"), "text-muted"
        elif r.eligible:
            status, token = L("Éligible"), "warning" if r.dependents else "success"
        else:
            status, token = L("Non éligible"), "danger"
        span = "—" if r.max_object is None else f"{r.min_object:03X} – {r.max_object:03X}"
        it = QTreeWidgetItem([r.path.name, status, str(r.new_records), span, str(r.path.parent)])
        it.setData(0, Qt.ItemDataRole.UserRole, r.path)
        it.setForeground(1, QBrush(QColor(socle_qt.c(token))))
        for col in (2, 3):
            it.setFont(col, socle_qt.font("mono"))
        it.setForeground(4, QBrush(QColor(socle_qt.c("text-subtle"))))
        return it

    def _rebuild(self):
        selected = {it.data(0, Qt.ItemDataRole.UserRole) for it in self.tree.selectedItems()}
        self.tree.clear()
        for res in self.results.values():
            it = self._item(res)
            self.tree.addTopLevelItem(it)
            it.setSelected(res.path in selected)

    def clear(self):
        self.results.clear()
        self.tree.clear()
        self.reason.setText(L("Ajoutez ou glissez-déposez des fichiers .ESP, .ESM, .ESL ou un dossier."))
        self.refresh_button()

    def show_reason(self):
        items = self.tree.selectedItems()
        socle_qt.status(self.reason, "none")
        if len(items) == 1:
            r = self.results[items[0].data(0, Qt.ItemDataRole.UserRole)]
            extra = "  " + L("En-tête {version}, {n} maître(s).", version=r.hedr_version, n=r.masters) if r.hedr_version else ""
            self.reason.setText(L("{name} : {reason}", name=r.path.name, reason=r.reason) + extra)
        self.refresh_button()

    def targets(self) -> list[core.Eligibility]:
        """Plugins éligibles parmi la sélection (ou toute la liste si rien n'est sélectionné)."""
        items = self.tree.selectedItems() or [self.tree.topLevelItem(i) for i in range(self.tree.topLevelItemCount())]
        return [self.results[it.data(0, Qt.ItemDataRole.UserRole)] for it in items
                if self.results[it.data(0, Qt.ItemDataRole.UserRole)].eligible]

    def refresh_button(self):
        n = len(self.targets())
        self.btn_apply.setEnabled(n > 0)
        self.btn_apply.setText(L("MARQUER ESL ({n})", n=n) if n else L("MARQUER ESL"))

    # -- application
    def apply(self):
        todo = self.targets()
        if not todo:
            return
        keep = self.chk_backup.isChecked()
        msg = (L("Marquer {n} plugin(s) comme ESL ?", n=len(todo)) + "\n\n" + "\n".join(r.path.name for r in todo[:15])
               + ("\n…" if len(todo) > 15 else "") + "\n\n"
               + (L("Une copie .bak de chaque fichier est créée avant modification.") if keep
                  else L("Aucune copie de sauvegarde ne sera créée.")))
        if QMessageBox.question(self, APP_NAME, msg) != QMessageBox.StandardButton.Yes:
            return
        done, errors = 0, []
        for r in todo:
            try:
                if keep:
                    core.backup(r.path)
                if core.inspect_and_flag_esl(r.path, apply_fix=True).get("modified"):
                    done += 1
                self.results[r.path] = core.check_eligibility(r.path)
            except Exception as e:
                errors.append(L("{name} : {reason}", name=r.path.name, reason=e))
        self.tree.clear()
        self._rebuild()
        self.refresh_button()
        text = L("{n} plugin(s) marqué(s) ESL.", n=done)
        socle_qt.status(self.reason, "danger" if errors else "success")
        self.reason.setText(text + (" " + L("{n} échec(s).", n=len(errors)) if errors else ""))
        if errors:
            QMessageBox.warning(self, APP_NAME, text + "\n\n" + L("Échecs :") + "\n" + "\n".join(errors[:15]))


if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    if ICON.is_file():
        app.setWindowIcon(QIcon(str(ICON)))
    socle_qt.apply(app)
    settings = QSettings(APP_NAME, APP_NAME)
    init_lang(settings)
    w = ESLifyApp(settings)
    w.show()
    update_check.start_qt(w, "eSLIFY", lang=get_lang)  # nouvelle version ? (au plus une fois par jour)
    w.add_paths(sys.argv[1:])
    sys.exit(app.exec())
