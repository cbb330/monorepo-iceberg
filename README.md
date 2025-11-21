# Monorepo Iceberg

This repository contains the following submodules:
- **Iceberg**: `iceberg/` (Fork: `cbb330/iceberg`)
- **OpenHouse**: `openhouse/` (Fork: `cbb330/openhouse`)

## Workflow

### 1. Setup (One-time)
Ensure you have the repository and submodules initialized:
```bash
git clone --recursive https://github.com/cbb330/monorepo-iceberg.git
cd monorepo-iceberg
```

### 2. Development Cycle
The normal workflow is designed to be simple and automated using `git-sync.sh`.

#### Step A: Make Changes
Edit files in `iceberg/`, `openhouse/`, or the root directory as needed. You don't need to worry about manually committing in each submodule.

#### Step B: Sync & Push
Instead of standard git commands, run:
```bash
./git-sync.sh "Description of your changes"
```
This script will automatically:
1. Detect changes in any submodule.
2. Commit those changes to the **current branch** in that submodule.
3. Push submodule changes to their upstream remote.
4. Update the monorepo pointers.
5. Commit and push the monorepo.

### 3. Working with Branches
**Crucial:** Before making changes, ensure your submodules are on the correct branches.
- **Check status:**
  ```bash
  git submodule foreach 'git branch --show-current'
  ```
- **Switch branches:**
  ```bash
  cd iceberg && git checkout test-harness
  cd ../openhouse && git checkout main
  ```

### Troubleshooting
- **Detached HEAD**: If `git-sync.sh` fails saying a submodule is in "detached HEAD", it means you aren't on a branch. Fix it by checking out a branch:
  ```bash
  cd iceberg
  git checkout -b my-feature-branch
  ```
