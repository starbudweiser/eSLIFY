"""Contrôles d'éligibilité ESL sur des plugins fabriqués octet par octet."""
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

import eslify_core as core  # noqa: E402
import i18n  # noqa: E402


def sub(sig: bytes, data: bytes) -> bytes:
    return sig + struct.pack("<H", len(data)) + data


def record(sig: bytes, form_id: int, data: bytes = b"") -> bytes:
    return sig + struct.pack("<IIIII", len(data), 0, form_id, 0, 0) + data


def plugin(records: list[bytes], masters: tuple[str, ...] = ("Skyrim.esm",), version: float = 1.71) -> bytes:
    head = sub(b"HEDR", struct.pack("<fiI", version, len(records), 0x800))
    head += b"".join(sub(b"MAST", m.encode() + b"\0") + sub(b"DATA", b"\0" * 8) for m in masters)
    body = b"".join(records)
    grup = b"GRUP" + struct.pack("<I", 24 + len(body)) + b"\0" * 16
    return b"TES4" + struct.pack("<IIIII", len(head), 0, 0, 0, 0) + head + grup + body


class TestEligibility(unittest.TestCase):
    def setUp(self):
        i18n.set_lang("fr")
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name: str, data: bytes) -> Path:
        path = self.dir / name
        path.write_bytes(data)
        return path

    def test_eligible(self):
        r = core.check_eligibility(self.write("A.esp", plugin([record(b"WEAP", 0x01000801)])))
        self.assertTrue(r.eligible)
        self.assertEqual((r.new_records, r.new_cells, r.dependents), (1, 0, ()))

    def test_new_cell_refused(self):
        r = core.check_eligibility(self.write("A.esp", plugin([record(b"CELL", 0x01000801)])))
        self.assertFalse(r.eligible)
        self.assertEqual(r.new_cells, 1)
        self.assertIn("cellule", r.reason)

    def test_new_worldspace_refused(self):
        r = core.check_eligibility(self.write("A.esp", plugin([record(b"WRLD", 0x01000802)])))
        self.assertFalse(r.eligible)

    def test_overridden_cell_allowed(self):
        # Une cellule de Skyrim.esm (index de maître 00) modifiée n'est pas une nouvelle cellule.
        r = core.check_eligibility(self.write("A.esp", plugin([record(b"CELL", 0x00000D74)])))
        self.assertTrue(r.eligible)
        self.assertEqual(r.new_cells, 0)

    def test_dependents_warn(self):
        a = self.write("A.esp", plugin([record(b"WEAP", 0x01000801)]))
        self.write("B.esp", plugin([], masters=("Skyrim.esm", "a.ESP")))
        self.write("C.esp", plugin([]))
        r = core.check_eligibility(a)
        self.assertTrue(r.eligible)
        self.assertEqual(r.dependents, ("B.esp",))
        self.assertIn("B.esp", r.reason)

    def test_dependents_given(self):
        r = core.check_eligibility(self.write("A.esp", plugin([record(b"WEAP", 0x01000801)])), dependents=())
        self.assertEqual(r.reason, "Éligible.")

    def test_formid_too_high(self):
        r = core.check_eligibility(self.write("A.esp", plugin([record(b"WEAP", 0x01001000)])))
        self.assertFalse(r.eligible)

    def test_low_formid_needs_171(self):
        r = core.check_eligibility(self.write("A.esp", plugin([record(b"WEAP", 0x01000100)], version=1.70)))
        self.assertFalse(r.eligible)
        r = core.check_eligibility(self.write("B.esp", plugin([record(b"WEAP", 0x01000100)], version=1.71)))
        self.assertTrue(r.eligible)

    def test_masters_read(self):
        version, masters = core.read_masters(plugin([], masters=("Skyrim.esm", "Update.esm")))
        self.assertEqual((version, masters), (1.71, ["Skyrim.esm", "Update.esm"]))

    def test_unreadable_neighbour_ignored(self):
        a = self.write("A.esp", plugin([record(b"WEAP", 0x01000801)]))
        self.write("Junk.esp", b"not a plugin")
        self.assertEqual(core.dependents_of(a), ())


if __name__ == "__main__":
    unittest.main()
