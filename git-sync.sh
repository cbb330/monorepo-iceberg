#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

MSG="$1"
if [ -z "$MSG" ]; then
    MSG="Update from monorepo"
fi

echo -e "${GREEN}Starting sync process...${NC}"

# Function to handle submodule
sync_submodule() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        return
    fi

    echo -e "\n${GREEN}>>> Checking submodule: $dir${NC}"
    cd "$dir" || exit

    # Check for uncommitted changes
    if [[ -n $(git status --porcelain) ]]; then
        echo -e "${YELLOW}Uncommitted changes found in $dir.${NC}"
        
        # Check if on a branch
        BRANCH=$(git rev-parse --abbrev-ref HEAD)
        if [[ "$BRANCH" == "HEAD" ]]; then
            echo -e "${RED}Error: $dir is in 'detached HEAD' state.${NC}"
            echo "You must check out a branch (e.g., 'main') in the submodule before committing."
            echo "Skipping push for $dir."
        else
            echo "Adding and committing changes to branch '$BRANCH'..."
            git add .
            git commit -m "$MSG"
            echo "Pushing to upstream..."
            git push origin "$BRANCH"
        fi
    elif [[ -n $(git log --branches --not --remotes) ]]; then
         # Check for unpushed commits
        BRANCH=$(git rev-parse --abbrev-ref HEAD)
        if [[ "$BRANCH" != "HEAD" ]]; then
            echo -e "${YELLOW}Unpushed commits found in $dir. Pushing...${NC}"
            git push origin "$BRANCH"
        fi
    else
        echo "No changes to sync in $dir."
    fi

    cd ..
}

# Sync submodules
# Parse .gitmodules to find paths
grep "path =" .gitmodules | awk '{print $3}' | while read -r submodule_path; do
    sync_submodule "$submodule_path"
done

echo -e "\n${GREEN}>>> Updating main repository...${NC}"

# Add updated submodule references
git add .

if [[ -n $(git status --porcelain) ]]; then
    echo "Committing changes to monorepo..."
    git commit -m "$MSG"
    echo "Pushing monorepo..."
    git push origin main
else
    echo "No changes in main repository."
    # Check if main has unpushed commits even if no new changes
    if [[ -n $(git log origin/main..HEAD 2>/dev/null) ]]; then
        echo "Pushing unpushed commits..."
        git push origin main
    fi
fi

echo -e "\n${GREEN}Sync complete!${NC}"

