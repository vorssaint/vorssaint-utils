---
name: pr-health
description: Assess whether a pull request is current, mergeable, and safe to advance, then report surgical remediation steps.
---

# Pull request health

Use this skill when a pull request may be stale, conflicted, or affected by later changes.

## Procedure

1. Read the repository's pull-request template and contribution guide before drafting
   any PR text.
2. Fetch the PR metadata from GitHub: state, draft status, base and head refs,
   mergeability, merge state, review decision, checks, last update, and changed-file
   counts.
3. Compare the head with the current base branch. Record:
   - whether the base commit is an ancestor of the head;
   - ahead/behind counts and whether the histories diverged;
   - the merge base and the files that conflict in a clean merge or cherry-pick;
   - commits on the base branch that touched the PR's changed files.
4. Inspect the PR's commits and diff against its declared base. Separate the intended
   feature from unrelated historical changes caused by a stale or rewritten base.
5. Use the repository's documented validation commands. Run the smallest relevant
   checks when the branch can be built; otherwise state exactly why validation is
   blocked.
6. Recommend one disposition:
   - **Ready after refresh**: fast-forward or rebase is low-risk and checks can run.
   - **Port required**: the intended feature can be transplanted, but conflicts or
     changed contracts require manual review.
   - **Close and reopen**: the branch is too stale or its intent is superseded.
7. Do not force-push, rewrite history, close a PR, or resolve conflicts automatically
   unless the user explicitly authorizes that action.

## Report format

Start with a one-line verdict. Include a compact table with:

| Signal | Result |
| --- | --- |
| PR state | open/closed, draft status |
| Merge state | mergeable and merge state |
| Base freshness | ahead/behind, ancestry, merge base |
| Scope | intended files versus historical noise |
| Validation | commands run and results |
| Recommendation | refresh, manually port, or close/reopen |

Then list the smallest concrete next steps, naming conflicting files and any behavior
that must be rechecked. Distinguish facts from inferences and include dates for stale
metadata.
