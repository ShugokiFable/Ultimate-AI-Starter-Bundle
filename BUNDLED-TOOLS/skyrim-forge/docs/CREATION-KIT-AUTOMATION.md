# Creation Kit automation

Forge supports a version-pinned Creation Kit/CKPE worker for operations such as FaceGen generation, script-property binding, fragment compilation, SEQ generation, and narrowly typed record work.

A worker must return exact output paths and changed-record evidence. Forge hashes the outputs and reopens plugins when possible.

Where a worker does not exist, Forge can run a pre-calibrated Windows UI Automation job. That fallback uses accessible control identity, never blind coordinates or OCR. It remains inappropriate for automatic navmesh quality, landscape composition, dialogue timing, or visual placement decisions.
