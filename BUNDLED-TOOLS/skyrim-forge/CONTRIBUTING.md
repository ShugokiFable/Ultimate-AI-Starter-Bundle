# Contributing

Changes must preserve typed jobs, no-shell process execution, workspace confinement, overwrite refusal, explicit approval, executable identity, transaction receipts, and honest evidence labels.

Run:

```text
python -m compileall -q skyrim_forge tests scripts
python -m unittest discover -s tests -v
python scripts/validate_repository.py
cd writer/native-go
gofmt -w .
go vet ./...
go test ./...
```

External-tool adapters need a production-shaped fake-tool test and a documented Windows smoke test. Do not add invented CLI arguments for third-party applications.
