> **Pack version 5.0.0:** All listed AIs receive the same expanded skill set (houseCARL, Spooky, Forge, codebase-memory, Headroom, Superpowers, Ponytail, CodeBurn). Differences are mainly MCP/plugin UX and model quality — not missing V5 skills after install.
# Which AI Should I Use for Skyrim Modding?

**Applies to:** Codex / GPT, Claude Code, Grok Build, Kimi Code, and Hermes Agent  
**Updated:** July 22, 2026  
**Skill library:** V4 framework-authority and extended-FormID edition

> **Recommended default:** Use **Codex** for the actual implementation, **Claude Code** for architecture and hostile review, **Kimi Code** for large-context exploration, **Grok Build** for fast research and prototypes, and **Hermes** as a persistent coordinator when you want one agent shell around different models.

---


## Do not make me read the whole guide

Use the row matching the job. When an exact model is unavailable, choose the strongest current equivalent in that application.

| Job | Use this | Model and reasoning | Why |
|---|---|---|---|
| **New mod from scratch** | **Codex** | **GPT-5.6 Sol, Extra High** | Best balance of architecture, implementation, tools, validation, and final artifacts. |
| New mod from scratch with several truly independent components | **Codex** | **GPT-5.6 Sol, Ultra** | Ultra delegates independent work. Do not use it when everyone would edit the same plugin or source tree. |
| Architecture-first design before anybody writes files | **Claude Code** | **Fable 5, High or xhigh** | Strong requirements, lifecycle, compatibility, and preservation reasoning. |
| Huge architecture job that naturally splits into research, design, and review | **Claude Code** | **Fable 5, ultracode** | Ultracode adds workflow orchestration. It is excessive for a small edit. |
| **Small safe edit** | **Codex** | **GPT-5.6 Terra, Medium** | Faster and cheaper while still capable of inspecting and validating the change. |
| Medium existing-mod update | **Codex** | **GPT-5.6 Terra High** or **Sol High** | Terra for ordinary work; Sol when records, runtime behavior, or several systems interact. |
| Major rework or modernization | **Codex** | **GPT-5.6 Sol, Extra High** | Needs careful preservation, implementation, and final packaging. |
| SKSE, CommonLib, native DLL, hooks, offsets, ABI, or reverse engineering | **Codex** | **GPT-5.6 Sol, Max** | Use maximum reasoning for native correctness. Require a Claude or second-Codex review. |
| ESP/ESL/ESM, VMAD, FormIDs, quests, or complex Papyrus binding | **Codex** | **GPT-5.6 Sol, Extra High or Max** | These fail catastrophically when the schema or binding model is guessed. |
| Crash-log diagnosis | **Codex** | **GPT-5.6 Sol, Extra High** | Strong at evidence timelines, binary/plugin inspection, and actionable repair. |
| Final hostile review before release | **Claude Code** | **Fable 5, xhigh** | Best place to challenge scope loss, invalid assumptions, and false validation claims. |
| Extremely difficult final review | **Claude Code** | **Fable 5, max** | Use for one correctness-critical audit, not as the daily default. |
| Read an enormous repository, documentation vault, or many logs | **Kimi Code** | **K3 High** | Best use is broad exploration and a structured implementation handoff. |
| Huge independent exploration streams | **Kimi Code** | **K3 Max** | Parallelize research, not several writers changing one tightly coupled artifact. |
| Fast web research, locating tools, or a rough prototype | **Grok Build** | **High, with `/plan` before edits** | Very fast scout. Send the result to Codex or Claude before release. |
| Persistent personal coordinator across sessions | **Hermes** | **Strongest available coding/reasoning backend** | Hermes quality depends on its selected model. Use it to coordinate skills, profiles, and durable workflows. |
| Unknown game or unfamiliar framework | **Codex first** | **GPT-5.6 Sol, Extra High** | Inspect the installed game and official framework sources before choosing an architecture. |

### One-line default

- **Ordinary existing-mod improvement:** Codex, Terra High.
- **Complex plugin, VMAD, quest, or multi-system repair:** Codex, Sol High or Extra High.
- **Reviewing the plan or final result:** Claude Code, Fable 5, xhigh.
- **Tiny edit:** Codex, GPT-5.6 Terra, Medium.
- **Native DLL or dangerous binary work:** Codex Sol Max, then Claude review.
- **Massive reading and exploration:** Kimi K3 High.
- **Fast research or prototype:** Grok Build High with `/plan`.
- **Long-term coordinator:** Hermes with the strongest suitable backend.
- **Ultra or ultracode:** use only when the work genuinely splits into independent streams.

> **Critical rule:** one writer owns each tightly coupled plugin, DLL, installer, generated configuration set, or release archive. Other agents may research or review it, but they do not edit it concurrently.

---

## Fast answer

| What you are doing | Best first choice | Best backup or reviewer |
|---|---|---|
| Building or repairing a Skyrim mod | **Codex** | Claude Code |
| SKSE / CommonLibSSE-NG DLL work | **Codex** | Claude Code |
| ESP/ESL/ESM, VMAD, FormID, record work | **Codex** | Claude Code |
| Papyrus architecture and code review | **Claude Code** | Codex |
| Crash-log diagnosis | **Codex** | Claude Code |
| Huge repository or documentation exploration | **Kimi Code** | Claude Code |
| Large SPID, KID, or SkyPatcher research pass | **Kimi Code** | Grok Build |
| Fast web research or rough prototype | **Grok Build** | Codex |
| Final release audit and packaging review | **Claude Code** | Codex |
| Long-running personal agent with persistent learning | **Hermes** | Depends on its selected model |
| One tightly coupled file or plugin | **One Codex or Claude writer** | Read-only reviewer |
| Many independent research questions | **Kimi, Codex, or Hermes delegation** | Claude synthesis |

---

## Overall ranking for this Skyrim workflow

### 1. Codex / GPT: best overall implementer

**Use it for**

- SKSE and CommonLibSSE-NG plugins
- Papyrus implementation
- typed ESP/ESL/ESM tooling
- plugin repair
- VMAD and binding investigations
- deterministic generators
- crash-log analysis
- FOMOD creation
- packaging and release artifacts
- difficult repository surgery

**Why**

Codex is the best fit when the job must end as an actual working folder, source tree, script, DLL project, or ZIP. It is particularly strong when it can inspect files, edit them, run validators, compare diffs, and produce a concrete artifact.

Its main danger is not lack of intelligence. It is going too deep into reconstruction or analysis without preserving enough time for runtime-safe implementation and final packaging. Raw plugin surgery is also dangerous unless typed tooling or exact schema evidence exists.

**Recommended reasoning**

- Routine edits and ordinary mod work: **High**
- Plugins, DLLs, crashes, architecture, VMAD, difficult Papyrus: **highest practical reasoning mode**
- Maximum mode: only for a rescue, hostile audit, or unusually difficult native-code problem
- Parallel agents: only for genuinely independent research or components

**Practical estimates**

| Measure | Estimate |
|---|---:|
| Complex-task reliability | **85–92%** |
| Speed / efficiency | **8/10** |
| Deep technical reasoning | **9.5/10** |
| Artifact completion | **9/10** |
| Need for independent review | **Medium** |

**Bottom line:** Start with Codex when code, plugin data, native DLLs, or a distributable artifact must actually be produced.

---

### 2. Claude Code: best architect and reviewer

**Use it for**

- architecture
- requirements cleanup
- code review
- compatibility analysis
- migration planning
- Papyrus lifecycle reasoning
- understanding large systems
- final hostile audit
- checking whether implementation removed intended behavior

**Why**

Claude Code is excellent at maintaining a coherent conceptual model of a complicated project. It is especially valuable before implementation and after implementation, when you need someone to ask whether the design is correct, whether a migration preserved behavior, and whether the claimed validation really proves anything.

Its main risks are context accumulation, usage boundaries, and ending with a superb diagnosis but an unfinished artifact. Invoked skills and long conversations must be managed deliberately.

**Recommended reasoning**

- Routine review and planning: **High**
- Major architecture, plugin review, difficult compatibility analysis: **xhigh**
- Maximum: rare final audit or rescue
- Use subagents for exploration and review, not several writers editing one tightly coupled artifact

**Practical estimates**

| Measure | Estimate |
|---|---:|
| Complex-task reliability | **82–90%** |
| Speed / efficiency | **7.5/10** |
| Deep technical reasoning | **9.5/10** |
| Review quality | **9.5/10** |
| Need for implementation follow-up | **Medium** |

**Bottom line:** Use Claude before Codex for the blueprint, or after Codex as the skeptical inspector with a flashlight and a crowbar.

---

### 3. Kimi Code: best large-context explorer

**Use it for**

- mapping very large repositories
- reading many documents
- comparing framework versions
- extracting requirements
- independent research streams
- exploring logs and generated output
- preparing structured implementation packets
- long-horizon investigation

**Why**

Kimi is strongest when the problem begins as a mountain of context. It can explore broadly, divide independent research, and produce useful structured handoffs. It is a good first pass before implementation when the repository, documentation, and compatibility matrix are too large to hold comfortably in one ordinary coding session.

Its main danger is delegation without enough context. Kimi subagents have isolated contexts, so every task packet must include exact paths, constraints, forbidden actions, and expected evidence. Parallel writers should not touch one coupled plugin or installer.

**Recommended reasoning**

- Mechanical and deterministic tasks: **Low**
- Normal exploration and coding: **High**
- Architecture, difficult debugging, native code: **Max**
- Swarm or broad parallelism: only for independent questions

**Practical estimates**

| Measure | Estimate |
|---|---:|
| Complex-task reliability | **76–86%** |
| Speed / efficiency | **8.5/10** |
| Large-context exploration | **9.5/10** |
| Final artifact reliability | **7.5/10** |
| Need for review | **Medium–high** |

**Bottom line:** Use Kimi to map the continent, then give the verified route to Codex or Claude.

---

### 4. Grok Build: best fast scout and prototype engine

**Use it for**

- fast web research
- locating relevant tools and documentation
- rough prototypes
- brainstorming implementation paths
- quick repository reconnaissance
- generating first-pass scripts
- dividing large research questions
- finding likely compatibility pressure points

**Why**

Grok is fast and productive. It can cover a lot of ground quickly and is useful when you need momentum rather than ceremony.

That same speed is its central risk. In the supplied histories, the recurring danger pattern was editing before fully preserving scope, generating giant malformed configurations, losing FOMOD branches, and treating partial validation as completion.

**Recommended reasoning**

- Use **High**
- Enter plan mode before broad edits
- Generate huge SPID, KID, and SkyPatcher outputs through deterministic scripts and chunks
- Give final ownership to one writer
- Require Codex or Claude review before release

**Practical estimates**

| Measure | Estimate |
|---|---:|
| Complex-task reliability | **70–82%** |
| Speed / efficiency | **9/10** |
| Research and prototyping | **9/10** |
| Final release reliability | **7/10** |
| Need for review | **High** |

**Bottom line:** Grok is the scout bike. It gets to the ruins first, but another agent should verify the bridge before the convoy drives over it.

---

### 5. Hermes Agent: best persistent coordinator

**Use it for**

- a personal long-running agent
- persistent workflows
- skill discovery
- coordinating other coding agents
- scheduled or repeated work
- cross-session learning
- model routing
- managing separate profiles
- acting as a front end for Codex, Claude, Kimi, or other models

**Why**

Hermes is not one fixed reasoning model. It is an agent system that can run different underlying models, keep profiles, load skills progressively, preserve memory, and delegate work. Its quality therefore depends heavily on the selected main model, tool configuration, and whether its accumulated learning remains clean.

Hermes is strongest as the conductor, not automatically the best violin. Configure a frontier model for hard architecture or code, use faster auxiliary models for small jobs, and let the Skyrim skills plus evidence registry control the workflow.

**Recommended reasoning**

- Simple file operations, formatting, and summaries: faster model
- Complex Skyrim design, plugins, and architecture: frontier reasoning model
- Keep one coding owner for coupled changes
- Treat self-modified skills as candidates until reviewed
- Use separate profiles when different purposes should not share memory or state

**Practical estimates**

| Measure | Estimate |
|---|---:|
| Complex-task reliability | **68–92%**, model-dependent |
| Speed / efficiency | **7–9/10**, model-dependent |
| Persistent coordination | **9.5/10** |
| Standalone coding quality | **Depends on backend** |
| Configuration sensitivity | **High** |

**Bottom line:** Hermes is the chassis. The engine you install determines how fast and accurately it drives.

---

## Best workflow for serious Skyrim projects

### Stage 1: Explore

Use **Kimi Code** or **Grok Build** to:

- inventory the project
- inspect documentation
- identify framework versions
- build compatibility maps
- locate likely failure zones

Do not let this stage directly rewrite the entire project.

### Stage 2: Architect

Use **Claude Code** to:

- turn findings into requirements
- preserve intended behavior
- define ownership and versioning
- design validation gates
- challenge assumptions

### Stage 3: Implement

Use **Codex** to:

- create the next versioned snapshot
- edit the source
- build deterministic generators
- compile
- validate
- package the artifact

### Stage 4: Hostile review

Use **Claude Code** or a second Codex thread to:

- inspect the actual diff
- compare against the last known-good version
- check FOMOD branches and optional content
- audit plugin and Papyrus semantics
- verify that the final ZIP matches the validated staging folder

### Stage 5: Coordinate and remember

Use **Hermes** when you want:

- a persistent supervisor
- profile separation
- recurring work
- long-term skill and workflow management
- routing between different coding agents

---

## Recommended two-agent combinations

| Combination | Best use |
|---|---|
| **Codex + Claude** | Best overall quality for hard Skyrim development |
| **Kimi + Codex** | Huge context exploration followed by strong implementation |
| **Grok + Codex** | Fast research and prototype followed by disciplined production |
| **Claude + Kimi** | Architecture plus large-document or repository analysis |
| **Hermes + Codex** | Persistent coordinator with strong implementation backend |
| **Hermes + Claude** | Persistent coordinator with strong architecture and review |

---

## Do not use parallel writers for these

Keep one implementation owner for:

- one ESP/ESL/ESM
- one VMAD-bearing plugin
- one FOMOD tree
- one generated SPID/KID/SkyPatcher output set
- one Papyrus state-machine family
- one SKSE/CommonLibSSE-NG DLL
- one release ZIP
- one tightly coupled source tree

Other agents may research or review in parallel, but one owner merges the work.

---

## How the estimates should be read

The percentages above are **practical reliability ranges**, not vendor benchmarks.

They combine:

- observed behavior from the supplied Codex and Grok histories
- indirect evidence from previous Claude-related work
- official provider capabilities
- the expected improvement from the tailored skills, error registry, versioned snapshots, and mandatory validation gates

A “90%” estimate does not mean nine out of ten arbitrary prompts succeed. It means the tool is comparatively likely to complete that class of Skyrim task correctly **when given the packaged workflow, exact files, enough time, and the required validation process**.

Runtime testing can still overturn every structural success claim.

---

## Final recommendation

For the least painful default:

1. **Codex** performs the implementation.
2. **Claude Code** reviews architecture and the final diff.
3. **Kimi Code** handles enormous context or broad exploration.
4. **Grok Build** handles fast scouting and prototypes.
5. **Hermes** coordinates persistent workflows and whichever backend model you trust.

When only one application is available, choose **Codex** for the broadest Skyrim workload.

---

## Official capability references

- Codex app and parallel workflows: https://developers.openai.com/codex/app
- Codex cloud coding agent: https://developers.openai.com/codex/cloud
- Claude Code overview: https://code.claude.com/docs/en/overview
- Claude Code skills: https://code.claude.com/docs/en/skills
- Claude Code subagents: https://code.claude.com/docs/en/sub-agents
- Claude Code model and effort configuration: https://code.claude.com/docs/en/model-config
- Grok Build overview: https://docs.x.ai/build/overview
- Grok Build skills: https://docs.x.ai/build/features/skills-plugins-marketplaces
- Grok Build modes and commands: https://docs.x.ai/build/modes-and-commands
- Kimi Code overview: https://www.kimi.com/code/docs/en/
- Kimi Code skills: https://www.kimi.com/code/docs/en/kimi-code-cli/customization/skills.html
- Kimi Code agents and subagents: https://www.kimi.com/code/docs/en/kimi-code-cli/customization/agents.html
- Hermes skills: https://hermes-agent.nousresearch.com/docs/user-guide/features/skills
- Hermes profiles: https://hermes-agent.nousresearch.com/docs/user-guide/profiles
- Hermes model configuration: https://hermes-agent.nousresearch.com/docs/user-guide/configuring-models


## V4 skill routing

Use `skyrim-frameworks-index` for selection. Exact grammar belongs to the dedicated KID, SPID, SkyPatcher, and BOS skills. Plugin work must pass the extended-FormID and first-master gate.
