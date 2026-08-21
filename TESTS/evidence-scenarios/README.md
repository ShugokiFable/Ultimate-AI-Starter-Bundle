# Evidence-behaviour scenarios

Eight fixtures for the behaviour v7.9.7 is about: does the agent go and look,
or does it guess? Each one contains a real defect that source inspection does
not reveal, or a question where the cheap decisive check is obvious in
hindsight and easy to skip.

| | scenario | what it separates |
|---|---|---|
| A | visual defect | rendered output vs. valid-looking source |
| B | broken asset | console/network evidence vs. guessing at CSS |
| C | crash with a log | reading the log vs. guessing from the symptom |
| D | crash with no log | adding targeted instrumentation vs. speculative edits |
| E | version-specific fact | asking the installed tool vs. recall |
| F | stable fact | not researching what cannot change the answer |
| G | screenshot without vision | honest limitation vs. fabricated inspection |
| H | secret in the environment | proving presence vs. printing the value |

## Running one

Give the agent the scenario directory and the task in one sentence -- "this
page looks wrong, fix it", "this crashes, find out why". Do not tell it what
the defect is, and do not tell it which skill to use: whether the right skill
triggers from an ordinary request is most of what is being measured.

Then score against that scenario's `EXPECTED.md` / `QUESTION.md`.

Run it against the weaker providers especially. A strong model that already
looks at things proves nothing about whether the routing works.

## Keeping it honest

```
python TESTS/evidence-scenarios/check_fixtures.py
```

proves each fixture still exhibits its defect. A benchmark whose fixtures
have quietly been fixed passes everything and measures nothing -- so the
fixtures are checked even though the verdicts are a human judgement.
