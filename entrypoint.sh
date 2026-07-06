#!/usr/bin/env bash
set -euo pipefail

PLUGINS_DIR="/plugins"
VIRIONS_DIR="/opt/pocketmine/virions"
ADDITIONAL_PLUGINS="${ADDITIONAL_PLUGINS:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# --- First-run: seed baked plugins into /plugins volume ---
if [ ! -f "${PLUGINS_DIR}/Devirion.phar" ]; then
    echo ":: First run — seeding baked plugins into volume..."
    if [ -d /baked-plugins ] && [ "$(ls -A /baked-plugins 2>/dev/null)" ]; then
        cp -r /baked-plugins/* "${PLUGINS_DIR}/"
    fi
    if [ -d /baked-virions ] && [ "$(ls -A /baked-virions 2>/dev/null)" ]; then
        mkdir -p "${VIRIONS_DIR}"
        cp -r /baked-virions/* "${VIRIONS_DIR}/"
    fi
fi

# --- Runtime plugin helpers ---
PLUGINS_ADDED=0

normalize_github_ref() {
    local ref="$1"
    ref="${ref#https://github.com/}"
    ref="${ref#http://github.com/}"
    ref="${ref#github.com/}"
    ref="${ref%.git}"
    ref="${ref%/}"
    echo "${ref}"
}

# Download a GitHub release asset via API (handles private repos).
# Returns: asset_name|temp_file_path, or empty on failure.
download_github_asset() {
    local repo="$1"
    local auth_header=""
    [ -n "${GITHUB_TOKEN}" ] && auth_header="-H \"Authorization: Bearer ${GITHUB_TOKEN}\""

    local release_json
    release_json=$(curl -s ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
        "https://api.github.com/repos/${repo}/releases/latest")

    # Guard against null/empty responses (private repo, no access, etc.)
    if [ -z "${release_json}" ] || [ "$(echo "${release_json}" | jq -r 'type')" != "object" ]; then
        echo ""
        return
    fi

    local asset_info
    asset_info=$(echo "${release_json}" | jq -r \
        '[.assets[]? | select(.name | test("\\.(phar|zip|tar\\.gz|tgz)$"; "i"))][0] | "\(.name)|\(.url)"')
    local asset_name="${asset_info%%|*}"
    local asset_api_url="${asset_info##*|}"

    if [ -z "${asset_api_url}" ] || [ "${asset_api_url}" = "null" ]; then
        echo ""
        return
    fi

    local tmpfile="/tmp/plugin-dl-$$"
    curl -fSL ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
        -H "Accept: application/octet-stream" -o "${tmpfile}" "${asset_api_url}" || {
        rm -f "${tmpfile}"
        echo ""
        return
    }
    echo "${asset_name}|${tmpfile}"
}

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

    # 3) GitHub reference: URL or owner/repo shorthand
    elif [[ "${src}" == github.com/* ]] || [[ "${src}" == http://github.com/* ]] || [[ "${src}" == https://github.com/* ]] \
      || ( [[ "${src}" == */* ]] && [[ "${src}" != */*/* ]] && [[ "${src}" != http://* ]] && [[ "${src}" != https://* ]] ); then
        local repo
        repo=$(normalize_github_ref "${src}")
        [ -z "${name}" ] && name=$(basename "${repo}")
        echo "   -> Fetching latest release from ${repo}..."

        local result
        result=$(download_github_asset "${repo}")
        if [ -n "${result}" ]; then
            local asset_name="${result%%|*}"
            local dl_file="${result##*|}"
            # Place based on extension
            case "${asset_name}" in
                *.phar)
                    cp "${dl_file}" "${PLUGINS_DIR}/${name}.phar"
                    echo "   -> ${name}.phar"
                    ;;
                *.zip|*.tar.gz|*.tgz)
                    local extract_dir="/tmp/plugin-extract-$$"
                    mkdir -p "${extract_dir}"
                    if [[ "${asset_name}" == *.tar.gz ]] || [[ "${asset_name}" == *.tgz ]]; then
                        tar xzf "${dl_file}" -C "${extract_dir}"
                    else
                        unzip -oq "${dl_file}" -d "${extract_dir}"
                    fi
                    local subfolders=("${extract_dir}"/*/)
                    if [ ${#subfolders[@]} -eq 1 ] && [ -d "${subfolders[0]}" ]; then
                        mv "${subfolders[0]}" "${PLUGINS_DIR}/${name}"
                    else
                        mkdir -p "${PLUGINS_DIR}/${name}"
                        mv "${extract_dir}"/* "${PLUGINS_DIR}/${name}/"
                    fi
                    rm -rf "${extract_dir}"
                    echo "   -> plugins/${name}/ (folder)"
                    ;;
                *)
                    cp "${dl_file}" "${PLUGINS_DIR}/${name}.phar"
                    echo "   -> ${name}.phar"
                    ;;
            esac
            rm -f "${dl_file}"
            PLUGINS_ADDED=$((PLUGINS_ADDED + 1))
            return
        fi
        echo "   !! No release assets for ${repo}, falling back to archive download..."
        download_github_archive "${repo}" "${name}"
        echo "   -> plugins/${name}/"

    # 4) Generic URL
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
        echo "   Supported: .phar, .zip/.tar.gz, GitHub repo (owner/repo), URL"
        return 1
    fi

    PLUGINS_ADDED=$((PLUGINS_ADDED + 1))
}

# --- Parse CLI args ---
# Extract --add-plugin flags, pass everything else to POCKETMINE_ARGS
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

# Pass remaining args to start-pocketmine via POCKETMINE_ARGS
export POCKETMINE_ARGS="${PMMP_ARGS[*]}"

echo ":: Starting PocketMine-MP..."
cd /opt/pocketmine
exec start-pocketmine
