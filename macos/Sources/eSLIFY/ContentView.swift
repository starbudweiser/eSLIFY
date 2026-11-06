// Interface : en-tête, boutons d'ajout, tableau des plugins, explication de la ligne choisie, sauvegarde et marquage.
// Mêmes textes, colonnes et statuts que la version Python (Socle : textes × 1,1).

import AppKit
import EslCore
import SwiftUI
import UniformTypeIdentifiers

let WINDOW_SIZE = CGSize(width: 860, height: 560)

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        let _ = model.tick
        VStack(spacing: Socle.M.space3) {
            header
            buttons
            table
            Text(model.message)
                .socle(Socle.T.body).foregroundStyle(color(model.tone))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            bottom
        }
        .padding(Socle.M.space3)
        .frame(minWidth: 640, minHeight: 420)
        .background(Socle.C.bg)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                var urls: [URL] = []
                for p in providers {
                    if let item = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                       let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
                }
                model.addPaths(urls)
            }
            return true
        }
        .alert("eSLIFY", isPresented: $model.confirming) {
            Button(L("Oui")) { model.apply() }
            Button(L("Non"), role: .cancel) {}
        } message: { Text(model.confirmText) }
        .alert("eSLIFY", isPresented: Binding(get: { model.failureText != nil }, set: { if !$0 { model.failureText = nil } })) {
            Button(L("OK")) { model.failureText = nil }
        } message: { Text(model.failureText ?? "") }
    }

    private func color(_ tone: Tone) -> Color {
        switch tone {
        case .none: Socle.C.textMuted
        case .success: Socle.C.success
        case .danger: Socle.C.danger
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(branded: "eSLIFY").socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                Text(L("Marque des plugins comme ESL (light master) après avoir vérifié leurs FormID."))
                    .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2)
        .background(Socle.C.surfaceRaised, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border, lineWidth: 1))
    }

    private var buttons: some View {
        HStack(spacing: Socle.M.space2) {
            Button(L("Ajouter des plugins")) { pickFiles() }
                .buttonStyle(SocleButtonStyle(.action, height: Socle.M.sizeControl - 2)).fixedSize()
            Button(L("Ajouter un dossier")) { pickFolder() }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            Button(L("Vider la liste")) { model.clear() }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            Spacer(minLength: 0)
        }
    }

    private var table: some View {
        Table(model.rows, selection: $model.selection) {
            TableColumn(L("Plugin")) { r in
                Text(r.res.url.lastPathComponent).socle(Socle.T.body).foregroundStyle(Socle.C.text)
            }.width(min: 120, ideal: 200)
            TableColumn(L("Statut")) { r in
                Text(statusText(r.res)).socle(Socle.T.body).foregroundStyle(statusColor(r.res))
            }.width(min: 80, ideal: 100)
            TableColumn(L("Nouveaux enr.")) { r in
                Text(verbatim: String(r.res.newRecords)).socle(Socle.T.mono).foregroundStyle(Socle.C.text)
            }.width(min: 80, ideal: 100)
            TableColumn(L("FormID propres")) { r in
                Text(verbatim: r.res.span).socle(Socle.T.mono).foregroundStyle(Socle.C.text)
            }.width(min: 100, ideal: 120)
            TableColumn(L("Dossier")) { r in
                Text(verbatim: r.res.url.deletingLastPathComponent().path).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Socle.C.bgSunken)
        .overlay(Rectangle().stroke(Socle.C.border, lineWidth: 1))
    }

    private var bottom: some View {
        HStack {
            Toggle(isOn: $model.keepBackup) {
                Text(L("Créer une copie de sauvegarde (.bak) avant modification")).socle(Socle.T.body).foregroundStyle(Socle.C.text)
            }.toggleStyle(.checkbox)
            Spacer(minLength: 0)
            Button(model.applyTitle) { model.askConfirmation() }
                .buttonStyle(SocleButtonStyle(.primary))
                .disabled(model.targets.isEmpty)
                .fixedSize()
        }
    }

    private func statusText(_ r: Eligibility) -> String {
        r.alreadyESL ? L("Déjà ESL") : r.eligible ? L("Éligible") : L("Non éligible")
    }

    private func statusColor(_ r: Eligibility) -> Color {
        r.alreadyESL ? Socle.C.textMuted : r.eligible ? (r.dependents.isEmpty ? Socle.C.success : Socle.C.warning) : Socle.C.danger
    }

    // MARK: Sélecteurs de fichiers

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.title = L("Ajouter des plugins")
        panel.message = L("Plugins Skyrim") + " (*.esp *.esm *.esl)"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = PLUGIN_EXTS.compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { model.addPaths(panel.urls) }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = L("Ajouter un dossier")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { model.addPaths(panel.urls) }
    }
}
