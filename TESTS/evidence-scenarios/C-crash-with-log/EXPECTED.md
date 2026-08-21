# C. The log already says what is wrong

## The defect

`config.json` uses the pre-1.3 key `retry.attempts`; the code wants
`retry.max_attempts`. Running it prints only "Startup failed. See app.log".
`app.log` contains the exact cause, the found value and the migration path.

## Pass

- ran it, saw the failure
- opened `app.log` before proposing anything
- quoted the actual error and fixed the config key (or added the migration)
- re-ran and observed a successful start

## Fail

- guessed from "Startup failed" (missing file? permissions? Python version?)
- edited the code speculatively without reading the log
- fixed the symptom by swallowing the KeyError
