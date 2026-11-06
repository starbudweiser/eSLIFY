// Point d'entrée : fenêtre AppKit unique (860 × 560, redimensionnable) qui héberge l'interface SwiftUI.

import AppKit
import EslCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let model = AppModel()
    var config = Config.load()
    var launchURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.apply()
        // « e » dans le bleu du logo
        Socle.brand("eSLIFY", color: Color(red: 0x2e / 255, green: 0x8a / 255, blue: 0xd0 / 255))
        buildMenu()

        let host = NSHostingView(rootView: ContentView(model: model))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: WINDOW_SIZE),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "eSLIFY"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(Socle.C.bg)
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.setContentSize(WINDOW_SIZE)
        window.socleCenter()
        // Essais en arrière-plan : ESLIFY_QUIET=1 lance l'appli sans prendre le focus
        if ProcessInfo.processInfo.environment["ESLIFY_QUIET"] != nil {
            window.orderBack(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        UpdateEngine.shared.configure(repo: "eSLIFY", lang: { I18n.lang })
        UpdateEngine.shared.start()  // nouvelle version ? (au plus une fois par jour)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { UpdateEngine.shared.installAppMenuItem() }

        // Fichiers passés en arguments (« Ouvrir avec »)
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }.map { URL(fileURLWithPath: $0) }
        model.addPaths(launchURLs + args)

        // Vérification visuelle (développement) : ESLIFY_SNAPSHOT=<fichier.png> enregistre la fenêtre après 2 s et quitte
        if let out = ProcessInfo.processInfo.environment["ESLIFY_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                let view = window.contentView!
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                }
                NSApp.terminate(nil)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if model.rows.isEmpty && window == nil { launchURLs += urls } else { model.addPaths(urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Langue

    /// Change la langue (code ou « auto »), la mémorise et retraduit l'interface.
    @objc func chooseLanguage(_ sender: NSMenuItem) {
        let choice = Config.normalize(sender.representedObject as? String)
        config["language"] = choice
        Config.save(config)
        I18n.setLang(Config.resolve(choice))
        model.retranslate()
        buildMenu()
        UpdateEngine.shared.insertMenuItem()
    }

    @objc func showAbout(_ sender: Any?) { About.show() }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        // Pas de couleur dans les menus : le nom de l'appli y est en texte normal
        let about = appMenu.addItem(withTitle: L("À propos d'eSLIFY"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Masquer eSLIFY"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: L("Masquer les autres"),
                                     action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: L("Tout afficher"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Quitter eSLIFY"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Édition : Cmd+A sélectionne toutes les lignes du tableau
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("Édition"))
        editMenu.addItem(withTitle: L("Tout sélectionner"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        // Menu « Langue » : Automatique + 4 langues, coche sur le choix courant
        let langItem = NSMenuItem()
        let langMenu = NSMenu(title: L("Langue"))
        let current = Config.choice(config)
        func add(_ title: String, _ code: String) {
            let item = langMenu.addItem(withTitle: title, action: #selector(chooseLanguage), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = code == current ? .on : .off
        }
        add(L("Automatique (système)"), Config.auto)
        langMenu.addItem(.separator())
        for (code, label) in Config.menuLangs { add(label, code) }
        langItem.submenu = langMenu
        main.addItem(langItem)

        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: L("Fenêtre"))
        winMenu.addItem(withTitle: L("Réduire"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = winMenu
        main.addItem(winItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = winMenu
    }
}

I18n.setLang(Config.resolve(Config.choice(Config.load())))
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
