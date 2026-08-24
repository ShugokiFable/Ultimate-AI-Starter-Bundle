---
name: process-lifecycle-cleanup
description: Use when code launches child processes, local servers, workers, browsers, watchers, or temporary services that must not survive failure or shutdown.
---

# Process Lifecycle Cleanup

Every child process needs an owner and a terminal cleanup path.

## Contract

- Record the child process identity/handle at launch.
- Distinguish daemon-by-design from task-scoped children.
- On normal completion, error, timeout, cancellation, or parent exit, stop task-scoped children and wait for termination.
- Clean temporary ports, lock files, pipes, sockets, and working directories owned by the process.
- Never kill by broad process name when an exact PID/job/process tree is available.
- Verify shutdown: the process is gone and owned resources are released.

A UI closing while its worker remains alive is a failure. Cleanup errors must be surfaced when they can leave corrupt or conflicting state.
