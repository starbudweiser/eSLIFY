// Cœur d'eSLIFY : lecture et pose du drapeau ESL (light master) des plugins Skyrim SE.
// Traduction ligne à ligne de src/eslify_core.py (version Python), sans interface.
//
// inspectAndFlagESL() lit l'en-tête TES4 et pose le drapeau en ne réécrivant que 4 octets.
// checkEligibility() vérifie, avant de poser le drapeau, que les FormID propres au plugin tiennent dans la plage des
// plugins légers : sinon le jeu les renumérote et le plugin casse. Elle refuse aussi les plugins qui ajoutent des
// cellules ou des worldspaces et signale ceux dont d'autres plugins du dossier dépendent.

import Foundation

public let FLAG_ESL: UInt32 = 0x0200
public let ESL_MAX_OBJECT: UInt32 = 0xFFF        // dernier identifiant d'objet autorisé dans un plugin léger
public let ESL_MIN_OBJECT_OLD: UInt32 = 0x800    // avant l'en-tête 1.71, les identifiants commencent à 0x800
public let HEDR_VERSION_171 = 1.71
public let PLUGIN_EXTS = ["esp", "esm", "esl"]

/// Erreur de lecture d'un plugin (fichier tronqué ou invalide) : le message est affiché tel quel.
public struct PluginError: Error, CustomStringConvertible {
    public let description: String
    init(_ d: String) { description = d }
}

// MARK: Lecture binaire

extension Data {
    /// Octets lus à `offset` (Data peut avoir un startIndex non nul) ; échoue si le fichier est tronqué.
    func u32(_ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw PluginError("fichier tronqué (octet \(offset))") }
        let i = startIndex + offset
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }

    func u16(_ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw PluginError("fichier tronqué (octet \(offset))") }
        let i = startIndex + offset
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }

    func sig(_ offset: Int) -> [UInt8] {
        guard offset >= 0, offset + 4 <= count else { return [] }
        return Array(self[(startIndex + offset)..<(startIndex + offset + 4)])
    }
}

let TES4: [UInt8] = Array("TES4".utf8)
let GRUP: [UInt8] = Array("GRUP".utf8)
let HEDR: [UInt8] = Array("HEDR".utf8)
let MAST: [UInt8] = Array("MAST".utf8)
let CELL: [UInt8] = Array("CELL".utf8)
let WRLD: [UInt8] = Array("WRLD".utf8)

/// Windows-1252 : 0x80–0x9F ont des caractères propres ; les 5 octets non définis donnent U+FFFD (comme Python, errors="replace").
private let cp1252High: [UInt32] = [
    0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
    0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178,
]

func decodeCP1252<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    var out = String.UnicodeScalarView()
    for b in bytes {
        let v: UInt32 = (b >= 0x80 && b < 0xA0) ? cp1252High[Int(b) - 0x80] : UInt32(b)
        out.append(Unicode.Scalar(v) ?? "\u{FFFD}")
    }
    return String(out)
}

/// Représentation d'un `bytes` Python (b'abcd'), pour le message « trouvé {sig} ».
func pythonBytesRepr(_ bytes: [UInt8]) -> String {
    let useDouble = bytes.contains(0x27) && !bytes.contains(0x22)
    let quote: UInt8 = useDouble ? 0x22 : 0x27
    var s = "b" + String(UnicodeScalar(quote))
    for b in bytes {
        switch b {
        case quote: s += "\\" + String(UnicodeScalar(b))
        case 0x5C: s += "\\\\"
        case 0x09: s += "\\t"
        case 0x0A: s += "\\n"
        case 0x0D: s += "\\r"
        case 0x20..<0x7F: s += String(UnicodeScalar(b))
        default: s += String(format: "\\x%02x", b)
        }
    }
    return s + String(UnicodeScalar(quote))
}

// MARK: inspect_and_flag_esl

public struct FlagResult: Equatable {
    public var file: String
    public var alreadyESL: Bool
    public var modified: Bool
    public var previousFlags: String?
    public var newFlags: String?
    public var currentFlags: String?
}

/// Lit l'en-tête TES4 d'un plugin Skyrim, vérifie son statut ESL et applique le drapeau si demandé
/// (réécriture des 4 octets des drapeaux, offset 8, et rien d'autre).
public func inspectAndFlagESL(_ url: URL, applyFix: Bool = false) throws -> FlagResult {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
        throw PluginError(L("Fichier introuvable : {path}", ["path": url.path]))
    }
    let name = url.lastPathComponent
    let handle = applyFix ? try FileHandle(forUpdating: url) : try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    // Signature du premier enregistrement (doit être TES4), puis octets 8 à 11 : drapeaux (uint32 petit-boutiste)
    let head = try handle.read(upToCount: 12) ?? Data()
    let sig = Array(head.prefix(4))
    guard sig == TES4 else {
        throw PluginError(L("{name} n'est pas un plugin Skyrim valide (attendu TES4, trouvé {sig}).",
                            ["name": name, "sig": pythonBytesRepr(sig)]))
    }
    let flags = try head.u32(8)
    let isESL = flags & FLAG_ESL != 0

    if applyFix && !isESL {
        let new = flags | FLAG_ESL
        try handle.seek(toOffset: 8)
        try handle.write(contentsOf: Data([UInt8(new & 0xFF), UInt8(new >> 8 & 0xFF), UInt8(new >> 16 & 0xFF), UInt8(new >> 24 & 0xFF)]))
        return FlagResult(file: name, alreadyESL: false, modified: true,
                          previousFlags: "0x" + String(flags, radix: 16), newFlags: "0x" + String(new, radix: 16))
    }
    return FlagResult(file: name, alreadyESL: isESL, modified: false, currentFlags: "0x" + String(flags, radix: 16))
}

// MARK: Maîtres

/// Version HEDR (arrondie à 2 décimales) et noms des maîtres (MAST) lus dans l'en-tête TES4.
public func readMasters(_ data: Data) throws -> (version: Double, masters: [String]) {
    let size = Int(try data.u32(4))
    var version = 0.0
    var masters: [String] = []
    var q = 24
    let end = min(24 + size, data.count)
    while q + 6 <= end {
        let sig = data.sig(q)
        let sz = Int(try data.u16(q + 4))
        if sig == HEDR && sz >= 4 {
            let bits = try data.u32(q + 6)
            let f = Double(Float(bitPattern: bits))
            // Arrondi à 2 décimales sur la valeur binaire exacte, comme round() de Python
            version = Double(String(format: "%.2f", f)) ?? f
        } else if sig == MAST {
            let lo = min(q + 6, data.count), hi = min(q + 6 + sz, data.count)
            let raw = data[(data.startIndex + lo)..<(data.startIndex + hi)]
            masters.append(decodeCP1252(raw.prefix { $0 != 0 }))
        }
        q += 6 + sz
    }
    return (version, masters)
}

/// Début du fichier jusqu'à la fin de l'en-tête TES4 (vide si ce n'est pas un plugin).
func header(of url: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let head = try handle.read(upToCount: 24) ?? Data()
    guard head.count >= 24, Array(head.prefix(4)) == TES4 else { return Data() }
    let size = Int(try head.u32(4))
    return head + (try handle.read(upToCount: size) ?? Data())
}

func hasPluginExtension(_ name: String) -> Bool {
    // Comme Path.suffix de Python : après le dernier point, mais pas pour un nom caché (« .esp »)
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex, name.index(after: dot) != name.endIndex else { return false }
    return PLUGIN_EXTS.contains(name[name.index(after: dot)...].lowercased())
}

/// Ordre des noms de fichiers comme `sorted()` de Python : par point de code.
func codepointLess(_ a: String, _ b: String) -> Bool {
    a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars) { $0.value < $1.value }
}

/// Cache des maîtres par dossier, relu quand la date de modification du dossier change (8 dossiers au plus).
final class MastersCache: @unchecked Sendable {
    static let shared = MastersCache()
    private let lock = NSLock()
    private var entries: [(folder: String, mtime: Int64, table: [(name: String, masters: [String])])] = []

    func table(for folder: URL) -> [(name: String, masters: [String])] {
        let key = folder.path
        let mtime = Self.mtimeNs(folder)
        lock.lock(); defer { lock.unlock() }
        if let i = entries.firstIndex(where: { $0.folder == key && $0.mtime == mtime }) {
            let hit = entries.remove(at: i)
            entries.append(hit)
            return hit.table
        }
        entries.removeAll { $0.folder == key }
        let table = Self.scan(folder)
        entries.append((key, mtime, table))
        if entries.count > 8 { entries.removeFirst() }
        return table
    }

    static func mtimeNs(_ url: URL) -> Int64 {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return 0 }
        return Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
    }

    /// Maîtres (en minuscules) de chaque plugin du dossier, dans l'ordre alphabétique.
    static func scan(_ folder: URL) -> [(name: String, masters: [String])] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted(by: codepointLess)
        var table: [(String, [String])] = []
        for name in names where hasPluginExtension(name) {
            let other = folder.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: other.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            guard let head = try? header(of: other), !head.isEmpty else { continue }
            if let m = try? readMasters(head) { table.append((name, m.masters.map { $0.lowercased() })) }
        }
        return table
    }
}

/// Plugins du même dossier qui déclarent ce plugin comme maître.
public func dependents(of url: URL) -> [String] {
    let name = url.lastPathComponent.lowercased()
    let table = MastersCache.shared.table(for: url.deletingLastPathComponent())
    return table.filter { $0.name != url.lastPathComponent && $0.masters.contains(name) }.map(\.name)
}

// MARK: Éligibilité

public struct Eligibility {
    public var url: URL
    public var flags: UInt32 = 0
    public var alreadyESL = false
    public var masters = 0
    public var newRecords = 0
    public var minObject: UInt32?
    public var maxObject: UInt32?
    public var hedrVersion = 0.0
    public var newCells = 0
    public var dependents: [String] = []
    public var eligible = false
    public var reason = ""

    public init(url: URL, reason: String = "") {
        self.url = url
        self.reason = reason
    }

    /// Plage des FormID propres affichée dans le tableau : « 801 – 8FF », « — » sans enregistrement propre.
    public var span: String {
        guard let lo = minObject, let hi = maxObject else { return "—" }
        return String(format: "%03X – %03X", lo, hi)
    }
}

/// Valeur d'un float telle que Python l'écrit (1.7, 1.71, 0.0).
public func pyFloat(_ v: Double) -> String { v == v.rounded() && abs(v) < 1e16 ? String(format: "%.1f", v) : "\(v)" }

/// Analyse les en-têtes d'enregistrements (sans décompresser) pour savoir si le plugin peut recevoir le drapeau ESL
/// sans casser ses FormID. `dependents` : plugins qui dépendent de celui-ci ; par défaut, cherchés dans son dossier.
public func checkEligibility(_ url: URL, dependents given: [String]? = nil) throws -> Eligibility {
    var res = Eligibility(url: url)
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard data.sig(0) == TES4 else {
        res.reason = L("Ce n'est pas un plugin Skyrim (en-tête TES4 absent).")
        return res
    }
    let size = Int(try data.u32(4))
    res.flags = try data.u32(8)
    res.alreadyESL = res.flags & FLAG_ESL != 0
    let parsed = try readMasters(data)
    res.hedrVersion = parsed.version
    res.masters = parsed.masters.count
    let end = 24 + size

    // Enregistrements : on descend dans les groupes sans lire les données
    var p = end
    let n = data.count
    while p + 24 <= n {
        let sig = data.sig(p)
        let sz = Int(try data.u32(p + 4))
        if sig == GRUP {
            p += 24
            continue
        }
        let formID = try data.u32(p + 12)
        if Int(formID >> 24) == res.masters {
            let obj = formID & 0xFFFFFF
            res.newRecords += 1
            res.minObject = res.minObject.map { min($0, obj) } ?? obj
            res.maxObject = res.maxObject.map { max($0, obj) } ?? obj
            if sig == CELL || sig == WRLD { res.newCells += 1 }
        }
        p += 24 + sz
    }
    res.dependents = given ?? EslCore.dependents(of: url)

    if res.alreadyESL {
        res.eligible = false
        res.reason = L("Déjà marqué ESL.")
    } else if res.newCells > 0 {
        res.reason = L("Ajoute {n} cellule(s) ou worldspace(s) : le jeu gère mal les nouvelles cellules d'un plugin ESL (modifications perdues, objets qui disparaissent).",
                       ["n": res.newCells])
    } else if let hi = res.maxObject, hi > ESL_MAX_OBJECT {
        res.reason = L("FormID propre trop élevé ({max} > {limit}). Compactez les FormID dans xEdit avant de le marquer ESL.",
                       ["max": String(format: "%06X", hi), "limit": String(format: "%03X", ESL_MAX_OBJECT)])
    } else if let lo = res.minObject, lo < ESL_MIN_OBJECT_OLD, res.hedrVersion < HEDR_VERSION_171 {
        res.reason = L("FormID propre sous 0x800 ({min}) avec un en-tête {version} : il faut un en-tête 1.71 (xEdit) pour que le jeu l'accepte.",
                       ["min": String(format: "%06X", lo), "version": pyFloat(res.hedrVersion)])
    } else if !res.dependents.isEmpty {
        res.eligible = true
        res.reason = L("Éligible, mais {n} plugin(s) en dépendent ({names}) : ne compactez plus ses FormID après le marquage, ils casseraient.",
                       ["n": res.dependents.count,
                        "names": res.dependents.prefix(3).joined(separator: ", ") + (res.dependents.count > 3 ? "…" : "")])
    } else {
        res.eligible = true
        res.reason = L("Éligible.")
    }
    return res
}

/// Comme checkEligibility, mais une erreur devient un verdict « non éligible » avec son explication (jamais d'exception).
public func checkEligibilitySafe(_ url: URL) -> Eligibility {
    do {
        return try checkEligibility(url)
    } catch let e as PluginError {
        return Eligibility(url: url, reason: L("Plugin illisible : {err}.", ["err": e.description]))
    } catch {
        let ns = error as NSError
        var code = ns.domain == NSPOSIXErrorDomain ? Int32(ns.code) : 0
        if code == 0, let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError, under.domain == NSPOSIXErrorDomain { code = Int32(under.code) }
        if code != 0 {
            return Eligibility(url: url, reason: L("Lecture impossible : {err}.", ["err": String(cString: strerror(code))]))
        }
        return Eligibility(url: url, reason: L("Plugin illisible : {err}.", ["err": error.localizedDescription]))
    }
}

// MARK: Sauvegarde

/// Copie de sauvegarde à côté du plugin : <nom>.bak (horodatée AAAAMMJJ-HHMMSS si elle existe déjà),
/// avec les dates du fichier conservées. Une copie existante n'est jamais écrasée.
@discardableResult
public func backup(_ url: URL, now: Date = Date()) throws -> URL {
    let fm = FileManager.default
    let dir = url.deletingLastPathComponent()
    var target = dir.appendingPathComponent(url.lastPathComponent + ".bak")
    if fm.fileExists(atPath: target.path) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: now)
        target = dir.appendingPathComponent("\(url.lastPathComponent).\(stamp).bak")
        var k = 2
        while fm.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent("\(url.lastPathComponent).\(stamp)-\(k).bak")
            k += 1
        }
    }
    try fm.copyItem(at: url, to: target)
    if let attrs = try? fm.attributesOfItem(atPath: url.path) {
        var keep: [FileAttributeKey: Any] = [:]
        for k in [FileAttributeKey.modificationDate, .posixPermissions] { keep[k] = attrs[k] }
        try? fm.setAttributes(keep, ofItemAtPath: target.path)
    }
    return target
}

// MARK: Ajout de fichiers

/// Plugins à ajouter pour une liste de chemins : fichiers .esp/.esm/.esl, ou contenu (non récursif, trié) des dossiers.
public func pluginFiles(in paths: [URL]) -> [URL] {
    let fm = FileManager.default
    var files: [URL] = []
    for p in paths {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: p.path, isDirectory: &isDir) else { continue }
        if isDir.boolValue {
            let names = ((try? fm.contentsOfDirectory(atPath: p.path)) ?? []).sorted(by: codepointLess)
            for name in names where hasPluginExtension(name) {
                let f = p.appendingPathComponent(name)
                var d: ObjCBool = false
                if fm.fileExists(atPath: f.path, isDirectory: &d), !d.boolValue { files.append(f) }
            }
        } else if hasPluginExtension(p.lastPathComponent) {
            files.append(p)
        }
    }
    return files
}
