# Distribution and patcher framework engineering

Forge uses versioned profiles rather than one timeless parser:

- SPID 7.3
- KID 4.0.6
- BOS 3.4.1
- SkyPatcher 6.4.2 core INI shape and placement
- FLM 1.8.1 core INI shape

`framework-build` renders only modeled syntax and lints the generated file. Existing syntax outside the modeled profile must be reported as unverified or warning-level, not silently rewritten. A clean static result does not prove that FormIDs resolve or that runtime distribution occurred. Check the corresponding SKSE log.
