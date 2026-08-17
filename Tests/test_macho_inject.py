import importlib.util
import pathlib
import struct
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "macho_inject", ROOT / "Tools" / "macho_inject.py"
)
MACHO = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MACHO
SPEC.loader.exec_module(MACHO)


def dylib_command(name: str, command: int = MACHO.LC_LOAD_DYLIB) -> bytes:
    encoded = name.encode() + b"\0"
    size = MACHO.align(24 + len(encoded), 8)
    result = bytearray(size)
    struct.pack_into("<IIIIII", result, 0, command, size, 24, 0, 0, 0)
    result[24 : 24 + len(encoded)] = encoded
    return bytes(result)


def fixture(section_offset: int = 0x400) -> bytes:
    segment = bytearray(152)
    struct.pack_into("<II", segment, 0, MACHO.LC_SEGMENT_64, len(segment))
    struct.pack_into("<I", segment, 64, 1)
    struct.pack_into("<I", segment, 72 + 48, section_offset)
    legacy = dylib_command(
        "@rpath/LegacyTweak.dylib",
        0x18 | 0x80000000,
    )
    commands = bytes(segment) + legacy
    result = bytearray(max(section_offset + 32, 0x500))
    struct.pack_into(
        "<IiiIIIII",
        result,
        0,
        MACHO.MH_MAGIC_64,
        0x0100000C,
        0,
        6,
        2,
        len(commands),
        0,
        0,
    )
    result[32 : 32 + len(commands)] = commands
    return bytes(result)


class MachOInjectTests(unittest.TestCase):
    def test_replaces_legacy_load(self):
        rewritten = MACHO.rewrite(
            fixture(),
            "@rpath/YouLitePlus.dylib",
            ["LegacyTweak.dylib"],
        )
        self.assertEqual(MACHO.list_dylibs(rewritten), [["@rpath/YouLitePlus.dylib"]])

    def test_is_idempotent(self):
        first = MACHO.rewrite(
            fixture(),
            "@rpath/YouLitePlus.dylib",
            ["LegacyTweak.dylib"],
        )
        second = MACHO.rewrite(
            first,
            "@rpath/YouLitePlus.dylib",
            ["LegacyTweak.dylib"],
        )
        self.assertEqual(first, second)

    def test_rejects_missing_slack(self):
        source = fixture()
        count, size = MACHO.header(source, MACHO.Slice(0, len(source)))
        self.assertEqual(count, 2)
        tight = fixture(32 + size)
        with self.assertRaises(MACHO.MachOError):
            MACHO.rewrite(tight, "@rpath/YouLitePlus.dylib", [])



if __name__ == "__main__":
    unittest.main()
