# Saints Row binary format reference

All facts below were verified against ThomasJepp.SaintsRow source (rev133
source zip, Packfiles/Version0A + AssetAssembler/Version0B/0C) and the
Volition SDK. The Python ports live in
`S:\Apps\Saints Row Tools\SaintsRowForge\src\srforge\formats\`.

## VPP packfile v0x0A (.vpp_pc / .str2_pc)

Header — 10 x u32 LE, 0x28 bytes:
```
0x00 descriptor   = 0x51890ACE
0x04 version      = 0x0A
0x08 header_checksum  (CRC over bytes 0x0C..0x28)
0x0C file_size
0x10 flags        bit0 compressed, bit1 condensed
0x14 num_files
0x18 dir_size     (0x18 * num_files)
0x1C filename_size
0x20 data_size    (uncompressed total)
0x24 compressed_data_size  (0xFFFFFFFF when uncompressed)
```
Entry — 0x18 bytes each at 0x28: `filename_offset u32 | pad u32 |
start u32 | size u32 | compressed_size u32 | flags u16(bit0=compressed) |
alignment u16`. Name block follows (offsets relative to name-block start,
2-aligned). Payload last.

- Condensed+compressed = ONE zlib stream over payloads in entry order;
  per-entry compressed_size comes from sync-flush boundaries.
- str2 semantics when writing: entries aligned to 16 in the uncompressed
  accounting; `data_size` counts padded size for all but last entry.
- Reference reader recomputes `start` for condensed archives; don't trust
  stored start values blindly.

## Asset Assembler .asm_pc

Header 8 bytes: signature `0xBEEFFEED` u32, version u16 (`0x0B` SRTT,
`0x0C` SRIV/GOOH), num_containers i16. Then three type tables
(allocator/primitive/container): each `u32 count`, then per entry
`u16 len + ascii name + byte id`. Then containers:

```
u16 len + ascii name
byte container_type
u16 flags
i16 primitive_count
u32 packfile_base_offset
[0x0C only] byte compression_type      <- THE ONLY 0B/0C difference
u16 len + ascii stub_parent (empty ok)
i32 aux_len + aux bytes
i32 total_compressed_packfile_read_size
per primitive: WriteTimeSizes { u32 cpu_size; u32 gpu_size }  (all first)
per primitive: u16 len + ascii name + PrimitiveData(13 bytes):
  type u8, allocator u8, flags u8, extension_index u8,
  cpu_size u32, gpu_size u32, allocation_group u8
```

ASM update after rebuilding a str2 (reference BuildPackfile -asm logic):
find container whose name matches the str2 stem (case-insensitive,
extension-stripped); set `packfile_base_offset` = first payload byte of the
rebuilt str2; `total_compressed_read_size` = header
compressed_data_size; for each primitive whose name exists in the str2,
cpu_size = entry.size and gpu_size = matching `.gNNN` twin's size.

## XTBL

Tab-indented XML. Record identity = text content of `<Name>` child
(NOT an attribute) — duplicate names are possible and must be detected as a
validation failure rather than silently merged by attribute-based parsing.
Preserve comments (ElementTree drops them; use comment-aware parsing).
Semantic diff = per-record/per-field value changes, not line diff.

## le_strings

Header 12 bytes: id `0xA84C7F73`, version u16 =1, bucket_count u16,
string_count u32. Bucket array right after header (8 bytes each: count +
table offset). Table entries = absolute u32 offsets to records
`[hash u32][utf-16-le chars][NUL u16]`. Bucket index = hash & (count-1);
bucket_count power-of-two ladder 32..1024.

## Volition CRC

Standard CRC-32 table (poly 0xEDB88320), init 0, no final xor; strings are
lowercased before hashing.

## Precedence

loose files > patch_compressed.vpp_pc > patch_uncompressed.vpp_pc > base
vpps (alphabetical among bases). Resolve winner before editing anything.
