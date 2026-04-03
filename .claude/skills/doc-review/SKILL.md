---
description: Review one populated doc for overview accuracy against its technical sections, fix mismatches, and update relates_to.
---

You are reviewing documentation files for accuracy. Each doc has an overview that may narrow or misrepresent what the technical sections actually describe. Your job is to find and fix those mismatches.

**IMPORTANT: Only review ONE doc per invocation.** Do not use agents, subagents, or background tasks.

The optional argument is: $ARGUMENTS

- No argument: find the FIRST unreviewed doc, review it, then STOP
- A name (e.g., `camera`): review only that doc (checks both `docs/domain/` and `docs/features/`)

## Step 1: Find the next unreviewed doc

Read `docs/.reviewed` if it exists. If it doesn't exist, treat all docs as unreviewed. This file contains one doc name per line (e.g., `domain/camera`, `features/live-view`). These have already been reviewed.

Scan `docs/domain/*.md` and `docs/features/*.md` for all populated docs. A doc is populated if its body after YAML frontmatter has more than 100 characters and does not contain `<!-- stub: awaiting /doc-populate -->`.

Skip any doc whose path (relative to `docs/`, without `.md`) appears in `.reviewed`.

If a specific name was given as argument, review only that doc regardless of `.reviewed`.

If no unreviewed docs remain, report:

```
Review complete. All X docs reviewed.
```

Then STOP.

Otherwise, pick the FIRST unreviewed doc (alphabetically, concepts before features) and continue.

## Step 2: Read and understand the full doc

Read the entire doc. Parse:
- **Frontmatter**: `name`, `type` (concept or feature), `relates_to`
- **Overview section**: everything under `## Overview`
- **All other sections**: data model, API surface, business logic, business rules, how it works, architecture, integrations — whatever sections exist

## Step 3: Extract claims from the overview

Identify what the overview asserts:
- **What it is** — how does the overview define this entity/feature?
- **Scope** — does it say "camera X" when it could be "camera or project X"? Does it say "JPEG" when it could be "JPEG or MP4"?
- **Capabilities listed** — how many variants/modes/types does the overview mention?
- **Who interacts** — what actors/systems does the overview name?
- **Why it exists** — what problem does the overview say it solves?

## Step 4: Extract facts from the technical sections

Go through every section below the overview and collect:
- **All types/schemas/enums** — every variant, subtype, mode, or resource type defined in the data model
- **All API endpoints** — every route, method, and what it operates on
- **All business rules** — every constraint, permission check, feature flag, edge case
- **All integrations** — every external system, service, or repo mentioned
- **All references to other concepts/features** — every entity name that appears in the technical sections

## Step 5: Find mismatches

Compare overview claims against technical facts. Look for:

1. **Narrowing** — the overview describes a subset of what the entity actually does. Example: "embeddable camera viewer" when the data model shows camera, project, AND video wall resources.

2. **Omission** — the overview doesn't mention significant capabilities that the technical sections describe. Example: overview doesn't mention 360 widgets but the settings section defines `ThreeSixtyWidgetSettings`.

3. **Overclaiming** — the overview claims something the technical sections don't support.

4. **Framing bias** — the overview frames the entity through its most common use case rather than its actual scope. Example: describing a multi-protocol streaming system as "JPEG snapshot polling."

If no mismatches are found, the overview is accurate. Skip to Step 7.

## Step 6: Rewrite the overview

Rewrite the overview to accurately reflect the full scope described in the technical sections.

**Rules:**
- Keep the same approximate length. Don't inflate a 3-sentence overview into 10 sentences.
- Keep the same style and voice.
- Lead with what it IS (accurate scope), then why it exists, then how it fits into the system.
- Don't add implementation details that belong in the technical sections. The overview is a domain-level summary.
- Don't remove correct information — only fix what's wrong or missing.

Write the updated doc with the new overview replacing the old one. All other sections remain unchanged.

## Step 7: Check relates_to

Scan the technical sections for references to other concepts and features. Compare against the `relates_to` field in frontmatter.

- Check that every concept in `relates_to.concepts` has a corresponding file in `docs/domain/`
- Check that every feature in `relates_to.features` has a corresponding file in `docs/features/`
- If a concept/feature is prominently referenced in the technical sections but missing from `relates_to`, add it
- If a name in `relates_to` has no corresponding doc file, remove it

Update the frontmatter if changes are needed.

## Step 8: Mark as reviewed and report

Append the doc's path (relative to `docs/`, without `.md`) to `docs/.reviewed`. Create the file if it doesn't exist.

Report:

If changes were made:
```
✓ Reviewed: domain/widget
  Overview: FIXED — was narrowing to "camera viewer", now accurately describes all 5 widget types
  relates_to: added video-wall concept, removed stale feature link
  
Remaining unreviewed: 23
```

If no changes needed:
```
✓ Reviewed: domain/camera — no changes needed

Remaining unreviewed: 23
```

Then STOP.
