"""Gerade so viel ELF, wie der Android-Build braucht.

Bewusst ohne Fremdbibliothek: auf dem Runner steht kein `readelf` für
Android-Binärdateien, und `pyelftools` wäre eine Abhängigkeit für zwei
Funktionen. Gelesen werden Sektionstabelle, `.dynamic` und `.dynsym` — mehr
ist hier nicht nötig.
"""

from __future__ import annotations

import struct
from pathlib import Path

# Marken aus elf.h, die hier vorkommen.
SHT_DYNSYM = 11
SHT_DYNAMIC = 6
DT_NEEDED = 1
DT_SONAME = 14


class Elf:
    """Eine gelesene ELF-Datei."""

    def __init__(self, data: bytes) -> None:
        if data[:4] != b"\x7fELF":
            raise ValueError("keine ELF-Datei")
        self.data = data
        self.is64 = data[4] == 2
        self.end = "<" if data[5] == 1 else ">"
        self._sections = self._read_sections()

    @classmethod
    def load(cls, path: Path) -> "Elf":
        return cls(path.read_bytes())

    def _read_sections(self) -> list[tuple[int, int, int, int, int, int]]:
        data, end = self.data, self.end
        if self.is64:
            offset, = struct.unpack_from(end + "Q", data, 0x28)
            entsize, count, _ = struct.unpack_from(end + "HHH", data, 0x3A)
        else:
            offset, = struct.unpack_from(end + "I", data, 0x20)
            entsize, count, _ = struct.unpack_from(end + "HHH", data, 0x2E)

        sections = []
        for index in range(count):
            base = offset + index * entsize
            if self.is64:
                _, kind = struct.unpack_from(end + "II", data, base)
                start, size = struct.unpack_from(end + "QQ", data, base + 0x18)
                link, = struct.unpack_from(end + "I", data, base + 0x28)
                slot, = struct.unpack_from(end + "Q", data, base + 0x38)
            else:
                _, kind = struct.unpack_from(end + "II", data, base)
                start, size = struct.unpack_from(end + "II", data, base + 0x10)
                link, = struct.unpack_from(end + "I", data, base + 0x18)
                slot, = struct.unpack_from(end + "I", data, base + 0x24)
            sections.append((kind, start, size, link, slot, index))
        return sections

    def _strings(self, link: int) -> bytes:
        for kind, start, size, _, _, index in self._sections:
            if index == link:
                return self.data[start:start + size]
        return b""

    @staticmethod
    def _at(table: bytes, offset: int) -> str:
        if offset >= len(table):
            return ""
        return table[offset:table.find(b"\0", offset)].decode("utf-8", "replace")

    def dynamic_symbols(self) -> set[str]:
        """Alles, was diese Bibliothek exportiert oder braucht."""
        names: set[str] = set()
        for kind, start, size, link, slot, _ in self._sections:
            if kind != SHT_DYNSYM or slot == 0:
                continue
            table = self._strings(link)
            for position in range(start, start + size, slot):
                name, = struct.unpack_from(self.end + "I", self.data, position)
                if name:
                    text = self._at(table, name)
                    if text:
                        names.add(text)
        return names

    def needed(self) -> list[str]:
        """Die `DT_NEEDED`-Einträge — was der Lader zusätzlich holen muss."""
        out: list[str] = []
        step = 16 if self.is64 else 8
        fmt = self.end + ("QQ" if self.is64 else "II")
        for kind, start, size, link, _, _ in self._sections:
            if kind != SHT_DYNAMIC:
                continue
            table = self._strings(link)
            for position in range(start, start + size, step):
                tag, value = struct.unpack_from(fmt, self.data, position)
                if tag == 0:
                    break
                if tag == DT_NEEDED:
                    name = self._at(table, value)
                    if name:
                        out.append(name)
        return out

    def soname(self) -> str | None:
        step = 16 if self.is64 else 8
        fmt = self.end + ("QQ" if self.is64 else "II")
        for kind, start, size, link, _, _ in self._sections:
            if kind != SHT_DYNAMIC:
                continue
            table = self._strings(link)
            for position in range(start, start + size, step):
                tag, value = struct.unpack_from(fmt, self.data, position)
                if tag == 0:
                    break
                if tag == DT_SONAME:
                    return self._at(table, value) or None
        return None
