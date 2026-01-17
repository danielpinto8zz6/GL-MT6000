#!/bin/bash

# --- Configuration ---
REMOTE_REPOSITORY="pesa1234/openwrt"
CONFIG_FILE="mt6000.config"
LOCAL_BUILDER_REPO_PATH="$(pwd)" # Assumes you're inside the folder where the config and files are
MY_GITHUB_REPO="danielpinto8zz6/GL-MT6000" # Change to your repo if you want to use the 'gh' command

# --- 2. Check Commits (check_commits logic) ---
echo "--- Checking for new remote version ---"
remote_branch=$(git ls-remote https://github.com/${REMOTE_REPOSITORY}.git "refs/heads/next-*" | sed -e 's|\(.*heads/\)||' | grep -viE 'test|beta' | sort -V | tail -n1)

if [ -z "$remote_branch" ]; then
    echo "Error: Could not find remote branch."
    exit 1
fi

latest_commit_sha=$(curl -s "https://api.github.com/repos/${REMOTE_REPOSITORY}/commits/${remote_branch}" | grep -m 1 '"sha":' | cut -d'"' -f4)
release_prefix="${remote_branch%.rss*}"

echo "Branch: $remote_branch"
echo "Commit: $latest_commit_sha"

# --- 3. Checkout Code ---
if [ -d "openwrt_src" ]; then
    echo "--- openwrt_src folder already exists. Updating... ---"
    cd openwrt_src
    git remote set-url origin https://github.com/${REMOTE_REPOSITORY}.git
    git fetch origin
    git checkout $remote_branch
    git pull origin $remote_branch
else
    echo "--- Cloning OpenWrt repository ---"
    git clone -b "$remote_branch" "https://github.com/${REMOTE_REPOSITORY}.git" openwrt_src
    cd openwrt_src
fi

# --- 4. Feeds ---
echo "--- Atualizando feeds ---"
./scripts/feeds update -a
./scripts/feeds install -a
./scripts/feeds install -a

# --- 5. Custom Configuration and Files ---
echo "--- Applying custom configurations ---"
# Assumes the 'files' folder and the '.config' file are in the folder where you ran the script
if [ -d "../files" ]; then
    cp -rv ../files ./
    # Adjust the upgrade script if needed
    [ -f "./files/usr/bin/upgrade_custom_openwrt" ] && \
    sed -i "s|XXXXXX/XXXXXX|${MY_GITHUB_REPO}|" ./files/usr/bin/upgrade_custom_openwrt && \
    chmod 755 ./files/usr/bin/upgrade_custom_openwrt
fi

if [ -f "../$CONFIG_FILE" ]; then
    cp -v "../$CONFIG_FILE" .config
else
    echo "Warning: $CONFIG_FILE not found in root folder!"
fi

make defconfig

n_procs=$(nproc)

# --- 6. Build ---
echo "--- Starting build (this can take hours) ---"
n_procs=$(nproc)

make download -j$n_procs || make download -j1 V=s

# First build attempt
if ! make -j$n_procs; then
    echo "Build error. Trying again with V=s (single thread)..."
    make -j1 V=s
fi

# --- 7. Organize Artifacts ---
echo "--- Organizing final files ---"
mkdir -p ../firmware_output
find ./bin -type f \( -iname 'openwrt-*-sysupgrade.bin' -or -iname 'config.buildinfo' \) -exec cp -v {} ../firmware_output/ \;
cp .config ../firmware_output/full.config

cd ../firmware_output
find -iname 'openwrt-*-sysupgrade.bin' -exec sh -c "sha256sum {} > sha256sums" \;

echo "--- DONE ---"
echo "Your firmware is at: $(pwd)"