from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path

from .safety import sha256_file


class PluginFormatError(ValueError):
    pass


@dataclass(slots=True)
class PluginHeader:
    path: str
    size_bytes: int
    sha256: str
    record_flags: int
    is_master_flag: bool
    is_light_flag: bool
    form_version: int
    author: str = ""
    description: str = ""
    masters: list[str] = field(default_factory=list)
    header_version: float | None = None
    num_records: int | None = None
    next_object_id: int | None = None


def _decode_zstring(data: bytes) -> str:
    return data.split(b"\x00", 1)[0].decode("utf-8", errors="replace")


def inspect_plugin_header(path: Path, max_header_bytes: int = 64 * 1024 * 1024) -> PluginHeader:
    stat = path.stat()
    with path.open("rb") as handle:
        header = handle.read(24)
        if len(header) != 24 or header[:4] != b"TES4":
            raise PluginFormatError("File does not begin with a Skyrim TES4 record header")
        data_size = struct.unpack_from("<I", header, 4)[0]
        flags = struct.unpack_from("<I", header, 8)[0]
        form_version = struct.unpack_from("<H", header, 20)[0]
        if data_size > max_header_bytes:
            raise PluginFormatError(f"TES4 header payload is implausibly large: {data_size}")
        payload = handle.read(data_size)
        if len(payload) != data_size:
            raise PluginFormatError("Truncated TES4 header payload")

    result = PluginHeader(
        path=str(path),
        size_bytes=stat.st_size,
        sha256=sha256_file(path),
        record_flags=flags,
        is_master_flag=bool(flags & 0x00000001),
        is_light_flag=bool(flags & 0x00000200),
        form_version=form_version,
    )

    pos = 0
    extended_size: int | None = None
    while pos + 6 <= len(payload):
        signature = payload[pos : pos + 4]
        size = struct.unpack_from("<H", payload, pos + 4)[0]
        pos += 6
        if signature == b"XXXX":
            if size != 4 or pos + 4 > len(payload):
                raise PluginFormatError("Malformed XXXX extended-size subrecord")
            extended_size = struct.unpack_from("<I", payload, pos)[0]
            pos += 4
            continue
        actual_size = extended_size if extended_size is not None else size
        extended_size = None
        if actual_size < 0 or pos + actual_size > len(payload):
            raise PluginFormatError(f"Malformed {signature!r} subrecord length")
        data = payload[pos : pos + actual_size]
        pos += actual_size

        if signature == b"HEDR" and len(data) >= 12:
            result.header_version, result.num_records, result.next_object_id = struct.unpack_from("<fII", data, 0)
        elif signature == b"CNAM":
            result.author = _decode_zstring(data)
        elif signature == b"SNAM":
            result.description = _decode_zstring(data)
        elif signature == b"MAST":
            result.masters.append(_decode_zstring(data))

    return result
