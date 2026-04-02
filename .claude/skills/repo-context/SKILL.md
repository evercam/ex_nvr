---
description: Analyse a repo's tech stack, directory structure, and domain to produce a REPO_CONTEXT.md that drives doc generation
---

You are analysing this repository to produce a context file that will drive documentation generation. The goal is to understand **what this repo is**, **how it's built**, and **what domain concepts and features live here**.

The optional argument is: $ARGUMENTS

If an argument is provided, treat it as a path to a seed file listing known concepts and features from another repo (e.g., the frontend). Read it and use it to look for matching entities here — but always look for new ones too.

## Step 1: Detect the tech stack

Check for build/config files at the repo root to identify the stack:

| File | Stack |
|------|-------|
| `mix.exs` | Elixir (check for Phoenix, Nerves, or plain OTP) |
| `package.json` | JavaScript/TypeScript (check for Vue, React, Express, Nuxt, Next, etc.) |
| `pyproject.toml` or `requirements.txt` | Python (check for FastAPI, Django, Flask, etc.) |
| `Cargo.toml` | Rust |
| `go.mod` | Go |

Read the identified build file to extract:
- Language and version (also check `.tool-versions`, `.mise.toml`, or runtime config)
- Framework and version
- Key dependencies that shape the architecture (ORMs, message queues, HTTP clients, AI/ML libs)
- Whether it's a monorepo (multiple apps/packages) or single-app

Also read `AGENTS.md`, `CLAUDE.md`, or `README.md` if they exist — these often contain curated architecture info.

## Step 2: Map the directory structure

Run `ls` at the top level and 2 levels deep to understand the layout. Then identify discovery paths based on the stack:

**Elixir/Phoenix:**
| Category | How to find |
|----------|-------------|
| schemas | Grep for `use Ecto.Schema` |
| contexts | Grep for `defmodule.*Context` or business logic modules under `lib/<app>/` |
| controllers | `lib/*_web/controllers/` |
| routers | `lib/*_web/router.ex` or `lib/*_web/routers/` |
| views/JSON | `lib/*_web/views/` or `lib/*_web/controllers/*_json.ex` |
| channels | `lib/*_web/channels/` |
| workers | Grep for `use Oban.Worker` or background job modules |
| config | `config/*.exs` |
| migrations | `priv/repo/migrations/` |

**Python/FastAPI:**
| Category | How to find |
|----------|-------------|
| models | `**/models/`, `**/schemas/` — Grep for `class.*BaseModel` or `class.*Model` |
| DTOs | `**/dto/` — request/response shapes |
| routes | `**/routes/`, `**/endpoints/` — Grep for `@router` or `@app` decorators |
| services | `**/services/`, `**/usecases/` |
| controllers | `**/controllers/` |
| config | `config.py`, `settings.py`, `**/config/` |
| tests | `tests/`, `test/` |

**TypeScript (Node/Vue/React):**
| Category | How to find |
|----------|-------------|
| types | `**/types/`, `**/interfaces/` |
| pages/routes | `**/pages/`, `**/routes/` |
| components | `**/components/` |
| stores | `**/stores/`, `**/state/` |
| services/API | `**/api/`, `**/services/` |
| utils | `**/utils/`, `**/helpers/` |
| config | `tsconfig.json`, framework config files |

For each category, verify the paths exist using Glob before including them. Record the actual glob patterns that match.

If the repo is a monorepo (multiple apps/packages), list each app/package separately with its role.

## Step 3: Select doc section templates

Based on the stack, select the appropriate section templates. These define what sections each doc type will contain.

**For ALL stacks, both concept and feature docs start with:**

> **Overview** — A human-friendly explanation of what this entity/feature is, why it exists, and how it fits into the bigger picture. Write for a new team member who needs to understand the domain, not just the code. Include the business context: who uses it, what problem it solves, what would break if it didn't exist. This section should capture institutional knowledge that isn't obvious from reading the code.

Then add stack-appropriate technical sections:

**backend-api** (Phoenix, FastAPI, Express, Django):
- Concept: Overview, Data model (schemas/types, key fields, associations), API surface (routes, methods, request/response), Business logic (context functions, workflows, jobs), Data persistence (queries, caching, migrations), Related concepts, Business rules
- Feature: Overview, How it works (request flow: route → controller → context → repo → response), Architecture (relevant files), Integrations (external services, message queues), Data contracts (JSON shapes, WebSocket messages)

**frontend-app** (Vue, React, Next, Nuxt):
- Concept: Overview, Data model (types, key fields, enums), API surface (client methods), State management (stores, actions, getters), Where it appears (feature links), Related concepts, Business rules
- Feature: Overview, How it works (user action → component → store → API → state), Architecture (relevant files, component tree), Data contracts (events, WebSocket channels, types)

**data-pipeline** (ingest, ETL, ML pipelines):
- Concept: Overview, Data model (schemas, message formats), Pipeline stages (where this entity enters and exits the pipeline), Input/Output contracts (message shapes, API calls), Related concepts, Configuration
- Feature: Overview, How it works (data flow through the pipeline), Architecture (relevant files), Integrations (upstream/downstream services, queues, storage), Data contracts (message formats, API calls)

**embedded/device** (Nerves, NVR, edge):
- Concept: Overview, Data model (schemas, config structures), API surface (REST/WebSocket endpoints), System integration (OTP supervision trees, hardware interfaces), Storage (local DB, file system), Related concepts, Business rules
- Feature: Overview, How it works (system-level flow), Architecture (relevant files, supervision tree), Integrations (hardware, network protocols), Configuration

If the repo spans multiple profiles (e.g., a Phoenix app with a pipeline component), note which profile applies to which part.

## Step 4: Discover candidate concepts

Concepts are domain entities — the nouns of the system. Search for them by:

1. **Schema/type discovery**: Based on the stack, find entity definitions:
   - Elixir: Grep for `use Ecto.Schema` and `defmodule` — extract module names
   - Python: Grep for `class.*BaseModel`, `class.*Model`, `class.*Schema` — extract class names
   - TypeScript: Grep for `export (interface|type)` in type directories — extract type names

2. **Controller/route discovery**: Extract resource names from REST patterns:
   - Elixir: Grep for `resources` and `pipe_through` in router files, and controller module names
   - Python: Grep for `APIRouter` and route decorator paths
   - TypeScript: Grep for route definitions

3. **Filename patterns**: Scan the discovery paths for files named after singular nouns (e.g., `camera.ex`, `camera.ts`, `camera.py`)

4. **If a seed file was provided**: Read it, extract the concept names, and Grep for each one in this repo. Mark which ones are found here too.

Deduplicate results. Normalise all names to kebab-case. For each candidate, note which files define it.

## Step 5: Discover candidate features

Features are things the product does — the verbs/workflows. Search for them by:

1. **Route grouping**: Look at route definitions and group related endpoints into logical features:
   - Elixir: Parse router scopes and controller names
   - Python: Parse route file names and path prefixes
   - TypeScript: Parse page directories or route configs

2. **Controller analysis**: Each controller or route group often corresponds to a feature

3. **If a seed file was provided**: Check which known features have code here

For each candidate feature, note the primary files (controllers, routes, services).

## Step 6: Present and confirm

Present the full context to the user in the REPO_CONTEXT.md format (see Step 7). Ask them to:
- Confirm or correct the stack info
- Add/remove/rename concepts
- Add/remove/rename features
- Adjust discovery paths

## Step 7: Write docs/REPO_CONTEXT.md

Create the `docs/` directory if it doesn't exist, then write `docs/REPO_CONTEXT.md`:

```markdown
---
repo: <repo-name>
stack: <language>-<framework>
generated_at: <ISO timestamp>
---

# Repo Context: <repo-name>

## What this repo does

<2-3 sentences explaining the repo's role in the system. What part of Evercam does it own? What would break if this repo didn't exist?>

## Stack

| Property | Value |
|----------|-------|
| Language | <language and version> |
| Framework | <framework and version> |
| Build tool | <build tool> |
| Test framework | <test framework> |
| Key dependencies | <notable deps that shape architecture> |

## Apps / Packages

<Only include if monorepo. Otherwise omit this section.>

| App/Package | Path | Role |
|-------------|------|------|
| <name> | `<path>/` | <one-line role> |

## Discovery Paths

| Category | Glob patterns | Description |
|----------|--------------|-------------|
| <category> | `<glob>` | <what's found here> |

## Concept Doc Template

<Paste the selected concept section list from Step 3. Include the full Overview description.>

1. **Overview** — ...
2. **Data model** — ...
...

## Feature Doc Template

<Paste the selected feature section list from Step 3. Include the full Overview description.>

1. **Overview** — ...
2. **How it works** — ...
...

## Suggested Concepts

| Concept | Key files | Notes |
|---------|-----------|-------|
| <kebab-name> | `<paths>` | <brief note, e.g. "also exists in frontend"> |

## Suggested Features

| Feature | Key files | Notes |
|---------|-----------|-------|
| <kebab-name> | `<paths>` | <brief note> |
```

Do NOT include a cross-repo concepts section — this skill runs within a single repo and has no access to other repos' docs.
