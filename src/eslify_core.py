"""Cœur d'eSLIFY : lecture et pose du drapeau ESL (light master) des plugins Skyrim SE.

inspect_and_flag_esl() est la fonction d'origine (ESLIFY.py), inchangée.
check_eligibility() vérifie, avant de poser le drapeau, que les FormID propres au plugin
tiennent dans la plage des plugins légers : sinon le jeu les renumérote et le plugin casse.
"""
import shutil
import struct
import time
from dataclasses import dataclass
from pathlib import Path

FLAG_ESL = 0x0200
ESL_MAX_OBJECT = 0xFFF       # dernier identifiant d'objet autorisé dans un plugin léger
ESL_MIN_OBJECT_OLD = 0x800   # avant l'en-tête 1.71, les identifiants commencent à 0x800
HEDR_VERSION_171 = 1.71


def inspect_and_flag_esl(plugin_path: str | Path, apply_fix: bool = False) -> dict:
    """Lit l'en-tête TES4 d'un plugin Skyrim, vérifie son statut ESL

    et applique le flag si demandé.
    """
    path = Path(plugin_path)
    if not path.is_file():
        raise FileNotFoundError(f"Fichier introuvable : {path}")

    with path.open("r+b" if apply_fix else "rb") as f:
        # Lecture de la signature du premier record (doit être TES4)
        sig = f.read(4)
        if sig != b"TES4":
            raise ValueError(f"{path.name} n'est pas un plugin Skyrim valide (attendu TES4, trouvé {sig}).")

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
    eligible: bool = False
    reason: str = ""


def check_eligibility(plugin_path: str | Path) -> Eligibility:
    """Analyse les en-têtes d'enregistrements (sans décompresser) pour savoir si le plugin
    peut recevoir le drapeau ESL sans casser ses FormID."""
    path = Path(plugin_path)
    res = Eligibility(path=path)
    data = path.read_bytes()
    if data[:4] != b"TES4":
        res.reason = "Ce n'est pas un plugin Skyrim (en-tête TES4 absent)."
        return res
    size, res.flags = struct.unpack_from("<II", data, 4)
    res.already_esl = bool(res.flags & FLAG_ESL)

    # Sous-enregistrements de TES4 : HEDR (version) et MAST (maîtres)
    q, end = 24, 24 + size
    while q + 6 <= end:
        sig = data[q:q + 4]
        sz = struct.unpack_from("<H", data, q + 4)[0]
        if sig == b"HEDR" and sz >= 4:
            res.hedr_version = round(struct.unpack_from("<f", data, q + 6)[0], 2)
        elif sig == b"MAST":
            res.masters += 1
        q += 6 + sz

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
        p += 24 + sz

    if res.already_esl:
        res.eligible, res.reason = False, "Déjà marqué ESL."
    elif res.max_object is not None and res.max_object > ESL_MAX_OBJECT:
        res.reason = (f"FormID propre trop élevé ({res.max_object:06X} > {ESL_MAX_OBJECT:03X}). "
                      "Compactez les FormID dans xEdit avant de le marquer ESL.")
    elif (res.min_object is not None and res.min_object < ESL_MIN_OBJECT_OLD
          and res.hedr_version < HEDR_VERSION_171):
        res.reason = (f"FormID propre sous 0x800 ({res.min_object:06X}) avec un en-tête {res.hedr_version} : "
                      "il faut un en-tête 1.71 (xEdit) pour que le jeu l'accepte.")
    else:
        res.eligible, res.reason = True, "Éligible."
    return res


def backup(path: str | Path) -> Path:
    """Copie de sauvegarde à côté du plugin : <nom>.bak (horodatée si elle existe déjà)."""
    path = Path(path)
    target = path.with_name(path.name + ".bak")
    if target.exists():
        target = path.with_name(f"{path.name}.{time.strftime('%Y%m%d-%H%M%S')}.bak")
    shutil.copy2(path, target)
    return target
