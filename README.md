# Monorepo Iceberg

This repository contains the following submodules:
- **Iceberg**: `iceberg/` (Upstream: `apache/iceberg`)
- **OpenHouse**: `openhouse/` (Upstream: `cbb330/openhouse`)

## Workflow

To simplify working with submodules, use the provided `git-sync.sh` script.

### How to make changes

1. Make your code changes in any directory (submodule or root).
2. Run the sync script:

```bash
./git-sync.sh "Your commit message"
```

### What the script does

1. Iterates through each submodule.
2. If there are changes, it commits them to the currently checked-out branch of the submodule.
3. Pushes the submodule changes to its upstream remote.
4. Updates the main repository with the new submodule references.
5. Commits and pushes the main repository.

### Important Notes

- **Branches**: Ensure your submodules are checked out to a branch (e.g., `main` or `master`) and not in a "detached HEAD" state if you intend to push changes.
- **Permissions**: You need write access to the upstream repositories to push changes.

