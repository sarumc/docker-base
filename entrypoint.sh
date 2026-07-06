#!/usr/bin/env bash
set -euo pipefail

PMMP_DIR="${PMMP_DIR:-/server}"
PLUGINS_DIR="${PMMP_DIR}/plugins"
VIRIONS_DIR="${PMMP_DIR}/virions"
ADDITIONAL_PLUGINS="${ADDITIONAL_PLUGINS:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# --- First-run: seed baked plugins into volume if plugins dir is empty/new ---
# Devirion.phar is our canary — if missing, volume needs seeding
if [ ! -f "${PLUGINS_DIR}/Devirion.phar" ]; then
    echo ":: First run — seeding baked plugins into volume..."
    if [ -d /baked-plugins ]; then
        cp -r /baked-plugins/* "${PLUGINS_DIR}/" 2>/dev/null || true
    fi
    if [ -d /baked-virions ]; then
        cp -r /baked-virions/* "${VIRIONS_DIR}/" 2>/dev/null || true
    fi
fi

PLUGINS_ADDED=0

# Normalize a GitHub reference (URL or owner/repo) to "owner/repo"
normalize_github_ref() {
    local ref="$1"
    ref="${ref#https://github.com/}"
    ref="${ref#http://github.com/}"
    ref="${ref#github.com/}"
    ref="${ref%.git}"
    ref="${ref%/}"
    echo "${ref}"
}

# Resolve a GitHub repo to its latest release asset URL (or empty if none)
resolve_github_release() {
    local repo="$1"
    curl -s ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
        "https://api.github.com/repos/${repo}/releases/latest" \
        | jq -r '.assets[0].browser_download_url // empty'
}

# Download a GitHub repo as zip archive (fallback when no release assets)
download_github_archive() {
    local repo="$1" dest_name="$2"
    local archive_url="https://github.com/${repo}/archive/refs/heads/main.zip"
    local tmpfile="/tmp/plugin-dl-$$"
    if [ -n "${GITHUB_TOKEN}" ]; then
        curl -fSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -o "${tmpfile}" "${archive_url}"
    else
        curl -fSL -o "${tmpfile}" "${archive_url}"
    fi
    local extract_dir="/tmp/plugin-extract-$$"
    mkdir -p "${extract_dir}"
    unzip -oq "${tmpfile}" -d "${extract_dir}"
    local subfolders=("${extract_dir}"/*/)
    if [ ${#subfolders[@]} -eq 1 ] && [ -d "${subfolders[0]}" ]; then
        mv "${subfolders[0]}" "${PLUGINS_DIR}/${dest_name}"
    fi
    rm -rf "${tmpfile}" "${extract_dir}"
}

download_plugin() {
    local src="$1"
    local name="${2:-}"
    echo ":: Installing plugin: ${src}"

    # 1) Direct .phar URL
    if [[ "${src}" == *.phar ]]; then
        [ -z "${name}" ] && name=$(basename "${src}" .phar)
        curl -fSL --progress-bar -o "${PLUGINS_DIR}/${name}.phar" "${src}"
        echo "   -> ${name}.phar"

    # 2) Archive URL (.zip / .tar.gz / .tgz)
    elif [[ "${src}" == *.zip ]] || [[ "${src}" == *.tar.gz ]] || [[ "${src}" == *.tgz ]]; then
        local tmpfile="/tmp/plugin-dl-$$"
        curl -fSL --progress-bar -o "${tmpfile}" "${src}"
        [ -z "${name}" ] && name=$(basename "${src}" | sed 's/\.[^.]*$//')
        local extract_dir="/tmp/plugin-extract-$$"
        mkdir -p "${extract_dir}"
        case "${src}" in
            *.tar.gz|*.tgz) tar xzf "${tmpfile}" -C "${extract_dir}" ;;
            *.zip)          unzip -oq "${tmpfile}" -d "${extract_dir}" ;;
        esac
        local subfolders=("${extract_dir}"/*/)
        if [ ${#subfolders[@]} -eq 1 ] && [ -d "${subfolders[0]}" ]; then
            mv "${subfolders[0]}" "${PLUGINS_DIR}/${name}"
        else
            mkdir -p "${PLUGINS_DIR}/${name}"
            mv "${extract_dir}"/* "${PLUGINS_DIR}/${name}/"
        fi
        rm -rf "${tmpfile}" "${extract_dir}"
        echo "   -> plugins/${name}/ (folder)"

    # 3) GitHub reference: github.com URL OR owner/repo shorthand
    elif [[ "${src}" == github.com/* ]] || [[ "${src}" == http://github.com/* ]] || [[ "${src}" == https://github.com/* ]] \
      || ( [[ "${src}" == */* ]] && [[ "${src}" != */*/* ]] && [[ "${src}" != http://* ]] && [[ "${src}" != https://* ]] ); then
        local repo
        repo=$(normalize_github_ref "${src}")
        [ -z "${name}" ] && name=$(basename "${repo}")
        echo "   -> Fetching latest release from ${repo}..."

        local asset_url
        asset_url=$(resolve_github_release "${repo}")
        if [ -n "${asset_url}" ]; then
            # Recurse with the resolved asset URL
            download_plugin "${asset_url}" "${name}"
            return
        fi
        # Fallback: download repo as zip
        echo "   !! No release assets for ${repo}, falling back to archive download..."
        download_github_archive "${repo}" "${name}"
        echo "   -> plugins/${name}/"

    # 4) Generic URL (non-GitHub)
    elif [[ "${src}" == http://* ]] || [[ "${src}" == https://* ]]; then
        [ -z "${name}" ] && name=$(basename "${src}" | sed 's/\.[^.]*$//')
        local tmpfile="/tmp/plugin-dl-$$"
        curl -fSL --progress-bar -o "${tmpfile}" "${src}"

        if file "${tmpfile}" 2>/dev/null | grep -qi 'phar'; then
            cp "${tmpfile}" "${PLUGINS_DIR}/${name}.phar"
            echo "   -> ${name}.phar"
        else
            local extract_dir="/tmp/plugin-extract-$$"
            mkdir -p "${extract_dir}"
            unzip -oq "${tmpfile}" -d "${extract_dir}" 2>/dev/null \
                || tar xzf "${tmpfile}" -C "${extract_dir}" 2>/dev/null \
                || { echo "   !! Could not extract ${src}"; rm -rf "${tmpfile}" "${extract_dir}"; return 1; }
            local subfolders=("${extract_dir}"/*/)
            if [ ${#subfolders[@]} -eq 1 ] && [ -d "${subfolders[0]}" ]; then
                mv "${subfolders[0]}" "${PLUGINS_DIR}/${name}"
            else
                mkdir -p "${PLUGINS_DIR}/${name}"
                mv "${extract_dir}"/* "${PLUGINS_DIR}/${name}/"
            fi
            rm -rf "${extract_dir}"
            echo "   -> plugins/${name}/ (folder)"
        fi
        rm -f "${tmpfile}"

    else
        echo "   !! Unrecognized plugin source: ${src}"
        echo "   Supported: .phar URL, archive URL, GitHub repo (owner/repo), generic URL"
        return 1
    fi

    PLUGINS_ADDED=$((PLUGINS_ADDED + 1))
}

# --- Parse CLI args ---
PMMP_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --add-plugin)
            download_plugin "$2"
            shift 2 || true
            ;;
        --add-plugin-named)
            download_plugin "$2" "$3"
            shift 3 || true
            ;;
        *)
            PMMP_ARGS+=("$1")
            shift || true
            ;;
    esac
done

# --- Load plugins from env var (comma-separated URLs/repos) ---
if [ -n "${ADDITIONAL_PLUGINS}" ]; then
    echo ":: Loading plugins from ADDITIONAL_PLUGINS env..."
    IFS=',' read -ra PLUGIN_LIST <<< "${ADDITIONAL_PLUGINS}"
    for plugin_src in "${PLUGIN_LIST[@]}"; do
        plugin_src=$(echo "${plugin_src}" | xargs)
        [ -n "${plugin_src}" ] && download_plugin "${plugin_src}"
    done
fi

if [ ${PLUGINS_ADDED} -gt 0 ]; then
    echo ":: ${PLUGINS_ADDED} plugin(s) added at runtime."
fi

echo ":: Starting PocketMine-MP..."
cd "${PMMP_DIR}"

exec php PocketMine-MP.phar "${PMMP_ARGS[@]}"
