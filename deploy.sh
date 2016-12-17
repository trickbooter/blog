#!/bin/bash

echo -e "\033[0;32mCommitting changes...\033[0m"

# Build the project.
hugo

# Add changes to git.
git add -A

# Commit changes.
msg="rebuilding site `date`"
if [ $# -eq 1 ]
  then msg="$1"
fi
git commit -m "$msg"
git push origin develop

# Push source and build repos.
echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"
cp CNAME public/
git -C public add --all && git -C public commit -m "$msg" && git -C push
