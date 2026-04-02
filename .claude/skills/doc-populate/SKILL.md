---
description: Loop over stub/incomplete docs, read the watched source files, and generate full documentation content
---

You are populating documentation files for this repository. Each stub doc has frontmatter with watched paths — you read the source code at those paths and generate the doc content.

The optional argument is: $ARGUMENTS

- No argument: find the FIRST incomplete doc, populate it, then STOP
- A name (e.g., `camera`): populate only that doc (checks both `docs/domain/` and `docs/features/`)
- `domain:<name>` or `feature:<name>`: populate a specific doc by type

**IMPORTANT: Only populate ONE doc per invocation.** Do not use agents, subagents, or background tasks. Do not attempt to populate multiple docs in a single run. After completing one doc, report progress and stop. The user will re-invoke this skill for the next doc.

## Step 1: Read REPO_CONTEXT.md

Read `docs/REPO_CONTEXT.md`. If it doesn't exist, tell the user to run `/repo-context` first and stop.

Extract:
- `repo` and `stack` from frontmatter
- The concept doc template (section list)
- The feature doc template (section list)

## Step 2: Find incomplete docs

Scan `docs/domain/*.md` and `docs/features/*.md`. A doc is incomplete if:
- It contains `<!-- stub: awaiting /doc-populate -->` (freshly scaffolded)
- Its body after the YAML frontmatter has fewer than 100 characters of content
- It contains `<!-- TODO -->` markers

If a specific name was given as argument, check only that doc.

If no incomplete docs are found, report "All docs are populated." and stop.

Otherwise, list them:

```
Incomplete docs (8):
  Concepts: camera, project, user, recording, archive
  Features: camera-management, snapshot-capture, live-streaming

Populating...
```

## Step 3: Populate each doc

For each incomplete doc:

### 3a. Read the frontmatter

Extract `name`, `type`, `repo`, `stack`, `paths`, and `relates_to`.

### 3b. Read the source code

**Start with the watched paths** — expand each glob pattern in `paths` using Glob and read the matching files:
- Elixir: `.ex`, `.exs` files
- Python: `.py` files
- TypeScript: `.ts`, `.tsx`, `.vue`, `.js`, `.jsx` files

**Then explore beyond the watched paths.** The `paths` frontmatter defines what the doc *watches for staleness*, but to write a thorough doc you need broader context. Use the discovery paths from REPO_CONTEXT.md to search for additional references:

1. Generate name variants (kebab, camelCase, PascalCase, snake_case, plural forms)
2. Grep across the full codebase for these variants to find files that reference this entity/feature but aren't in the watched paths
3. Read the most relevant hits — especially:
   - Config files that mention this entity (feature flags, environment variables, permissions)
   - Test files that reveal expected behaviour and edge cases
   - Other modules that call into or depend on this entity
   - Migration files that show how the data model evolved
   - README or doc comments that explain design decisions

If any of these exploration files are clearly relevant to this entity/feature (not just a passing reference), **add them to the `paths` frontmatter**. The scaffold provides a starting point, but the populate step should refine and complete the watched paths based on what it actually finds in the code.

If the total number of files exceeds 20, prioritise:
1. Schema/model/type definitions
2. Main context/service modules
3. Controllers/routes
4. Config, tests, and callers that reveal business rules
5. Supporting files

Read the prioritised files and note which ones were skipped. You can always read skipped files in a follow-up pass if the doc feels incomplete.

### 3c. Generate content

Get the current HEAD commit hash via `git rev-parse HEAD`.

Using the section template from REPO_CONTEXT.md (concept template or feature template based on the doc's `type`), generate the full doc.

**Content rules:**

1. **Overview first, and make it count.** The Overview is the most important section. Write it for a human who needs to understand this entity or feature without reading the code. Include:
   - What it is / what it does (in domain terms, not code terms)
   - Why it exists — what problem does it solve, what would break without it
   - How it fits into the broader system — what depends on it, what it depends on
   - Who interacts with it (end users, other services, background jobs)
   - Any historical context or non-obvious design decisions visible in the code

2. **Be thorough, not padded.** A simple utility concept might be 1K tokens. A central entity like Camera might be 5K+. Let the complexity of the code drive the length. Don't pad short docs; don't truncate complex ones.

3. **Reference real code.** Name actual functions, modules, classes, routes, fields. The doc should be traceable back to the source. If someone reads "the `Cameras.create_camera/2` function validates the changeset and broadcasts via PubSub", they should be able to find that exact function.

4. **Capture knowledge that isn't obvious from the code.** Business rules, edge cases, permission checks, feature flags, the *why* behind non-obvious patterns. This is the institutional knowledge that makes these docs valuable — the stuff a new developer would spend weeks discovering.

5. **Omit empty sections entirely.** If a concept has no business rules, don't include a Business rules section. Don't write "N/A" or "None".

6. **Use the section template from REPO_CONTEXT.md** as the structure, but adapt it to what the code actually contains. The template is a guide, not a straitjacket.

7. **Cross-links:** Use relative paths for links between docs:
   - From a concept to another concept: `[project](project.md)`
   - From a concept to a feature: `[camera-management](../features/camera-management.md)`
   - From a feature to a concept: `[camera](../domain/camera.md)`
   - Only link to docs that exist (check `docs/domain/` and `docs/features/` for matching files)

### 3d. Write the doc

Replace the entire file content with the generated doc:

```markdown
---
name: <name>
type: <concept or feature>
repo: <repo>
stack: <stack>
last_updated_commit: <new HEAD hash>
paths:
  - <scaffold paths + any relevant files discovered during exploration>
relates_to:
  concepts: [<discovered concept links>]
  features: [<discovered feature links>]
---

<generated content following the section template>
```

Update `relates_to` based on what you discovered while reading the code:
- If this concept is referenced by features that have stubs in `docs/features/`, add them
- If this concept uses other concepts that have stubs in `docs/domain/`, add them
- Only add links to docs that actually exist as files

### 3e. Report progress

After each doc, briefly report:

```
✓ docs/domain/camera.md — 6 sections, ~3.2K tokens
```

## Step 4: Report and stop

After populating the single doc, report:

```
✓ docs/domain/camera.md — 6 sections, ~3.2K tokens

Remaining incomplete: 7
  Concepts: project, user, recording, archive
  Features: camera-management, snapshot-capture, live-streaming
```

Then STOP. Do not continue to the next doc. The user will re-run `/doc-populate` for the next one, or use `/loop 0 /doc-populate` to automate sequential runs.
