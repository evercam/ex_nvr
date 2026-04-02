---
description: Index one unindexed doc into docs/INDEX.md per invocation.
---

You are building a glossary index for this repository. Each invocation indexes ONE doc that isn't yet in `docs/INDEX.md`, then stops.

**IMPORTANT: Only index ONE doc per invocation.** Do not use agents, subagents, or background tasks.

The optional argument is: $ARGUMENTS

- No argument: find the FIRST unindexed doc and index it
- A name (e.g., `camera`): index only that doc

## Step 1: Read or create docs/INDEX.md

Read `docs/INDEX.md`. If it doesn't exist, create it with this initial structure:

```markdown
---
description: Glossary index of all documented concepts and features in this repository.
---

# Index

## Concepts

| Name | Summary | Related concepts | Related features |
|------|---------|-----------------|-----------------|

## Features

| Name | Summary | Related concepts | Related features |
|------|---------|-----------------|-----------------|
```

Parse the existing index to build a set of already-indexed doc names (from the `Name` column in both tables).

## Step 2: Find the next unindexed doc

Scan `docs/domain/*.md` and `docs/features/*.md` for all doc files. Skip any file named `index.md`.

Compare against the already-indexed set. An unindexed doc is any `.md` file in those directories whose name (without `.md`) does not appear in the index tables.

Also check for **stale entries**: names that appear in the index but whose `.md` file no longer exists. Collect these for cleanup in Step 4.

If a specific name was given as argument, check only that doc. If it's already indexed, report that and stop.

If no unindexed docs remain and no stale entries exist, report:

```
Index is complete. X concepts, Y features indexed.
```

Then stop.

Otherwise, pick the FIRST unindexed doc (alphabetically, concepts before features) and continue.

## Step 3: Read and understand the doc

Read the full doc file. Understand what this entity or feature actually is — its role in the system, what depends on it, what it depends on.

Extract:

1. **Name** — from the `name`, `concept`, or `feature` field in frontmatter. Fall back to the filename.
2. **Type** — `concept` or `feature`. Infer from the `type` field in frontmatter, or from the directory (`docs/domain/` → concept, `docs/features/` → feature).
3. **Summary** — Write a single sentence (max 120 characters) that captures what this entity or feature *is* and *why it matters*. Do not just copy the first sentence of the Overview — read the entire doc and distill it. The summary should answer: "If someone has never heard of this, what's the one sentence that gives them the right mental model?" Prefer domain language over implementation language.
4. **Related concepts** — from `relates_to.concepts` in frontmatter. Only include names that have a corresponding file in `docs/domain/`.
5. **Related features** — from `relates_to.features` in frontmatter. Only include names that have a corresponding file in `docs/features/`.

If the doc is a stub (no content beyond frontmatter, or body < 100 characters), use the summary: `*(stub — awaiting content)*`

## Step 4: Update docs/INDEX.md

Read the current `docs/INDEX.md` content.

**Add the new entry** to the appropriate table (Concepts or Features), maintaining alphabetical order within each table. Format:

```
| [name](domain/name.md) | First sentence of overview | concept1, concept2 | feature1, feature2 |
```

Use relative links: `domain/<name>.md` for concepts, `features/<name>.md` for features.

**Remove any stale entries** found in Step 2 (names in the index whose files no longer exist).

Write the updated `docs/INDEX.md`.

## Step 5: Report and stop

```
✓ Indexed: camera (concept) — "Physical IP camera deployed on a construction site..."

Remaining unindexed: 12
  Concepts: kit, nvr, project, ...
  Features: live-streaming, gate-report, ...
```

Then STOP.
