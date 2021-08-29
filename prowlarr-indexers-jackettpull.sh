#!/bin/bash

## Script to keep Prowlarr/Indexers up to date with Jackett/Jackett
## Requirements
### Prowlarr/Indexers git repo exists
### Jackett/Jackett git repo exists
### Require
## Variables
prowlarr_git_path="/c/Development/Code/Prowlarr_Indexers/"
jackett_repo_name="z_Jackett/master"
jackett_pulls_branch="jackett-pulls"
prowlarr_commit_template=$(sed -n 1p .gitcommit_pulltemplate.txt)

## Switch to Prowlarr directory and fetch all
cd "$prowlarr_git_path" || exit
git fetch --all
## Config Git and Prevent Conflicts
git config commit.template .gitcommit_pulltemplate.txt
## Check if jackett-pulls exists
pulls_check=$(git ls-remote --heads origin "$jackett_pulls_branch")
if [ -z "$pulls_check" ]; then
    ## no existing branch found
    pulls_exists=false
    echo "origin/$jackett_pulls_branch does not exist"
    git checkout -b "$jackett_pulls_branch" - origin/master
    echo "origin/$jackett_pulls_branch created from master"
## create new branch from master
else
    ## existing branch found
    pulls_exists=true
    echo "origin/$jackett_pulls_branch does exist"
    #git checkout "$jackett_pulls_branch"
    echo "origin/$jackett_pulls_branch checked out from origin"
    existing_message=$(git log --format=%B -n1)
## pull down recently
fi

jackett_recent_commit=$(git rev-parse "$jackett_repo_name")
echo "most recent jackett commit is: $jackett_recent_commit"
recent_pulled_commit=$(git log -n 10 | grep "$prowlarr_commit_template" | awk 'NR==1{print $5}')
## check most recent 10 commits in case we have other commits
echo "most recent origin jackett pulled commit is: $recent_pulled_commit"

## Pull commits between our most recent pull and jackett's latest commit
commit_range=$(git log --reverse --pretty="%H" "$recent_pulled_commit".."$jackett_recent_commit")
## Cherry pick each commit and attempt to resolve common conflicts
for pick_commit in ${commit_range}; do
    git cherry-pick -n --rerere-autoupdate --allow-empty --keep-redundant-commits "$pick_commit"
    has_conflicts=$(git ls-files --unmerged)
    readme_conflicts=$(git diff --cached --name-only | grep "README.md")
    csharp_conflicts=$(git diff --cached --name-only | grep ".cs")
    yml_conflicts=$(git diff --cached --name-only | grep ".yml")
    if [[ -n $has_conflicts ]]; then
        ## Handle Common Conflicts
        if [[ -n $csharp_conflicts ]]; then
            git rm "*.cs"
        fi
        if [[ -n $readme_conflicts ]]; then
            git checkout --ours "README.md"
            git add "README.md"
        fi
        if [[ -n $yml_conflicts ]]; then
            git checkout --theirs "*.yml"
            git add "*.yml" ## Add any new yml definitions
        fi
    fi
done
echo "completed pulls"
echo "checking for backporting needed"
## Work on Newer Version Indexers and backport
v2_indexers=$(git diff --cached --name-only | grep "v2") ## get files to check for v2
v2_pattern="v2"
v1_pattern="v1"

back_port=$v2_indexers
if [[ -n $back_port ]]; then
    for indexer in ${back_port}; do
        v1_indexer=${indexer/$v2_pattern/$v1_pattern}
        echo "looking for v1 indexer of $v1_indexer"
        if [[ -f $v1_indexer ]]; then
            echo "found v1 indexer for $indexer"
            git difftool --no-index "$indexer" "$v1_indexer"
            git add "$v1_indexer"
        else
            echo "did not find v1 indexer for $indexer"
        fi
    done
fi
## Wait for user interaction to handle any conflicts and review
echo "After review; the script will commit the changes."
echo "Ensure no v1 indexers need deleting; ensure no selectors are in v1"
read -p "Press any key to continue or [Ctrl-C] to abort.  Waiting for human review..." -n1 -s
new_commit_msg="$prowlarr_commit_template $jackett_recent_commit"
if [ $pulls_exists ]; then
    ## If our branch existed, we squash and ammend
    git merge --squash
    git commit --amend -m "$new_commit_msg" -m "$existing_message"
    #disabled git push origin $jackett_pulls_branch --force
    echo "Commit Appended"
else
    ## new branches; new commit
    git commit -m "$new_commit_msg"
    #disabled git push origin $jackett_pulls_branch
    echo "New Commit made"
fi
