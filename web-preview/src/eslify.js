// Portage JS de check_eligibility() (src/eslify_core.py) : lecture seule, rien n'est écrit.
const FLAG_ESL = 0x0200;
const ESL_MAX_OBJECT = 0xfff;
const ESL_MIN_OBJECT_OLD = 0x800;
const HEDR_VERSION_171 = 1.71;
const WORLD_RECORDS = ["CELL", "WRLD"]; // nouveaux enregistrements interdits dans un plugin léger

const hex = (v, w) => v.toString(16).toUpperCase().padStart(w, "0");
const sig = (dv, at) => String.fromCharCode(dv.getUint8(at), dv.getUint8(at + 1), dv.getUint8(at + 2), dv.getUint8(at + 3));

export function checkEligibility(name, folder, buffer) {
  const res = { name, folder, flags: 0, alreadyEsl: false, masters: 0, newRecords: 0,
    minObject: null, maxObject: null, hedrVersion: 0, newCells: 0, eligible: false, reason: "" };
  const dv = new DataView(buffer);
  if (dv.byteLength < 24 || sig(dv, 0) !== "TES4") {
    res.reason = "Ce n'est pas un plugin Skyrim (en-tête TES4 absent).";
    return res;
  }
  const size = dv.getUint32(4, true);
  res.flags = dv.getUint32(8, true);
  res.alreadyEsl = Boolean(res.flags & FLAG_ESL);

  // Sous-enregistrements de TES4 : HEDR (version) et MAST (maîtres)
  let q = 24;
  const end = Math.min(24 + size, dv.byteLength);
  while (q + 6 <= end) {
    const s = sig(dv, q);
    const sz = dv.getUint16(q + 4, true);
    if (s === "HEDR" && sz >= 4) res.hedrVersion = Math.round(dv.getFloat32(q + 6, true) * 100) / 100;
    else if (s === "MAST") res.masters += 1;
    q += 6 + sz;
  }

  // Enregistrements : on descend dans les groupes sans lire les données
  let p = 24 + size;
  while (p + 24 <= dv.byteLength) {
    const sz = dv.getUint32(p + 4, true);
    if (sig(dv, p) === "GRUP") { p += 24; continue; }
    const formId = dv.getUint32(p + 12, true);
    if (formId >>> 24 === res.masters) {
      const obj = formId & 0xffffff;
      res.newRecords += 1;
      res.minObject = res.minObject === null ? obj : Math.min(res.minObject, obj);
      res.maxObject = res.maxObject === null ? obj : Math.max(res.maxObject, obj);
      if (WORLD_RECORDS.includes(sig(dv, p))) res.newCells += 1;
    }
    p += 24 + sz;
  }
  return decide(res);
}

export function decide(res) {
  res.eligible = false;
  if (res.alreadyEsl) {
    res.reason = "Déjà marqué ESL.";
  } else if (res.newCells) {
    res.reason = `Ajoute ${res.newCells} cellule(s) ou worldspace(s) : le jeu gère mal les nouvelles cellules `
      + "d'un plugin ESL (modifications perdues, objets qui disparaissent).";
  } else if (res.maxObject !== null && res.maxObject > ESL_MAX_OBJECT) {
    res.reason = `FormID propre trop élevé (${hex(res.maxObject, 6)} > ${hex(ESL_MAX_OBJECT, 3)}). `
      + "Compactez les FormID dans xEdit avant de le marquer ESL.";
  } else if (res.minObject !== null && res.minObject < ESL_MIN_OBJECT_OLD && res.hedrVersion < HEDR_VERSION_171) {
    res.reason = `FormID propre sous 0x800 (${hex(res.minObject, 6)}) avec un en-tête ${res.hedrVersion} : `
      + "il faut un en-tête 1.71 (xEdit) pour que le jeu l'accepte.";
  } else {
    res.eligible = true;
    res.reason = "Éligible.";
  }
  return res;
}

export const span = (r) => (r.maxObject === null ? "—" : `${hex(r.minObject, 3)} – ${hex(r.maxObject, 3)}`);

// Jeu d'exemples pour voir les trois statuts sans fichiers sous la main.
export function samples() {
  const base = "/Users/stephan/Games/Skyrim Special Edition/Data";
  const mk = (name, o) => decide({ name, folder: base, flags: 0, alreadyEsl: false, masters: 1, newRecords: 0,
    minObject: null, maxObject: null, hedrVersion: 1.71, eligible: false, reason: "", ...o });
  return [
    mk("BetterQuestObjectives.esp", { newRecords: 42, minObject: 0x800, maxObject: 0x8a3 }),
    mk("ImmersiveArmors.esp", { masters: 2, newRecords: 3120, minObject: 0x800, maxObject: 0x1f4c2 }),
    mk("FlowerGirls_Patch.esp", { masters: 3, newRecords: 6, minObject: 0x801, maxObject: 0x806 }),
    mk("RiverwoodHome.esp", { newRecords: 58, minObject: 0x800, maxObject: 0x83a, newCells: 2 }),
    mk("OldTweaks.esp", { hedrVersion: 0.94, newRecords: 12, minObject: 0x012, maxObject: 0x01d }),
    mk("ccBGSSSE001-Fish.esm", { flags: FLAG_ESL, alreadyEsl: true, masters: 1, newRecords: 870, minObject: 0x800, maxObject: 0xb65 }),
    mk("NoRecords.esp", { masters: 1, newRecords: 0 }),
  ];
}
