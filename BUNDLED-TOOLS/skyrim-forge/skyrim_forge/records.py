from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator, Any

from .errors import ValidationError
from .plugin_header import inspect_plugin_header
from .util import sha256_file

RECORD_HEADER = 24
GROUP_HEADER = 24
COMPRESSED_FLAG = 0x00040000
MAX_PLUGIN_BYTES = 4 * 1024 * 1024 * 1024
MAX_RECORD_UNCOMPRESSED = 512 * 1024 * 1024
MAX_GROUP_DEPTH = 128


@dataclass(slots=True)
class Record:
    signature: str
    form_id: int
    flags: int
    form_version: int
    offset: int
    data_size: int
    editor_id: str = ""
    compressed: bool = False
    subrecords: list[tuple[str, bytes]] = field(default_factory=list)

    @property
    def raw_form_id_hex(self) -> str:
        return f"0x{self.form_id:08X}"


def parse_subrecords(payload: bytes) -> list[tuple[str, bytes]]:
    result: list[tuple[str, bytes]] = []
    offset = 0
    extended: int | None = None
    while offset + 6 <= len(payload):
        signature = payload[offset:offset+4].decode("ascii", errors="replace")
        size = struct.unpack_from("<H", payload, offset + 4)[0]
        offset += 6
        if signature == "XXXX":
            if size != 4 or offset + 4 > len(payload):
                raise ValidationError("Malformed XXXX subrecord")
            extended = struct.unpack_from("<I", payload, offset)[0]
            offset += 4
            continue
        actual = extended if extended is not None else size
        extended = None
        if offset + actual > len(payload):
            raise ValidationError(f"Truncated {signature} subrecord")
        result.append((signature, payload[offset:offset+actual]))
        offset += actual
    if offset != len(payload):
        raise ValidationError("Trailing bytes in subrecord payload")
    return result


def _record(data: bytes, offset: int) -> tuple[Record, int]:
    if offset + RECORD_HEADER > len(data):
        raise ValidationError("Truncated record header")
    signature = data[offset:offset+4].decode("ascii", errors="replace")
    size, flags, form_id = struct.unpack_from("<III", data, offset + 4)
    form_version = struct.unpack_from("<H", data, offset + 20)[0]
    end = offset + RECORD_HEADER + size
    if end > len(data):
        raise ValidationError(f"Truncated {signature} record")
    payload = data[offset+RECORD_HEADER:end]
    compressed = bool(flags & COMPRESSED_FLAG)
    if compressed:
        if len(payload) < 4:
            raise ValidationError(f"Compressed {signature} record lacks size")
        expected = struct.unpack_from("<I", payload, 0)[0]
        if expected > MAX_RECORD_UNCOMPRESSED:
            raise ValidationError(f"Compressed {signature} record exceeds safety limit")
        decompressor = zlib.decompressobj()
        unpacked = decompressor.decompress(payload[4:], expected + 1)
        if len(unpacked) > expected or decompressor.unconsumed_tail or not decompressor.eof:
            raise ValidationError(f"Compressed {signature} record exceeds declared size or is incomplete")
        unpacked += decompressor.flush()
        if len(unpacked) != expected:
            raise ValidationError(f"Compressed {signature} record size mismatch")
        payload = unpacked
    subrecords = parse_subrecords(payload)
    editor_id = ""
    for sub, raw in subrecords:
        if sub == "EDID":
            editor_id = raw.split(b"\0", 1)[0].decode("utf-8", errors="replace")
            break
    return Record(signature, form_id, flags, form_version, offset, size, editor_id, compressed, subrecords), end


def _walk(data: bytes, start: int, end: int, depth: int = 0) -> Iterator[Record]:
    if depth > MAX_GROUP_DEPTH:
        raise ValidationError("Plugin group nesting exceeds safety limit")
    offset = start
    while offset < end:
        if offset + 4 > end:
            raise ValidationError("Truncated record/group signature")
        if data[offset:offset+4] == b"GRUP":
            if offset + GROUP_HEADER > end:
                raise ValidationError("Truncated GRUP header")
            group_size = struct.unpack_from("<I", data, offset + 4)[0]
            if group_size < GROUP_HEADER or offset + group_size > end:
                raise ValidationError("Invalid GRUP size")
            yield from _walk(data, offset + GROUP_HEADER, offset + group_size, depth + 1)
            offset += group_size
        else:
            record, offset = _record(data, offset)
            yield record


def iter_records(path: Path) -> Iterator[Record]:
    size = path.stat().st_size
    if size > MAX_PLUGIN_BYTES:
        raise ValidationError(f"Plugin exceeds {MAX_PLUGIN_BYTES} byte safety limit")
    data = path.read_bytes()
    if len(data) < 24 or data[:4] != b"TES4":
        raise ValidationError("Not a Bethesda plugin")
    first_size = struct.unpack_from("<I", data, 4)[0]
    offset = 24 + first_size
    if offset > len(data):
        raise ValidationError("Truncated TES4 record")
    yield from _walk(data, offset, len(data))


def query_records(path: Path, *, signature: str = "", editor_id: str = "", form_id: int | None = None, limit: int = 5000) -> dict[str, Any]:
    if not 1 <= limit <= 100_000:
        raise ValidationError("record query limit must be from 1 to 100000")
    signature = signature.upper().strip()
    editor_fold = editor_id.casefold().strip()
    header = inspect_plugin_header(path)
    matches = []
    total = 0
    self_index = len(header.masters)
    for record in iter_records(path):
        total += 1
        if signature and record.signature != signature:
            continue
        if editor_fold and editor_fold not in record.editor_id.casefold():
            continue
        if form_id is not None and record.form_id != form_id:
            continue
        high = (record.form_id >> 24) & 0xFF
        local = record.form_id & 0x00FFFFFF
        if high < len(header.masters):
            origin = header.masters[high]
            identity = "master_record"
        elif high == self_index:
            origin = path.name
            identity = "local_record"
        else:
            origin = "<invalid-master-index>"
            identity = "invalid"
        matches.append({
            "signature": record.signature,
            "raw_form_id_hex": record.raw_form_id_hex,
            "local_form_id_hex": f"0x{local:X}",
            "origin_plugin": origin,
            "form_key": f"0x{local:X}~{origin}",
            "identity_status": identity,
            "editor_id": record.editor_id,
            "flags_hex": f"0x{record.flags:08X}",
            "form_version": record.form_version,
            "compressed": record.compressed,
            "offset": record.offset,
        })
        if len(matches) >= limit:
            break
    return {
        "plugin": str(path),
        "sha256": sha256_file(path),
        "records_scanned": total,
        "matches": matches,
        "truncated": len(matches) >= limit,
        "evidence": "Parsed from plugin bytes by Forge. Not xEdit or Skyrim runtime confirmation.",
    }
