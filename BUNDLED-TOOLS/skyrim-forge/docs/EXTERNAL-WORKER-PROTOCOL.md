# External worker protocol

Invocation:

```text
Worker.exe --job <job.json> --result <result.json>
```

Input schema: `skyrim-forge-external-worker/1`.

Required result fields:

```json
{
  "job_id": "matching-id",
  "status": "success",
  "outputs": ["<absolute-output-path>"],
  "warnings": []
}
```

Allowed status values are `success`, `failure`, and `blocked`. A zero process exit without a valid result file is a failure. Workers should never write outside their Forge-provided output directory.
