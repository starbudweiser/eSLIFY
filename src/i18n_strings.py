"""Traductions : {texte français: (anglais, italien, espagnol)}.

Les placeholders {x} doivent rester identiques dans toutes les langues (vérifié par
tests/test_i18n.py).
"""

TR = {
    # ------------------------------------------------------------ fenêtre
    "Marque des plugins comme ESL (light master) après avoir vérifié leurs FormID.": (
        "Flags plugins as ESL (light master) after checking their FormIDs.",
        "Contrassegna i plugin come ESL (light master) dopo averne verificato i FormID.",
        "Marca los plugins como ESL (light master) tras comprobar sus FormID."),
    "Ajouter des plugins": ("Add plugins", "Aggiungi plugin", "Añadir plugins"),
    "Ajouter un dossier": ("Add a folder", "Aggiungi una cartella", "Añadir una carpeta"),
    "Vider la liste": ("Clear list", "Svuota l'elenco", "Vaciar la lista"),
    "Plugins Skyrim": ("Skyrim plugins", "Plugin di Skyrim", "Plugins de Skyrim"),
    "Plugin": ("Plugin", "Plugin", "Plugin"),
    "Statut": ("Status", "Stato", "Estado"),
    "Nouveaux enr.": ("New records", "Nuovi record", "Registros nuevos"),
    "FormID propres": ("Own FormIDs", "FormID propri", "FormID propios"),
    "Dossier": ("Folder", "Cartella", "Carpeta"),
    "Créer une copie de sauvegarde (.bak) avant modification": (
        "Create a backup copy (.bak) before modifying",
        "Crea una copia di backup (.bak) prima della modifica",
        "Crear una copia de seguridad (.bak) antes de modificar"),
    "Ajoutez ou glissez-déposez des fichiers .ESP, .ESM, .ESL ou un dossier.": (
        "Add or drag and drop .ESP, .ESM, .ESL files or a folder.",
        "Aggiungi o trascina file .ESP, .ESM, .ESL o una cartella.",
        "Añade o arrastra archivos .ESP, .ESM, .ESL o una carpeta."),
    "Langue : {name}": ("Language: {name}", "Lingua: {name}", "Idioma: {name}"),
    "Automatique ({lang})": ("Automatic ({lang})", "Automatica ({lang})", "Automático ({lang})"),
    # ------------------------------------------------------------ liste
    "Déjà ESL": ("Already ESL", "Già ESL", "Ya ESL"),
    "Éligible": ("Eligible", "Idoneo", "Apto"),
    "Non éligible": ("Not eligible", "Non idoneo", "No apto"),
    "En-tête {version}, {n} maître(s).": (
        "Header {version}, {n} master(s).", "Intestazione {version}, {n} master.", "Cabecera {version}, {n} máster(es)."),
    "{name} : {reason}": ("{name}: {reason}", "{name}: {reason}", "{name}: {reason}"),
    "Lecture impossible : {err}.": ("Cannot read file: {err}.", "Lettura impossibile: {err}.", "No se puede leer: {err}."),
    "Plugin illisible : {err}.": ("Unreadable plugin: {err}.", "Plugin illeggibile: {err}.", "Plugin ilegible: {err}."),
    # ------------------------------------------------------------ verdicts
    "Ce n'est pas un plugin Skyrim (en-tête TES4 absent).": (
        "Not a Skyrim plugin (TES4 header missing).",
        "Non è un plugin di Skyrim (intestazione TES4 assente).",
        "No es un plugin de Skyrim (falta la cabecera TES4)."),
    "Déjà marqué ESL.": ("Already flagged ESL.", "Già contrassegnato ESL.", "Ya marcado como ESL."),
    "FormID propre trop élevé ({max} > {limit}). Compactez les FormID dans xEdit avant de le marquer ESL.": (
        "Own FormID too high ({max} > {limit}). Compact the FormIDs in xEdit before flagging it ESL.",
        "FormID proprio troppo alto ({max} > {limit}). Compatta i FormID in xEdit prima di contrassegnarlo ESL.",
        "FormID propio demasiado alto ({max} > {limit}). Compacta los FormID en xEdit antes de marcarlo como ESL."),
    "FormID propre sous 0x800 ({min}) avec un en-tête {version} : il faut un en-tête 1.71 (xEdit) pour que le jeu l'accepte.": (
        "Own FormID below 0x800 ({min}) with header {version}: the game needs a 1.71 header (xEdit) to accept it.",
        "FormID proprio sotto 0x800 ({min}) con intestazione {version}: serve un'intestazione 1.71 (xEdit) perché il gioco lo accetti.",
        "FormID propio por debajo de 0x800 ({min}) con cabecera {version}: el juego necesita una cabecera 1.71 (xEdit) para aceptarlo."),
    "Ajoute {n} cellule(s) ou worldspace(s) : le jeu gère mal les nouvelles cellules d'un plugin ESL (modifications perdues, objets qui disparaissent).": (
        "Adds {n} cell(s) or worldspace(s): the game handles new cells in an ESL plugin badly (lost changes, disappearing objects).",
        "Aggiunge {n} cella/e o worldspace: il gioco gestisce male le nuove celle di un plugin ESL (modifiche perse, oggetti che spariscono).",
        "Añade {n} celda(s) o worldspace(s): el juego gestiona mal las celdas nuevas de un plugin ESL (cambios perdidos, objetos que desaparecen)."),
    "Éligible, mais {n} plugin(s) en dépendent ({names}) : ne compactez plus ses FormID après le marquage, ils casseraient.": (
        "Eligible, but {n} plugin(s) depend on it ({names}): do not compact its FormIDs after flagging, they would break.",
        "Idoneo, ma {n} plugin ne dipendono ({names}): non compattare più i suoi FormID dopo il contrassegno, si romperebbero.",
        "Apto, pero {n} plugin(s) dependen de él ({names}): no compactes sus FormID después de marcarlo, se romperían."),
    "Éligible.": ("Eligible.", "Idoneo.", "Apto."),
    # ------------------------------------------------------------ marquage
    "MARQUER ESL": ("FLAG ESL", "CONTRASSEGNA ESL", "MARCAR ESL"),
    "MARQUER ESL ({n})": ("FLAG ESL ({n})", "CONTRASSEGNA ESL ({n})", "MARCAR ESL ({n})"),
    "Marquer {n} plugin(s) comme ESL ?": (
        "Flag {n} plugin(s) as ESL?", "Contrassegnare {n} plugin come ESL?", "¿Marcar {n} plugin(s) como ESL?"),
    "Une copie .bak de chaque fichier est créée avant modification.": (
        "A .bak copy of each file is created before modifying it.",
        "Prima della modifica viene creata una copia .bak di ogni file.",
        "Se crea una copia .bak de cada archivo antes de modificarlo."),
    "Aucune copie de sauvegarde ne sera créée.": (
        "No backup copy will be created.", "Non verrà creata alcuna copia di backup.", "No se creará ninguna copia de seguridad."),
    "{n} plugin(s) marqué(s) ESL.": (
        "{n} plugin(s) flagged ESL.", "{n} plugin contrassegnati ESL.", "{n} plugin(s) marcado(s) como ESL."),
    "{n} échec(s).": ("{n} failure(s).", "{n} errore/i.", "{n} fallo(s)."),
    "Échecs :": ("Failures:", "Errori:", "Fallos:"),
}
