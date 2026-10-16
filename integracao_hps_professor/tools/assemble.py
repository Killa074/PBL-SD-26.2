#!/usr/bin/env python3
"""Assembler for the teaching GPU ISA. Only Python's standard library is used."""
import argparse
import ast
from pathlib import Path
import re
import sys


class AssemblyError(ValueError):
    pass


ALU = {"ADD": 2, "SUB": 3, "AND": 4, "OR": 5, "XOR": 6,
       "SHL": 7, "SHR": 8, "SLT": 13}


def expression(text, symbols, constants, stack=()):
    """Evaluate integer arithmetic, never arbitrary Python code."""
    try:
        tree = ast.parse(text, mode="eval").body
    except (SyntaxError, ValueError) as exc:
        raise AssemblyError(f"invalid expression {text!r}") from exc

    def visit(node):
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.Name):
            name = node.id.upper()
            if name in symbols:
                return symbols[name]
            if name in constants and name not in stack:
                return expression(constants[name], symbols, constants, stack + (name,))
            raise AssemblyError(f"unknown or cyclic symbol {node.id!r}")
        if isinstance(node, ast.UnaryOp):
            value = visit(node.operand)
            if isinstance(node.op, ast.USub): return -value
            if isinstance(node.op, ast.UAdd): return value
            if isinstance(node.op, ast.Invert): return ~value
        if isinstance(node, ast.BinOp):
            left, right = visit(node.left), visit(node.right)
            if isinstance(node.op, ast.Add): return left + right
            if isinstance(node.op, ast.Sub): return left - right
            if isinstance(node.op, ast.Mult): return left * right
            if isinstance(node.op, ast.FloorDiv) and right: return left // right
            if isinstance(node.op, ast.Mod) and right: return left % right
            if isinstance(node.op, (ast.LShift, ast.RShift)) and 0 <= right <= 63:
                return left << right if isinstance(node.op, ast.LShift) else left >> right
            if isinstance(node.op, ast.BitOr): return left | right
            if isinstance(node.op, ast.BitAnd): return left & right
            if isinstance(node.op, ast.BitXor): return left ^ right
        raise AssemblyError(f"unsupported expression {text!r}")

    return visit(tree)


def register(text):
    match = re.fullmatch(r"[Rr](\d+)", text.strip())
    if not match or not 0 <= int(match[1]) < 16:
        raise AssemblyError(f"expected R0..R15, got {text!r}")
    return int(match[1])


def bounded(value, low, high, description):
    if not low <= value <= high:
        raise AssemblyError(f"{description} {value} is outside {low}..{high}")
    return value


def assemble(source, words=1024):
    bounded(words, 1, 1024, "memory size")
    symbols, constants, statements = {}, {}, []
    pc = 0
    for line_no, original in enumerate(source.splitlines(), 1):
        line = re.split(r";|//|#", original, maxsplit=1)[0].strip()
        try:
            while (match := re.match(r"^([A-Za-z_]\w*):", line)):
                name = match[1].upper()
                if name in symbols or name in constants:
                    raise AssemblyError(f"duplicate symbol {name}")
                symbols[name] = pc
                line = line[match.end():].strip()
            if not line: continue
            parts = line.split(None, 1)
            op = parts[0].upper()
            operands = [p.strip() for p in parts[1].split(",")] if len(parts) == 2 else []
            if any(not p for p in operands):
                raise AssemblyError("empty operand")
            if op == ".EQU":
                if len(operands) != 2 or not re.fullmatch(r"[A-Za-z_]\w*", operands[0]):
                    raise AssemblyError("expected .equ NAME, expression")
                name = operands[0].upper()
                if name in symbols or name in constants:
                    raise AssemblyError(f"duplicate symbol {name}")
                constants[name] = operands[1]
                continue
            statements.append((line_no, pc, op, operands, original))
            pc += 3 if op == "LI32" else 4 if op == "WRITE" else 1
            if pc > words:
                raise AssemblyError(f"program exceeds {words} instruction words")
        except AssemblyError as exc:
            raise AssemblyError(f"line {line_no}: {exc}") from exc

    def value(text): return expression(text, symbols, constants)
    # Diagnose unused malformed constants as well.
    for name in constants:
        expression(name, symbols, constants)

    def li32(rd, temp, number):
        if rd == 0 or temp == 0 or rd == temp:
            raise AssemblyError("LI32 needs two different nonzero registers")
        bounded(number, -0x80000000, 0xFFFFFFFF, "32-bit immediate")
        number &= 0xFFFFFFFF
        low = number & 0xFFFF
        high = ((number + 0x8000) >> 16) & 0xFFFF
        return [0xE0000000 | rd << 24 | high,
                0x10000000 | temp << 24 | low,
                0x20000000 | rd << 24 | rd << 20 | temp << 16]

    def encode(op, args):
        arities = {"NOP": 0, "HALT": 0, "LDI": 2, "LUI": 2, "MOV": 2,
                   "OUT": 2, "JMP": 1, "JZ": 2, "LI32": 3, "WRITE": 2,
                   ".WORD": 1, **{name: 3 for name in ALU}}
        if op not in arities: raise AssemblyError(f"unknown instruction {op}")
        if len(args) != arities[op]:
            raise AssemblyError(f"{op} expects {arities[op]} operands, got {len(args)}")
        if op == "NOP": return [0]
        if op == "HALT": return [0xF0000000]
        if op in ALU:
            return [ALU[op] << 28 | register(args[0]) << 24 |
                    register(args[1]) << 20 | register(args[2]) << 16]
        if op in ("LDI", "LUI"):
            immediate = bounded(value(args[1]), -32768 if op == "LDI" else 0,
                                32767 if op == "LDI" else 65535, f"{op} immediate")
            return [(1 if op == "LDI" else 14) << 28 | register(args[0]) << 24 | immediate & 0xFFFF]
        if op == "MOV": return [0x90000000 | register(args[0]) << 24 | register(args[1]) << 20]
        if op == "OUT":
            return [0xA0000000 | register(args[0]) << 20 | bounded(value(args[1]), 0, 255, "graphics port")]
        if op in ("JMP", "JZ"):
            target = bounded(value(args[-1]), 0, words - 1, "branch address")
            return [(0xB0000000 if op == "JMP" else 0xC0000000 | register(args[0]) << 20) | target]
        if op == "LI32": return li32(register(args[0]), register(args[1]), value(args[2]))
        if op == "WRITE":
            port = bounded(value(args[0]), 0, 255, "graphics port")
            return li32(14, 15, value(args[1])) + [0xA0E00000 | port]
        return [bounded(value(args[0]), -0x80000000, 0xFFFFFFFF, ".word value") & 0xFFFFFFFF]

    output, listing = [], []
    for line_no, address, op, args, original in statements:
        try:
            encoded = encode(op, args)
        except AssemblyError as exc:
            raise AssemblyError(f"line {line_no}: {exc}") from exc
        output.extend(encoded)
        listing.append(f"{address:03X}  {' '.join(f'{word:08X}' for word in encoded)}  {original.strip()}")
    used = len(output)
    output.extend([0xF0000000] * (words - used))
    return output, listing, used


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--words", type=int, default=1024)
    parser.add_argument("--listing", type=Path)
    args = parser.parse_args()
    try:
        words, listing, used = assemble(args.source.read_text(encoding="utf-8-sig"), args.words)
        output = args.output or args.source.with_suffix(".hex")
        output.write_text("".join(f"{word:08X}\n" for word in words), encoding="ascii")
        if args.listing:
            args.listing.write_text("\n".join(listing) + "\n", encoding="utf-8")
        print(f"{output}: {used} instructions, {len(words)} words including HALT padding")
    except (AssemblyError, OSError) as exc:
        print(f"assembler: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
