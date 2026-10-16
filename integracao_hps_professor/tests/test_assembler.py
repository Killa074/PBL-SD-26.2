"""Meaningful encoding/diagnostic regressions; run python tests/test_assembler.py."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("assemble", Path(__file__).resolve().parents[1] / "tools" / "assemble.py")
assembler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assembler)


class AssemblerTests(unittest.TestCase):
    def test_known_encodings_and_labels(self):
        words, _, used = assembler.assemble("""
            .equ PORT, 0x20 + 3
            LDI R1, -1
            LUI R2, 0x1234
            ADD R3, R1, R2
            OUT R3, PORT
            JZ R0, finish
            JMP 0
            finish: HALT
        """, 16)
        self.assertEqual(words[:7], [0x1100FFFF, 0xE2001234, 0x23120000,
                                    0xA0300023, 0xC0000006, 0xB0000000, 0xF0000000])
        self.assertEqual(used, 7)
        self.assertEqual(words[7:], [0xF0000000] * 9)

    def test_li32_signed_low_half_correction(self):
        for value in [0, 0x7FFF, 0x8000, 0xFFFF, 0x89ABCDEF, 0xFFFFFFFF, -0x80000000]:
            words, _, used = assembler.assemble(f"LI32 R1,R2,{value}", 4)
            high = (words[0] & 0xFFFF) << 16
            low = words[1] & 0xFFFF
            if low & 0x8000: low -= 0x10000
            self.assertEqual((high + low) & 0xFFFFFFFF, value & 0xFFFFFFFF)
            self.assertEqual(used, 3)
        words, _, _ = assembler.assemble("WRITE 0xF0,1\nJMP after\nafter:HALT", 8)
        self.assertEqual(words[3], 0xA0E000F0)
        self.assertEqual(words[4], 0xB0000005)

    def test_diagnostics(self):
        invalid = ["LDI R16,1", "LDI R1,65535", "OUT R1,256", "JMP 1024",
                   "JZ R1,missing", "ADD R1,R2", "NOP 1",
                   "A:NOP\nA:HALT", ".equ A,B\n.equ B,A\nHALT",
                   "LI32 R1,R1,1", "LI32 R0,R2,1", "WRITE 0,0x100000000",
                   "LDI R1,__import__('os')", "LDI R1,1<<10000"]
        for source in invalid:
            with self.subTest(source=source), self.assertRaises(assembler.AssemblyError):
                assembler.assemble(source, 16)
        with self.assertRaises(assembler.AssemblyError):
            assembler.assemble("NOP\nNOP\nNOP", 2)


if __name__ == "__main__":
    unittest.main()
