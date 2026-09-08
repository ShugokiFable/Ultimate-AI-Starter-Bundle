# Repository completion contract

Apply when creating, finishing, or preparing a GitHub project for users. Keep the work proportional: a library needs installable packages and examples; a desktop app needs a working build/install path; a documentation repository may need link checks and no binary release. An explicit empty-repo request stays empty.

## Decide completion before writing

Record the intended user, supported platforms, install/run command, test/build commands, deliverable type, and evidence needed. Inspect existing files, default branch, licence, workflows, release history, and repository settings. Preserve personal changes. Select versions and commands from project metadata and current primary sources.

Reuse existing permissions and prior approval. Prepare implementation, tests, documentation, release notes and packaging before stopping for missing publication approval. A request to create a repository is not automatically permission to publish a public release, change visibility/access rules, buy features, or assign a licence. Ask once at the final boundary only if that authority is actually missing; report exactly what is ready and what is pending. If publishing is already authorized, finish it without asking again.

## Baseline and proof

| Area | What to deliver | What proves it |
|---|---|---|
| Usable product | Working entrypoint, requirements, configuration example without secrets, reproducible install/build and appropriate packaged artifact | Run the documented quick start from a clean checkout or extracted artifact |
| Public presentation | Purpose, supported platforms, quick start, real previews for visual products, honest status, changelog, credits and licence/asset provenance | Inspect rendered README and final preview images; no unperformed runtime claims |
| CI | Real build/test/lint commands for the actual stack on push and pull request; relevant supported OS coverage | All required checks completed successfully on the exact pushed SHA |
| Dependencies | Dependency graph plus Dependabot alerts, security updates, and version-update configuration for actual manifests/directories including GitHub Actions | Read settings independently; a dependabot.yml file proves only version-update configuration |
| Code scanning | CodeQL default setup for supported languages, or an existing justified advanced setup / suitable scanner | Read setup state and a successful completed analysis of the relevant commit; enabled alone does not prove analysis |
| Secret protection | Secret scanning and push protection where supported and authorized | Read their reported states; never print raw secret-alert responses or credentials |
| Vulnerability reporting | SECURITY.md with supported versions and a real reporting route; private vulnerability reporting where available | Reporting endpoint is enabled and the policy points to it; no invented email address |
| Release | Versioned usable assets, release notes, checksums; source-only is appropriate only for source-delivered projects | Tag resolves to the tested SHA; download each published asset, require nonempty bytes and matching SHA-256 |

GitHub settings are separate from tracked files and are not inherited by simply cloning or creating a repository. Verify each new repository. Distinguish **configured**, **verified**, **not applicable**, and **blocked/unavailable**; a 403/404, missing response, or unsupported feature is not enabled and is not zero alerts. Check plan/visibility eligibility before proposing paid features. Repository-level checks do not authorize an account-wide sweep or settings change.

## Workflow quality

- Derive the default branch and build commands from the project; do not assume `main`, npm, or a Windows developer path.
- Use minimal job permissions, sensible timeouts and concurrency. Run untrusted PR code without write credentials. Do not use `pull_request_target` to check out and execute untrusted PR code with privileges.
- Resolve third-party actions to verified immutable commit SHAs with a version comment; let Dependabot maintain the pins. Do not guess action versions or hashes.
- Choose one CodeQL setup. Default setup disables advanced workflows; leaving an inert workflow creates broken dependency-update noise.
- Keep scanners matched to supported languages. No generic always-green replacement for a failing required build.
- Review dependency PR diffs and their own CI; group coupled action updates. Do not blindly auto-merge major versions. For manifest-gated repositories, update integrity metadata in the same change.
- Add branch rules only when authorized and after discovering actual check names. Do not require nonexistent checks or a second reviewer on a solo project without agreement.
- Use built-in CI, CodeQL, Dependabot and secret protection first. Another review bot is optional and must demonstrate additional value and have approved access/cost.

## Read-only GitHub checks

Use the actual `OWNER/REPO`. These endpoints inspect different controls; one green indicator cannot stand in for the others:

```text
gh api repos/OWNER/REPO --jq '{default_branch,security_and_analysis}'
gh api repos/OWNER/REPO/vulnerability-alerts --silent
gh api repos/OWNER/REPO/automated-security-fixes
gh api repos/OWNER/REPO/private-vulnerability-reporting
gh api repos/OWNER/REPO/code-scanning/default-setup
gh run list --repo OWNER/REPO --commit SHA --json headSha,status,conclusion,workflowName
gh api repos/OWNER/REPO/commits/SHA/check-runs --paginate
```

Check the exit status. The alerts-enable endpoint returns 204 on success, not a JSON boolean. Paginate when counting open alerts; select counts/status only, never raw secret content. For advanced CodeQL setup, inspect its workflow and analysis results instead of interpreting an unconfigured default as no scanning.

## Final handoff

Report the repository URL, tested commit, CI result, security controls verified versus unavailable, artifact/release URL and downloaded-hash result when published. If publication needs approval, give the concrete version, tested commit and prepared artifacts; mark it **prepared, not published**. Never finish with only "repo created" when these deliverables are in scope.

Primary references, checked 2026-09-07:

- [GitHub security quickstart](https://docs.github.com/en/code-security/getting-started/quickstart-for-securing-your-repository)
- [CodeQL default setup and advanced-workflow interaction](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/configure-code-scanning/configure-code-scanning)
- [Dependabot alerts configuration](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/configure-dependabot-alerts)
