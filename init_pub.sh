#!/bin/bash

# Create a new orphand branch (no commit history) named master
git checkout --orphan master

# Unstage all files
git rm -rf .

# Grab one file from the develop branch so we can make a commit
git checkout develop README.md

# Add and commit that file
git add .
git commit -m "INIT: initial commit on master branch"

# Push to remote master branch
git push origin master

# Return to develop branch
git checkout develop

# Remove the public folder to make room for the gh-pages subtree
rm -rf public

# Add the gh-pages branch of the repository. It will look like a folder named public
git subtree add --prefix=public git@github.com:trickbooter/trickbooter.github.io.git master --squash

# Pull down the file we just committed. This helps avoid merge conflicts
git -C ./public pull git@github.com:trickbooter/trickbooter.github.io.git master --allow-unrelated-histoies -m "Merge master subtree"

# Run hugo. Generated site will be placed in public directory (or omit -t ThemeName if you're not using a theme)
hugo

# Add everything
git add -A

# Commit and push to master
git commit -m "Updating site" && git push origin develop

# Push the public subtree to the gh-pages branch
git subtree push --prefix=public git@github.com:trickbooter/trickbooter.github.io.git master
