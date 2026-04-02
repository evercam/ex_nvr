---
description: Read REPO_CONTEXT.md, present discovered concepts and features for approval, then create stub doc files with frontmatter
---

You are scaffolding documentation files for this repository. This creates the empty structure that `/doc-populate` will fill with content.

The optional argument is: $ARGUMENTS

- No argument: scaffold ALL suggested concepts and features from REPO_CONTEXT.md
- A name (e.g., `camera`): scaffold only that concept or feature
- `concepts` or `features`: scaffold only that category

## Step 1: Read REPO_CONTEXT.md

Read `docs/REPO_CONTEXT.md`. If it doesn't exist, tell the user to run `/repo-context` first and stop.

Extract:
- `repo` and `stack` from frontmatter
- Discovery paths table
- Suggested concepts and features tables
- Doc section templates (concept and feature)

## Step 2: Present candidates for approval

List all suggested concepts and features as a numbered checklist:

```
Concepts:
 [1] camera — evercam_api/lib/evercam_media/cameras/, controllers/camera_controller.ex
 [2] project — evercam_api/lib/evercam_media/projects/, controllers/project_controller.ex
 [3] archive — evercam_api/lib/evercam_media/archives/
 ...

Features:
 [1] camera-management — camera_controller.ex (CRUD, status, config)
 [2] snapshot-capture — snapshot_controller.ex
 ...
```

Ask the user to:
- Confirm the list (press enter to accept all)
- Remove items by number (e.g., "remove concepts 5, 7")
- Add new items (e.g., "add concept: sim-card")
- Rename items (e.g., "rename feature 3 to cloud-recording")

If the argument specified a single name, skip the checklist and just scaffold that one.

## Step 3: Discover watched paths for each item

For each approved concept and feature, find the files it covers:

1. Generate name variants from the kebab-case name:
   - kebab-case: `video-wall`
   - camelCase: `videoWall`
   - PascalCase: `VideoWall`
   - snake_case: `video_wall`
   - plural forms of each
   - For Elixir: also `VideoWall` as a module name segment

2. Search the discovery paths from REPO_CONTEXT.md:
   - Use Glob for filename/directory matches against each discovery path category
   - Use Grep for content matches (module definitions, function names, type references)
   - For concepts: prioritise schema/model/type files, then work outward to controllers and services
   - For features: prioritise controller/route/page files, then work inward to services and models

3. Filter results: only include files where this entity is a primary concern, not just a passing import or reference.

Present the discovered paths grouped by category for each item:

```
camera:
  schemas: evercam_shared/lib/evercam_shared/cameras/camera.ex
  contexts: evercam_api/lib/evercam_media/cameras.ex
  controllers: evercam_api/lib/evercam_media_web/controllers/camera_controller.ex
  routers: evercam_api/lib/evercam_media_web/routers/camera_router.ex
  views: evercam_api/lib/evercam_media_web/views/camera_view.ex

Accept these paths? (y/n, or add/remove specific paths)
```

Let the user adjust paths per item. If there are many items, batch the confirmation (show all, let user edit specific ones).

## Step 4: Create stub files

Get the current HEAD commit hash via `git rev-parse HEAD`.

Create `docs/domain/` and `docs/features/` directories if they don't exist.

For each approved concept, write `docs/domain/<name>.md`:

```markdown
---
name: <kebab-case-name>
type: concept
repo: <repo from REPO_CONTEXT.md>
stack: <stack from REPO_CONTEXT.md>
last_updated_commit: <HEAD hash>
paths:
  - <glob pattern>
  - <glob pattern>
relates_to:
  concepts: []
  features: []
---

<!-- stub: awaiting /doc-populate -->
```

For each approved feature, write `docs/features/<name>.md`:

```markdown
---
name: <kebab-case-name>
type: feature
repo: <repo from REPO_CONTEXT.md>
stack: <stack from REPO_CONTEXT.md>
last_updated_commit: <HEAD hash>
paths:
  - <glob pattern>
  - <glob pattern>
relates_to:
  concepts: []
  features: []
---

<!-- stub: awaiting /doc-populate -->
```

Convert confirmed paths to glob patterns:
- Individual files stay as-is: `lib/my_app/cameras/camera.ex`
- Directories become globs: `lib/my_app_web/controllers/camera/**`

## Step 5: Report

List all created stubs:

```
Created 12 concept stubs:
  docs/domain/camera.md (5 watched paths)
  docs/domain/project.md (3 watched paths)
  ...

Created 8 feature stubs:
  docs/features/camera-management.md (4 watched paths)
  docs/features/snapshot-capture.md (3 watched paths)
  ...

Run /doc-populate to generate content for these docs.
```
