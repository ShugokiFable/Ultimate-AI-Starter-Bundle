# Nexus Mods publication gate

Forge 4.2 treats “shareable”, “public release”, and “ready for Nexus” as a different operation from private packaging.

A Nexus publication requires a typed `skyrim-forge-nexus-publication-plan/1` document and a complete release-tree audit. Forge does not infer permission from credit, popularity, or the presence of a file on Nexus Mods.

## Workflow

```text
forge nexus-policy-status
forge nexus-scaffold <release-root> NEXUS-PUBLICATION-PLAN.json --mod-name "My Mod" --mod-version 1.0.0 --uploader "Author" --approve
# Fill every rights, permission, content, policy-review and attestation field.
forge nexus-plan-validate NEXUS-PUBLICATION-PLAN.json
forge nexus-audit NEXUS-PUBLICATION-PLAN.json <release-root>
forge nexus-build NEXUS-PUBLICATION-PLAN.json <release-root> <workspace-output> --approve
```

`nexus-build` creates:

- a final release tree;
- deterministic ZIP archive;
- Nexus BBCode page;
- credits;
- third-party notices;
- public rights manifest;
- permissions and AI disclosure documents;
- a private compliance audit that is not put in the release ZIP.

## Hard blockers

Forge blocks share-ready status when any bundled file lacks a rights record, redistribution permission is absent, required credit is missing, explicit permission lacks local evidence, Donation Points conflict with asset permissions, original game files are present, public claims lack evidence, adult classifications are incomplete, internet-connected binaries lack the required disclosure and Nexus contact evidence, or the policy review is older than 90 days.

## Human boundary

Forge validates declarations and evidence files. It cannot authenticate authorship, interpret every licence in every jurisdiction, or provide legal advice. The uploader must sign the attestation and remains responsible for the upload.

## Current official-policy evidence

The source lock is reviewed against official Nexus Mods Terms of Service, File Submission Guidelines, Adult Content Guidelines, Donation Points rules, Best Practices and, when selected, event-specific rules. Forge does not scrape Nexus Mods. A review older than 90 days blocks share-ready status.

The Nexus Terms require the uploader to possess all necessary rights and permissions, comply with the original game's terms, understand the licence granted to Nexus and its partners, and avoid prohibited scraping/text-data-mining. File Submission Guidelines require permission as well as credit, truthful claims, accurate categorisation, functional files and more-than-repackaging value for compilations.
