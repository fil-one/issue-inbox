# linear-issue-test — Issue Inbox

This repo acts as a GitHub/Linear issue inbox. Issues filed here are
automatically routed to the appropriate repo based on their label, and
two-way synced with Linear via the native GitHub Issues Sync integration.

## How it works

1. An issue is created here (or arrives via Linear sync).
2. A routing label is applied — either at creation or afterwards.
3. A GitHub Action transfers the issue to the target repo.
4. A stub comment is left on the original issue with a redirect note.
5. Linear's sync follows the transferred issue to its new repo (one-way).

## Routing labels

Labels follow the format `🐙 repo-name`, where `repo-name` is the name of a repo
in the org. These labels are kept in sync automatically (see below). In Linear,
they live under the `repo` label group.

## GitHub Actions

### `sync-linear-labels.yml`

Runs nightly (and on demand via workflow_dispatch). For every non-archived repo
in the org (excluding this one), it ensures a corresponding label exists in
Linear under the `repo` group, and a matching `🐙 repo-name` label exists in
this repo.

**Secrets required:**

| Secret | What it is |
|--------|-----------|
| `LINEAR_API_KEY` | A Linear personal API key with Read and Write scopes (Settings → Security & Access → Personal API Keys) |
| `SYNC_PAT` | A GitHub PAT with `read:org` scope, to list org repos |

### `transfer-issue.yml`

Triggers on `issues: [labeled, opened]`. When an issue has a `🐙 repo-name`
label, it transfers the issue to that repo and leaves a redirect comment.

**Secrets required:**

| Secret | What it is |
|--------|-----------|
| `TRANSFER_PAT` | A GitHub PAT with `repo` scope (the default `GITHUB_TOKEN` cannot transfer issues across repos) |

> **Note:** Both workflows use separate PATs so you can scope permissions
> independently. You can use the same PAT for both if you prefer.

## Setup checklist

- [ ] Create the repo and enable Issues
- [ ] In Linear: Settings → Integrations → GitHub → GitHub Issues → **+**,
      select this repo, choose **Two-way** sync, link to your inbox team
- [ ] Create a Linear personal API key and add it as `LINEAR_API_KEY` secret
- [ ] Create a GitHub PAT (`repo` + `read:org`) and add as `SYNC_PAT`
- [ ] Create a GitHub PAT (`repo`) and add as `TRANSFER_PAT`
- [ ] Add both workflow files to `.github/workflows/`
- [ ] Run **Sync repo labels to Linear** manually once to bootstrap labels
- [ ] For each other repo you want as a target: in Linear, add a one-way
      GitHub Issues Sync connection (Settings → Integrations → GitHub →
      GitHub Issues → **+**, choose **One-way**)

## Caveats

- **Label must exist in the target repo** for it to survive the transfer.
  GitHub drops labels that don't exist at the destination. The routing label
  itself (`🐙 repo-name`) only needs to exist in this inbox repo — Linear
  creates it here automatically via the GitHub Issues Sync.
- **Only newly created issues sync** via Linear's GitHub Issues Sync.
  Existing issues must be imported manually if needed.
