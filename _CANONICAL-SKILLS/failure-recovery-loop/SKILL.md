---
name: failure-recovery-loop
description: Use when a test, build, install, CI job, tool call, or repeated attempt fails and the task must continue reliably.
---

# Failure Recovery Loop

## Core rule
Failures are evidence. Preserve them, identify the **root cause**, and change one causal variable at a time.

## Loop
1. Capture the exact command, inputs, exit code, stderr/logs, and relevant state.
2. Classify: environment, dependency, syntax, logic, data, timing, permission, compatibility, or external service.
3. Form one falsifiable cause hypothesis.
4. Create the **smallest reproducer** that distinguishes that hypothesis.
5. Make the minimal causal change.
6. Re-run the reproducer. If it still fails, revise the hypothesis rather than stacking guesses.
7. Once green, run the original failing command and then the **full gate**.
8. Sweep sibling paths that share the same cause.

Never erase the evidence before understanding it. Do not turn a required failure into a warning merely to make the pipeline green. A retry without a causal change is not debugging.
