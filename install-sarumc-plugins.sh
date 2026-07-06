#!/usr/bin/env bash
# Install SaruMC plugins from GitHub releases.
# Requires GITHUB_TOKEN env var for private repo access.
set -euo pipefail

PLUGINS_DIR="${1:-/baked-plugins}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPOS=("SaruMC/core:SaruMC-core" "SaruMC/horus:SaruMC-horus")

if [ -z "${GITHUB_TOKEN}" ]; then
    echo "WARN: No GITHUB_TOKEN set. Skipping SaruMC private plugins."
    echo "      They can be injected at runtime via ADDITIONAL_PLUGINS env."
    exit 0
fi

AUTH="Authorization: Bearer ${GITHUB_TOKEN}"
mkdir -p "${PLUGINS_DIR}"

for entry in "${REPOS[@]}"; do
    repo="${entry%%:*}"
    plugin_name="${entry##*:}"
    echo ":: Downloading ${repo} release..."

    ASSET_URL=$(curl -s -H "${AUTH}" \
        "https://api.github.com/repos/${repo}/releases/latest" \
        | jq -r '[.assets[] | select(.name | test("\\.(phar|zip|tar\\.gz|tgz)$"; "i"))][0].browser_download_url // empty')

    if [ -z "${ASSET_URL}" ]; then
        echo "   !! No release assets for ${repo}, skipping."
        continue
    fi

    echo "   -> ${ASSET_URL}"
    DL_FILE="/tmp/plugin-dl-$$"
    curl -fSL -H "${AUTH}" -o "${DL_FILE}" "${ASSET_URL}"

    case "${ASSET_URL}" in
        *.phar)
            cp "${DL_FILE}" "${PLUGINS_DIR}/${plugin_name}.phar"
            echo "   -> plugins/${plugin_name}.phar"
            ;;
        *.zip)
            EXTRACT_DIR="/tmp/plugin-extract-$$"
            mkdir -p "${EXTRACT_DIR}"
            unzip -oq "${DL_FILE}" -d "${EXTRACT_DIR}"
            # If archive wraps in a single folder, use its contents as the plugin
            SUBFOLDERS=("${EXTRACT_DIR}"/*/)
            if [ ${#SUBFOLDERS[@]} -eq 1 ] && [ -d "${SUBFOLDERS[0]}" ]; then
                mv "${SUBFOLDERS[0]}" "${PLUGINS_DIR}/${plugin_name}"
            else
                mkdir -p "${PLUGINS_DIR}/${plugin_name}"
                mv "${EXTRACT_DIR}"/* "${PLUGINS_DIR}/${plugin_name}/"
            fi
            rm -rf "${EXTRACT_DIR}"
            echo "   -> plugins/${plugin_name}/ (folder)"
            ;;
        *.tar.gz|*.tgz)
            EXTRACT_DIR="/tmp/plugin-extract-$$"
            mkdir -p "${EXTRACT_DIR}"
            tar xzf "${DL_FILE}" -C "${EXTRACT_DIR}"
            SUBFOLDERS=("${EXTRACT_DIR}"/*/)
            if [ ${#SUBFOLDERS[@]} -eq 1 ] && [ -d "${SUBFOLDERS[0]}" ]; then
                mv "${SUBFOLDERS[0]}" "${PLUGINS_DIR}/${plugin_name}"
            else
                mkdir -p "${PLUGINS_DIR}/${plugin_name}"
                mv "${EXTRACT_DIR}"/* "${PLUGINS_DIR}/${plugin_name}/"
            fi
            rm -rf "${EXTRACT_DIR}"
            echo "   -> plugins/${plugin_name}/ (folder)"
            ;;
        *)
            echo "   !! Unknown format, saving as .phar"
            cp "${DL_FILE}" "${PLUGINS_DIR}/${plugin_name}.phar"
            ;;
    esac
    rm -f "${DL_FILE}"
done

echo ":: SaruMC plugins installed."
