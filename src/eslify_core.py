"""Cœur d'eSLIFY : lecture et pose du drapeau ESL (light master) des plugins Skyrim SE.

inspect_and_flag_esl() est la fonction d'origine (ESLIFY.py), inchangée.
check_eligibility() vérifie, avant de poser le drapeau, que les FormID propres au plugin
tiennent dans la plage des plugins légers : sinon le jeu les renumérote et le plugin casse.
Elle refuse aussi les plugins qui ajoutent des cellules ou des worldspaces (le moteur gère mal
les nouvelles cellules d'un plugin léger) et signale ceux dont d'autres plugins du dossier dépendent.
"""
import functools
import shutil
import struct
import time
from dataclasses import dataclass
from pathlib import Path

from i18n import L

FLAG_ESL = 0x0200
ESL_MAX_OBJECT = 0xFFF       # dernier identifiant d'objet autorisé dans un plugin léger
ESL_MIN_OBJECT_OLD = 0x800   # avant l'en-tête 1.71, les identifiants commencent à 0x800
HEDR_VERSION_171 = 1.71
WORLD_RECORDS = (b"CELL", b"WRLD")   # nouveaux enregistrements interdits dans un plugin léger
EXTS = (".esp", ".esm", ".esl")


def inspect_and_flag_esl(plugin_path: str | Path, apply_fix: bool = False) -> dict:
    """Lit l'en-tête TES4 d'un plugin Skyrim, vérifie son statut ESL

    et applique le flag si demandé.
    """
    path = Path(plugin_path)
    if not path.is_file():
        raise FileNotFoundError(L("Fichier introuvable : {path}", path=path))

    with path.open("r+b" if apply_fix else "rb") as f:
        # Lecture de la signature du premier record (doit être TES4)
        sig = f.read(4)
        if sig != b"TES4":
            raise ValueError(L("{name} n'est pas un plugin Skyrim valide (attendu TES4, trouvé {sig}).", name=path.name, sig=sig))

        # Offset 4: data_size (4 octets uint32)
        # Offset 8: flags (4 octets uint32)
        f.seek(8)
        (flags,) = struct.unpack("<I", f.read(4))

        is_esl = bool(flags & FLAG_ESL)

        if apply_fix and not is_esl:
            new_flags = flags | FLAG_ESL
            f.seek(8)
            f.write(struct.pack("<I", new_flags))
            return {
                "file": path.name,
                "already_esl": False,
                "modified": True,
                "previous_flags": hex(flags),
                "new_flags": hex(new_flags),
            }

    return {
        "file": path.name,
        "already_esl": is_esl,
        "modified": False,
        "current_flags": hex(flags),
    }


@dataclass
class Eligibility:
    path: Path
    flags: int = 0
    already_esl: bool = False
    masters: int = 0
    new_records: int = 0
    min_object: int | None = None
    max_object: int | None = None
    hedr_version: float = 0.0
    new_cells: int = 0
    dependents: tuple[str, ...] = ()
    eligible: bool = False
    reason: str = ""


def read_masters(data: bytes) -> tuple[float, list[str]]:
    """Version HEDR et noms des maîtres (MAST) lus dans l'en-tête TES4."""
    size = struct.unpack_from("<I", data, 4)[0]
    version, masters = 0.0, []
    q, end = 24, min(24 + size, len(data))
    while q + 6 <= end:
        sig = data[q:q + 4]
        sz = struct.unpack_from("<H", data, q + 4)[0]
        if sig == b"HEDR" and sz >= 4:
            version = round(struct.unpack_from("<f", data, q + 6)[0], 2)
        elif sig == b"MAST":
            masters.append(data[q + 6:q + 6 + sz].split(b"\0", 1)[0].decode("cp1252", "replace"))
        q += 6 + sz
    return version, masters


def _header(path: Path) -> bytes:
    """Début du fichier jusqu'à la fin de l'en-tête TES4 (vide si ce n'est pas un plugin)."""
    with path.open("rb") as f:
        head = f.read(24)
        if len(head) < 24 or head[:4] != b"TES4":
            return b""
        return head + f.read(struct.unpack_from("<I", head, 4)[0])


@functools.lru_cache(maxsize=8)
def _masters_by_plugin(folder: Path, _mtime: int) -> dict[str, tuple[str, ...]]:
    """Maîtres (en minuscules) de chaque plugin du dossier ; relu quand le dossier change."""
    table = {}
    for other in sorted(folder.iterdir()):
        if other.suffix.lower() not in EXTS or not other.is_file():
            continue
        try:
            head = _header(other)
        except OSError:
            continue
        if head:
            table[other.name] = tuple(m.lower() for m in read_masters(head)[1])
    return table


def dependents_of(path: str | Path) -> tuple[str, ...]:
    """Plugins du même dossier qui déclarent ce plugin comme maître."""
    path = Path(path)
    name = path.name.lower()
    table = _masters_by_plugin(path.parent, path.parent.stat().st_mtime_ns)
    return tuple(other for other, masters in table.items() if other != path.name and name in masters)


def check_eligibility(plugin_path: str | Path, dependents: tuple[str, ...] | None = None) -> Eligibility:
    """Analyse les en-têtes d'enregistrements (sans décompresser) pour savoir si le plugin
    peut recevoir le drapeau ESL sans casser ses FormID.

    dependents : plugins qui dépendent de celui-ci ; par défaut, cherchés dans son dossier."""
    path = Path(plugin_path)
    res = Eligibility(path=path)
    data = path.read_bytes()
    if data[:4] != b"TES4":
        res.reason = L("Ce n'est pas un plugin Skyrim (en-tête TES4 absent).")
        return res
    size, res.flags = struct.unpack_from("<II", data, 4)
    res.already_esl = bool(res.flags & FLAG_ESL)
    res.hedr_version, masters = read_masters(data)
    res.masters = len(masters)
    end = 24 + size

    # Enregistrements : on descend dans les groupes sans lire les données
    p, n = end, len(data)
    while p + 24 <= n:
        sig = data[p:p + 4]
        sz = struct.unpack_from("<I", data, p + 4)[0]
        if sig == b"GRUP":
            p += 24
            continue
        form_id = struct.unpack_from("<I", data, p + 12)[0]
        if form_id >> 24 == res.masters:
            obj = form_id & 0xFFFFFF
            res.new_records += 1
            res.min_object = obj if res.min_object is None else min(res.min_object, obj)
            res.max_object = obj if res.max_object is None else max(res.max_object, obj)
            if sig in WORLD_RECORDS:
                res.new_cells += 1
        p += 24 + sz
    res.dependents = dependents_of(path) if dependents is None else tuple(dependents)

    if res.already_esl:
        res.eligible, res.reason = False, L("Déjà marqué ESL.")
    elif res.new_cells:
        res.reason = L("Ajoute {n} cellule(s) ou worldspace(s) : le jeu gère mal les nouvelles cellules d'un plugin ESL (modifications perdues, objets qui disparaissent).",
                       n=res.new_cells)
    elif res.max_object is not None and res.max_object > ESL_MAX_OBJECT:
        res.reason = L("FormID propre trop élevé ({max} > {limit}). Compactez les FormID dans xEdit avant de le marquer ESL.",
                       max=f"{res.max_object:06X}", limit=f"{ESL_MAX_OBJECT:03X}")
    elif (res.min_object is not None and res.min_object < ESL_MIN_OBJECT_OLD
          and res.hedr_version < HEDR_VERSION_171):
        res.reason = L("FormID propre sous 0x800 ({min}) avec un en-tête {version} : il faut un en-tête 1.71 (xEdit) pour que le jeu l'accepte.",
                       min=f"{res.min_object:06X}", version=res.hedr_version)
    elif res.dependents:
        res.eligible = True
        res.reason = L("Éligible, mais {n} plugin(s) en dépendent ({names}) : ne compactez plus ses FormID après le marquage, ils casseraient.",
                       n=len(res.dependents), names=", ".join(res.dependents[:3]) + ("…" if len(res.dependents) > 3 else ""))
    else:
        res.eligible, res.reason = True, L("Éligible.")
    return res


def backup(path: str | Path) -> Path:
    """Copie de sauvegarde à côté du plugin : <nom>.bak (horodatée si elle existe déjà)."""
    path = Path(path)
    target = path.with_name(path.name + ".bak")
    if target.exists():
        target = path.with_name(f"{path.name}.{time.strftime('%Y%m%d-%H%M%S')}.bak")
    shutil.copy2(path, target)
    return target
