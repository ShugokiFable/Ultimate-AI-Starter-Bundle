# Coordinate-free UI Automation

The fallback worker uses Windows UI Automation elements identified by process ID, window title, Automation ID, and accessible name.

Allowed actions are wait, invoke, select, set value, read value, screenshot, and close window. Jobs containing screen coordinates, OCR, or image matching are rejected before execution.

Each sequence has a timeout. Any missing control or unexpected state blocks the transaction. This is a narrow fallback, not a generic desktop agent.
