import "@socle/tokens.css";
import "@socle/components/bundle.css";
import "./style.css";
import { L, setLang, systemLang } from "./i18n.js";
import { checkEligibility, decide, samples, span } from "./eslify.js";

const EXTS = [".esp", ".esm", ".esl"];
// Langue : celle du navigateur (comme la langue du Mac dans l'appli), ou ?lang=en|fr|it|es
setLang(new URLSearchParams(location.search).get("lang") || systemLang());
const HINT = L("Ajoutez ou glissez-déposez des fichiers .ESP, .ESM, .ESL ou un dossier.");
const $ = (id) => document.getElementById(id);

const state = { results: [], selected: new Set(), anchor: null };

// -- ajout de fichiers
const isPlugin = (name) => EXTS.some((e) => name.toLowerCase().endsWith(e));

async function addFiles(files) {
  for (const f of files) {
    if (!isPlugin(f.name)) continue;
    const rel = f.webkitRelativePath || f.relativePath || "";
    const folder = rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "(fichier déposé)";
    if (state.results.some((r) => r.name === f.name && r.folder === folder)) continue;
    let res;
    try {
      res = checkEligibility(f.name, folder, await f.arrayBuffer());
    } catch (e) { // fichier tronqué ou corrompu
      res = decide({ name: f.name, folder, newRecords: 0, minObject: null, maxObject: null });
      res.eligible = false;
      res.reason = `Plugin illisible : ${e.message}.`;
    }
    state.results.push(res);
  }
  render();
}

// Dossiers déposés : on ne lit que le premier niveau, comme l'app (iterdir).
async function filesFromDrop(items) {
  const out = [];
  const read = (entry) => new Promise((ok) => entry.file((f) => { f.relativePath = entry.fullPath.slice(1); ok(f); }, () => ok(null)));
  for (const it of items) {
    const entry = it.webkitGetAsEntry?.();
    if (!entry) continue;
    if (entry.isFile) out.push(await read(entry));
    else if (entry.isDirectory) {
      const entries = await new Promise((ok) => entry.createReader().readEntries(ok, () => ok([])));
      for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) if (e.isFile) out.push(await read(e));
    }
  }
  return out.filter(Boolean);
}

// -- affichage
function statusOf(r) {
  if (r.alreadyEsl) return [L("Déjà ESL"), "st-muted"];
  if (r.eligible) return [L("Éligible"), "st-success"];
  return [L("Non éligible"), "st-danger"];
}

function render() {
  const tbody = $("rows");
  tbody.replaceChildren(...state.results.map((r, i) => {
    const [label, cls] = statusOf(r);
    const tr = document.createElement("tr");
    tr.dataset.i = i;
    if (state.selected.has(i)) tr.className = "is-selected";
    const cells = [[r.name], [label, cls], [String(r.newRecords), "num"], [span(r), "num"], [r.folder, "folder grow"]];
    for (const [text, c] of cells) {
      const td = document.createElement("td");
      td.textContent = text;
      if (c) td.className = c;
      if (c?.includes("folder")) td.title = text;
      tr.append(td);
    }
    return tr;
  }));
  $("drop-hint").hidden = state.results.length > 0;
  refreshButton();
}

function showReason() {
  const el = $("reason");
  el.className = "reason";
  if (state.selected.size === 1) {
    const r = state.results[[...state.selected][0]];
    const extra = r.hedrVersion ? `  En-tête ${r.hedrVersion}, ${r.masters} maître(s).` : "";
    el.textContent = `${r.name} : ${r.reason}${extra}`;
  }
}

// Plugins éligibles parmi la sélection (ou toute la liste si rien n'est sélectionné).
function targets() {
  const pool = state.selected.size ? [...state.selected].map((i) => state.results[i]) : state.results;
  return pool.filter((r) => r.eligible);
}

function refreshButton() {
  const n = targets().length;
  $("apply").disabled = n === 0;
  $("apply").textContent = n ? L("MARQUER ESL ({n})", { n }) : L("MARQUER ESL");
}

// -- sélection (clic, ⌘/Ctrl-clic, Maj-clic)
$("rows").addEventListener("click", (e) => {
  const tr = e.target.closest("tr");
  if (!tr) return;
  const i = Number(tr.dataset.i);
  if (e.shiftKey && state.anchor !== null) {
    const [a, b] = [Math.min(state.anchor, i), Math.max(state.anchor, i)];
    if (!(e.metaKey || e.ctrlKey)) state.selected.clear();
    for (let k = a; k <= b; k++) state.selected.add(k);
  } else if (e.metaKey || e.ctrlKey) {
    state.selected.has(i) ? state.selected.delete(i) : state.selected.add(i);
    state.anchor = i;
  } else {
    state.selected = new Set([i]);
    state.anchor = i;
  }
  render();
  showReason();
});

// -- boutons
$("add-files").onclick = () => $("pick-files").click();
$("add-dir").onclick = () => $("pick-dir").click();
$("pick-files").onchange = (e) => { addFiles([...e.target.files]); e.target.value = ""; };
$("pick-dir").onchange = (e) => {
  // L'app ne lit que le premier niveau du dossier.
  const top = [...e.target.files].filter((f) => f.webkitRelativePath.split("/").length === 2);
  addFiles(top.sort((a, b) => a.name.localeCompare(b.name)));
  e.target.value = "";
};
$("clear").onclick = () => {
  state.results = [];
  state.selected.clear();
  state.anchor = null;
  $("reason").className = "reason";
  $("reason").textContent = HINT;
  render();
};
$("samples").onclick = () => {
  state.results = samples();
  state.selected.clear();
  state.anchor = null;
  $("reason").className = "reason";
  $("reason").textContent = HINT;
  render();
};

// -- glisser-déposer
const drop = $("window");
drop.addEventListener("dragover", (e) => { e.preventDefault(); $("drop").classList.add("is-over"); });
drop.addEventListener("dragleave", (e) => { if (!drop.contains(e.relatedTarget)) $("drop").classList.remove("is-over"); });
drop.addEventListener("drop", async (e) => {
  e.preventDefault();
  $("drop").classList.remove("is-over");
  addFiles(await filesFromDrop([...e.dataTransfer.items]));
});

// -- application (simulée : l'aperçu ne modifie aucun fichier)
function confirmDialog(body) {
  return new Promise((ok) => {
    $("dlg-body").textContent = body;
    $("modal").hidden = false;
    $("dlg-yes").focus();
    const close = (v) => { $("modal").hidden = true; document.removeEventListener("keydown", onKey); ok(v); };
    const onKey = (e) => { if (e.key === "Escape") close(false); };
    document.addEventListener("keydown", onKey);
    $("dlg-yes").onclick = () => close(true);
    $("dlg-no").onclick = () => close(false);
  });
}

$("apply").onclick = async () => {
  const todo = targets();
  if (!todo.length) return;
  const keep = $("backup").checked;
  const msg = L("Marquer {n} plugin(s) comme ESL ?", { n: todo.length }) + "\n\n" + todo.slice(0, 15).map((r) => r.name).join("\n")
    + (todo.length > 15 ? "\n…" : "")
    + "\n\n" + (keep ? L("Une copie .bak de chaque fichier est créée avant modification.") : L("Aucune copie de sauvegarde ne sera créée."));
  if (!(await confirmDialog(msg))) return;
  for (const r of todo) {
    r.flags |= 0x0200;
    r.alreadyEsl = true;
    decide(r);
  }
  render();
  $("reason").className = "reason success";
  $("reason").textContent = L("{n} plugin(s) marqué(s) ESL.", { n: todo.length }) + " (simulation)";
};

// -- thème
$("theme").onclick = () => {
  const html = document.documentElement;
  const light = html.dataset.theme !== "light";
  html.dataset.theme = light ? "light" : "dark";
  $("theme").textContent = light ? "Thème sombre" : "Thème clair";
};

$("reason").textContent = HINT;
render();

// -- textes fixes de la page (clés de i18n/strings.json)
const fixed = {
  ".header-bar .meta": "Marque des plugins comme ESL (light master) après avoir vérifié leurs FormID.",
  "#add-files": "Ajouter des plugins", "#add-dir": "Ajouter un dossier", "#clear": "Vider la liste",
  "th:nth-child(1)": "Plugin", "th:nth-child(2)": "Statut", "th:nth-child(3)": "Nouveaux enr.",
  "th:nth-child(4)": "FormID propres", "th:nth-child(5)": "Dossier",
};
for (const [sel, key] of Object.entries(fixed)) document.querySelector(sel).textContent = L(key);
document.querySelector("#backup-label").lastChild.textContent = "\n          " + L("Créer une copie de sauvegarde (.bak) avant modification") + "\n";
