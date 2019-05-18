#!/bin/bash

# This script can build a release branch, or update an existing release branch.
# It doesn't care which branch you're currently standing on.
#
# Building a new set of release branches: "new" | "-n"
# It takes a parameter "new", which should only be used when preparing a new major release (x.x), not a point release.
#
# The "new" parameter will request a version number. It should be the version format "x.x" (example 4.9)
# It will then create a new (unbuilt) branch with the specific naming convention of "release-branch-x.x", and push it to the repo.
# It will also create another (built) branch with the specific naming convention of "release-branch-x.x-built",
#   push it to the repo, and build a production version to it.
#
# Updating an existing built branch: "update" | "-u"
# The "update" parameter will request an existing branch name to build to.

# Exit the build in scary red text if error
function exit_build {
    echo -e "${RED}Something went wrong and the build has stopped.  See error above for more details."
    exit 1
}
trap 'exit_build' ERR

# Instructions
function usage {
    echo "usage: $0 [-n new] [-u update <branchname>]"
    echo "  -n      Create new release branches"
    echo "  -u      Update existing release built branch"
    echo "          Can take an extra param that refers to an existing branch."
    echo "          Example: $0 -u master-stable"
    echo "  -h      help"
    exit 1
}

# This function will create a new set of release branches.
# The branch format will be release-branch-x.x
# These branches will be created off of master
function create_new_release_branch {

    # Prompt for version number.
    read -p "What version are you releasing? Please write in x.x syntax. Example: 4.9 - " version

    # Declare the new branch names.
    NEW_RELEASE_BRANCH="release-branch-$version"

    # Check if branch already exists, if not, create new branch named "release-branch-x.x"
    if [[ -n $( git branch -r | grep "$NEW_RELEASE_BRANCH" ) ]]; then
        echo "$NEW_RELEASE_BRANCH already exists.  Exiting..."
        exit 1
    else
        echo ""
        echo "Creating new unbuilt branch $NEW_RELEASE_BRANCH from current master branch..."
        echo ""
        # reset --hard to remote master in case they have local commits in their repo
        git checkout master && git pull && git reset --hard origin/master

        # Create new branch, push to repo
        git checkout -b $NEW_RELEASE_BRANCH

        git push -u origin $NEW_RELEASE_BRANCH
        echo ""
        echo "$NEW_RELEASE_BRANCH created."
        echo ""

        exit 1
    fi
}

function update_release_branch {
    # Current directory and current branch vars
    DIR=$(dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" )
    CURRENT_BRANCH=$( git branch | grep -e "^*" | cut -d' ' -f 2 )

    TMP_REMOTE_BUILT_VERSION="/tmp/jetpack"
    TMP_LOCAL_BUILT_VERSION="/tmp/jetpack2"

    # Make sure we don't have uncommitted changes.
    if [[ -n $( git status -s --porcelain ) ]]; then
        echo "Uncommitted changes found."
        echo "asdfPlease deal with them and try again clean."
        exit 1
    fi

    # Cast the branch name that we'll be building to a single var.
    if [[ -n $NEW_RELEASE_BRANCH ]]; then
        BUILD_TARGET=$NEW_RELEASE_BRANCH
    elif [[ -n $UPDATE_RELEASE_BRANCH ]]; then
        BUILD_TARGET=$UPDATE_RELEASE_BRANCH
    else
        echo ""
        echo "No target branch specified.  How did you make it this far?"
        exit 1
    fi

    ### This bit is the engine that will build a branch and push to another one ####

    # Make sure we're trying to deploy something that exists.
    if [[ -z $( git branch -r | grep "$BUILD_TARGET" ) ]]; then
        echo "Branch $BUILD_TARGET not found in git repository."
        echo ""
        exit 1
    fi

    read -p "You are about to update the $BUILD_TARGET branch from the $CURRENT_BRANCH branch. Are you sure? [y/N]" -n 1 -r
    if [[ $REPLY != "y" && $REPLY != "Y" ]]; then
        exit 1
    fi
    echo ""

    # Prep a home to drop our new files in. Just make it in /tmp so we can start fresh each time.
    rm -rf $TMP_REMOTE_BUILT_VERSION
    rm -rf $TMP_LOCAL_BUILT_VERSION

    echo "Rsync'ing everything over from Git except for .git and npm stuffs."
    rsync -r --exclude='*.git*' --exclude=node_modules $DIR/* $TMP_LOCAL_BUILT_VERSION
    echo "Done!"

    echo "Pulling latest from $BUILD_TARGET branch"
    CLONE_URL="$(git config --get remote.origin.url)"
    git clone --depth 1 -b $BUILD_TARGET --single-branch $CLONE_URL $TMP_REMOTE_BUILT_VERSION
    echo "Done!"

    echo "Rsync'ing everything over remote version"
    rsync -r --delete $TMP_LOCAL_BUILT_VERSION/* $TMP_REMOTE_BUILT_VERSION
    echo "Done!"

    cd $TMP_REMOTE_BUILT_VERSION

    echo "Finally, Committing and Pushing"
    git add .
    git commit -am 'New build'
    git push origin $BUILD_TARGET
    echo "Done! Branch $BUILD_TARGET has been updated."

    echo "Cleaning up the mess"
    cd $DIR
    rm -rf $TMP_REMOTE_BUILT_VERSION
    rm -rf $TMP_LOCAL_BUILT_VERSION
    echo "All clean!"
}

# Script parameter, what do you want to do?
# Expected to be "-n", "new", "-u", or "update"
COMMAND=$1

# Check the command
if [[ 'new' == $COMMAND || '-n' == $COMMAND ]]; then
    create_new_release_branch
elif [[ 'update' = $COMMAND || '-u' = $COMMAND ]]; then
    # It's possible they passed the branch name directly to the script
    if [[ -z $2 ]]; then
        read -p "What release branch are you updating? (enter just version number i.e. X.X): " version
        UPDATE_RELEASE_BRANCH="release-branch-$version"
    else
        UPDATE_RELEASE_BRANCH=$2
    fi

    update_release_branch
else
    usage
fi

