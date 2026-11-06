// Contrôles d'éligibilité ESL sur des plugins fabriqués octet par octet (portage de tests/test_core.py) et pose du drapeau.

import Foundation
import XCTest
@testable import EslCore

private func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)] }
private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }

private func sub(_ sig: String, _ data: [UInt8]) -> [UInt8] { Array(sig.utf8) + le16(data.count) + data }

private func rec(_ sig: String, _ formID: UInt32, _ data: [UInt8] = []) -> [UInt8] {
    Array(sig.utf8) + le32(UInt32(data.count)) + le32(0) + le32(formID) + le32(0) + le32(0) + data
}

private func plugin(_ records: [[UInt8]], masters: [String] = ["Skyrim.esm"], version: Float = 1.71, flags: UInt32 = 0) -> Data {
    var head = sub("HEDR", le32(version.bitPattern) + le32(UInt32(records.count)) + le32(0x800))
    for m in masters { head += sub("MAST", Array(m.utf8) + [0]) + sub("DATA", [UInt8](repeating: 0, count: 8)) }
    let body = records.flatMap { $0 }
    let grup = Array("GRUP".utf8) + le32(UInt32(24 + body.count)) + [UInt8](repeating: 0, count: 16)
    return Data(Array("TES4".utf8) + le32(UInt32(head.count)) + le32(flags) + le32(0) + le32(0) + le32(0) + head + grup + body)
}

final class EslCoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        I18n.setLang("fr")
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("eslify-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    @discardableResult
    func write(_ name: String, _ data: Data) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    // MARK: éligibilité (10 tests portés)

    func testEligible() throws {
        let r = try checkEligibility(write("A.esp", plugin([rec("WEAP", 0x0100_0801)])))
        XCTAssertTrue(r.eligible)
        XCTAssertEqual(r.newRecords, 1)
        XCTAssertEqual(r.newCells, 0)
        XCTAssertEqual(r.dependents, [])
    }

    func testNewCellRefused() throws {
        let r = try checkEligibility(write("A.esp", plugin([rec("CELL", 0x0100_0801)])))
        XCTAssertFalse(r.eligible)
        XCTAssertEqual(r.newCells, 1)
        XCTAssertTrue(r.reason.contains("cellule"))
    }

    func testNewWorldspaceRefused() throws {
        let r = try checkEligibility(write("A.esp", plugin([rec("WRLD", 0x0100_0802)])))
        XCTAssertFalse(r.eligible)
    }

    func testOverriddenCellAllowed() throws {
        // Une cellule de Skyrim.esm (index de maître 00) modifiée n'est pas une nouvelle cellule.
        let r = try checkEligibility(write("A.esp", plugin([rec("CELL", 0x0000_0D74)])))
        XCTAssertTrue(r.eligible)
        XCTAssertEqual(r.newCells, 0)
    }

    func testDependentsWarn() throws {
        let a = try write("A.esp", plugin([rec("WEAP", 0x0100_0801)]))
        try write("B.esp", plugin([], masters: ["Skyrim.esm", "a.ESP"]))
        try write("C.esp", plugin([]))
        let r = try checkEligibility(a)
        XCTAssertTrue(r.eligible)
        XCTAssertEqual(r.dependents, ["B.esp"])
        XCTAssertTrue(r.reason.contains("B.esp"))
    }

    func testDependentsGiven() throws {
        let r = try checkEligibility(write("A.esp", plugin([rec("WEAP", 0x0100_0801)])), dependents: [])
        XCTAssertEqual(r.reason, "Éligible.")
    }

    func testFormIDTooHigh() throws {
        let r = try checkEligibility(write("A.esp", plugin([rec("WEAP", 0x0100_1000)])))
        XCTAssertFalse(r.eligible)
        XCTAssertEqual(r.reason, "FormID propre trop élevé (001000 > FFF). Compactez les FormID dans xEdit avant de le marquer ESL.")
    }

    func testLowFormIDNeeds171() throws {
        var r = try checkEligibility(write("A.esp", plugin([rec("WEAP", 0x0100_0100)], version: 1.70)))
        XCTAssertFalse(r.eligible)
        XCTAssertTrue(r.reason.contains("avec un en-tête 1.7 :"), r.reason)
        r = try checkEligibility(write("B.esp", plugin([rec("WEAP", 0x0100_0100)], version: 1.71)))
        XCTAssertTrue(r.eligible)
    }

    func testMastersRead() throws {
        let (version, masters) = try readMasters(plugin([], masters: ["Skyrim.esm", "Update.esm"]))
        XCTAssertEqual(version, 1.71)
        XCTAssertEqual(masters, ["Skyrim.esm", "Update.esm"])
    }

    func testUnreadableNeighbourIgnored() throws {
        let a = try write("A.esp", plugin([rec("WEAP", 0x0100_0801)]))
        try write("Junk.esp", Data("not a plugin".utf8))
        XCTAssertEqual(dependents(of: a), [])
    }

    // MARK: tests ajoutés

    func testDependentsListTruncatedAfterThree() throws {
        let a = try write("A.esp", plugin([rec("WEAP", 0x0100_0801)]))
        for n in ["B", "C", "D", "E"] { try write("\(n).esp", plugin([], masters: ["Skyrim.esm", "A.esp"])) }
        let r = try checkEligibility(a)
        XCTAssertEqual(r.dependents, ["B.esp", "C.esp", "D.esp", "E.esp"])
        XCTAssertTrue(r.reason.contains("(B.esp, C.esp, D.esp…)"), r.reason)
    }

    func testAlreadyESLAndNotAPlugin() throws {
        let r = try checkEligibility(write("A.esp", plugin([rec("WEAP", 0x0100_0801)], flags: FLAG_ESL)))
        XCTAssertTrue(r.alreadyESL)
        XCTAssertFalse(r.eligible)
        XCTAssertEqual(r.reason, "Déjà marqué ESL.")
        let junk = checkEligibilitySafe(try write("J.esp", Data("hello world, not a plugin at all".utf8)))
        XCTAssertFalse(junk.eligible)
        XCTAssertEqual(junk.reason, "Ce n'est pas un plugin Skyrim (en-tête TES4 absent).")
    }

    func testTruncatedPluginReportedNotCrashing() throws {
        let full = plugin([rec("WEAP", 0x0100_0801)])
        let r = checkEligibilitySafe(try write("T.esp", full.prefix(10)))
        XCTAssertFalse(r.eligible)
        XCTAssertTrue(r.reason.hasPrefix("Plugin illisible"), r.reason)
        let missing = checkEligibilitySafe(dir.appendingPathComponent("absent.esp"))
        XCTAssertTrue(missing.reason.hasPrefix("Lecture impossible"), missing.reason)
    }

    func testSpanAndHedrRounding() throws {
        let r = try checkEligibility(write("A.esp", plugin([rec("WEAP", 0x0100_0801), rec("WEAP", 0x0100_08FF)])))
        XCTAssertEqual(r.span, "801 – 8FF")
        XCTAssertEqual(r.hedrVersion, 1.71)
        XCTAssertEqual(try checkEligibility(write("E.esp", plugin([]))).span, "—")
    }

    func testFlagChangesOnlyFourBytes() throws {
        let original = plugin([rec("WEAP", 0x0100_0801)], flags: 0x81)
        let url = try write("A.esp", original)
        let before = try Data(contentsOf: url)
        let res = try inspectAndFlagESL(url, applyFix: true)
        XCTAssertTrue(res.modified)
        XCTAssertEqual(res.previousFlags, "0x81")
        XCTAssertEqual(res.newFlags, "0x281")
        let after = try Data(contentsOf: url)
        XCTAssertEqual(after.count, before.count)
        let changed = (0..<before.count).filter { before[$0] != after[$0] }
        XCTAssertEqual(changed, [9])  // seul l'octet 0x02 des drapeaux (0x0200) change
        XCTAssertEqual(try after.u32(8), 0x281)
        // Deuxième passage : déjà ESL, rien n'est écrit
        let again = try inspectAndFlagESL(url, applyFix: true)
        XCTAssertFalse(again.modified)
        XCTAssertTrue(again.alreadyESL)
        XCTAssertEqual(try Data(contentsOf: url), after)
        // Lecture seule : ne modifie pas
        let other = try write("B.esp", original)
        XCTAssertFalse(try inspectAndFlagESL(other).modified)
        XCTAssertEqual(try Data(contentsOf: other), original)
    }

    func testFlagErrors() throws {
        XCTAssertThrowsError(try inspectAndFlagESL(dir.appendingPathComponent("nope.esp"))) {
            XCTAssertTrue("\($0)".hasPrefix("Fichier introuvable"))
        }
        let junk = try write("J.esp", Data("abcdefghijklmnop".utf8))
        XCTAssertThrowsError(try inspectAndFlagESL(junk, applyFix: true)) {
            XCTAssertEqual("\($0)", "J.esp n'est pas un plugin Skyrim valide (attendu TES4, trouvé b'abcd').")
        }
        XCTAssertEqual(try Data(contentsOf: junk), Data("abcdefghijklmnop".utf8))
    }

    func testBackupNames() throws {
        let url = try write("A.esp", plugin([rec("WEAP", 0x0100_0801)]))
        let old = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        let b1 = try backup(url)
        XCTAssertEqual(b1.lastPathComponent, "A.esp.bak")
        XCTAssertEqual(try Data(contentsOf: b1), try Data(contentsOf: url))
        let date = try FileManager.default.attributesOfItem(atPath: b1.path)[.modificationDate] as! Date
        XCTAssertEqual(date.timeIntervalSince1970, old.timeIntervalSince1970, accuracy: 1)
        let b2 = try backup(url, now: Date(timeIntervalSince1970: 1_700_000_000))
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        XCTAssertEqual(b2.lastPathComponent, "A.esp.\(f.string(from: Date(timeIntervalSince1970: 1_700_000_000))).bak")
        let b3 = try backup(url, now: Date(timeIntervalSince1970: 1_700_000_000))  // même seconde : pas d'écrasement
        XCTAssertNotEqual(b3, b2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: b2.path))
    }

    func testPluginFilesFromFolderAndFiles() throws {
        try write("b.ESP", plugin([])); try write("A.esm", plugin([])); try write("c.esl", plugin([])); try write("d.txt", Data())
        try write(".esp", Data())
        let found = pluginFiles(in: [dir]).map(\.lastPathComponent)
        XCTAssertEqual(found, ["A.esm", "b.ESP", "c.esl"])
        XCTAssertEqual(pluginFiles(in: [dir.appendingPathComponent("d.txt")]), [])
    }

    func testCp1252MasterName() throws {
        var head = sub("HEDR", le32(Float(1.71).bitPattern) + le32(0) + le32(0x800))
        head += sub("MAST", [0x43, 0x61, 0x66, 0xE9, 0x80, 0x81, 0x00])  // « Café€ » + octet non défini
        let data = Data(Array("TES4".utf8) + le32(UInt32(head.count)) + [UInt8](repeating: 0, count: 16) + head)
        XCTAssertEqual(try readMasters(data).masters, ["Café€\u{FFFD}"])
    }

    // MARK: traductions

    func testSamePlaceholdersInAllLanguages() {
        let field = try! NSRegularExpression(pattern: "\\{([A-Za-z_][A-Za-z0-9_]*)[^}]*\\}")
        func fields(_ s: String) -> Set<String> {
            Set(field.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range(at: 1), in: s)!]) })
        }
        for key in I18n.keys {
            let tr = I18n.translation(key)!
            XCTAssertEqual(tr.count, 3, key)
            for (lang, t) in zip(["en", "it", "es"], tr) {
                XCTAssertFalse(t.trimmingCharacters(in: .whitespaces).isEmpty, "\(lang) vide : \(key)")
                XCTAssertEqual(fields(key), fields(t), "\(lang) : \(key)")
            }
        }
    }

    func testEveryCoreMessageTranslated() {
        let used = ["Fichier introuvable : {path}", "Éligible.", "Déjà marqué ESL.", "Plugin illisible : {err}.",
                    "Lecture impossible : {err}.", "Ce n'est pas un plugin Skyrim (en-tête TES4 absent)."]
        for k in used { XCTAssertNotNil(I18n.translation(k), k) }
        I18n.setLang("en")
        XCTAssertEqual(L("Éligible."), "Eligible.")
        XCTAssertEqual(L("{name} : {reason}", ["name": "A.esp", "reason": "x"]), "A.esp: x")
        I18n.setLang("fr")
    }

    func testSystemLang() {
        XCTAssertEqual(I18n.systemLang(["it-IT", "en-US"]), "it")
        XCTAssertEqual(I18n.systemLang(["de-DE", "es-ES"]), "es")
        XCTAssertEqual(I18n.systemLang(["de-DE"]), "en")
    }
}
