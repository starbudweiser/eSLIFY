// État de l'appli : liste des plugins analysés, sélection, message sous le tableau, marquage.

import AppKit
import EslCore
import Observation
import SwiftUI

struct PluginRow: Identifiable {
    var res: Eligibility
    var id: URL { res.url }
}

enum Tone { case none, success, danger }

@MainActor @Observable
final class AppModel {
    var rows: [PluginRow] = []
    var selection: Set<URL> = [] { didSet { if selection != oldValue { selectionChanged() } } }
    var keepBackup = true
    var tone: Tone = .none
    var message = ""
    var tick = 0  // change à chaque retraduction (changement de langue)

    // Dialogues
    var confirming = false
    var confirmText = ""
    var failureText: String?

    init() { message = hint }

    var hint: String { L("Ajoutez ou glissez-déposez des fichiers .ESP, .ESM, .ESL ou un dossier.") }

    // MARK: Ajout

    func addPaths(_ paths: [URL]) {
        let known = Set(rows.map(\.id))
        var seen = known
        let files = pluginFiles(in: paths).filter { seen.insert($0).inserted }
        guard !files.isEmpty else { return }
        // Analyse hors du fil principal (un dossier peut contenir des centaines de plugins)
        Task {
            let results = await Task.detached(priority: .userInitiated) { files.map { checkEligibilitySafe($0) } }.value
            rows += results.map(PluginRow.init)
        }
    }

    func clear() {
        rows = []
        selection = []
        tone = .none
        message = hint
    }

    // MARK: Sélection et message

    /// Une seule ligne choisie : verdict et en-tête ; sinon le message reste, sans couleur (comme la version Python).
    func selectionChanged() {
        tone = .none
        guard selection.count == 1, let r = rows.first(where: { $0.id == selection.first })?.res else { return }
        let extra = r.hedrVersion != 0 ? "  " + L("En-tête {version}, {n} maître(s).", ["version": pyFloat(r.hedrVersion), "n": r.masters]) : ""
        message = L("{name} : {reason}", ["name": r.url.lastPathComponent, "reason": r.reason]) + extra
    }

    /// Plugins éligibles parmi la sélection (ou toute la liste si rien n'est sélectionné).
    var targets: [Eligibility] {
        let chosen = selection.isEmpty ? rows : rows.filter { selection.contains($0.id) }
        return chosen.map(\.res).filter(\.eligible)
    }

    var applyTitle: String {
        let n = targets.count
        return n > 0 ? L("MARQUER ESL ({n})", ["n": n]) : L("MARQUER ESL")
    }

    // MARK: Marquage

    func askConfirmation() {
        let todo = targets
        guard !todo.isEmpty else { return }
        confirmText = L("Marquer {n} plugin(s) comme ESL ?", ["n": todo.count]) + "\n\n"
            + todo.prefix(15).map { $0.url.lastPathComponent }.joined(separator: "\n") + (todo.count > 15 ? "\n…" : "") + "\n\n"
            + (keepBackup ? L("Une copie .bak de chaque fichier est créée avant modification.") : L("Aucune copie de sauvegarde ne sera créée."))
        confirming = true
    }

    func apply() {
        let todo = targets
        guard !todo.isEmpty else { return }
        var done = 0
        var errors: [String] = []
        for r in todo {
            do {
                if keepBackup { try backup(r.url) }
                if try inspectAndFlagESL(r.url, applyFix: true).modified { done += 1 }
                if let i = rows.firstIndex(where: { $0.id == r.url }) { rows[i] = PluginRow(res: checkEligibilitySafe(r.url)) }
            } catch {
                errors.append(L("{name} : {reason}", ["name": r.url.lastPathComponent, "reason": Self.describe(error)]))
            }
        }
        selection = []
        let text = L("{n} plugin(s) marqué(s) ESL.", ["n": done])
        tone = errors.isEmpty ? .success : .danger
        message = text + (errors.isEmpty ? "" : " " + L("{n} échec(s).", ["n": errors.count]))
        if !errors.isEmpty {
            failureText = text + "\n\n" + L("Échecs :") + "\n" + errors.prefix(15).joined(separator: "\n")
        }
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? PluginError { return e.description }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain { return String(cString: strerror(Int32(ns.code))) }
        return ns.localizedFailureReason ?? ns.localizedDescription
    }

    // MARK: Langue

    /// Retraduit l'interface : les verdicts sont recalculés dans la langue active.
    func retranslate() {
        tick += 1
        rows = rows.map { PluginRow(res: checkEligibilitySafe($0.id)) }
        if selection.isEmpty { tone = .none; message = hint } else { selectionChanged() }
    }
}

