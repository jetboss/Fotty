#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 MAJOR.MINOR.PATCH BUILD_NUMBER" >&2
    exit 64
fi

marketing_version="$1"
build_number="$2"

if [[ ! "$marketing_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Marketing version must use MAJOR.MINOR.PATCH, for example 1.7.1." >&2
    exit 64
fi

if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "Build number must be a positive integer." >&2
    exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
project_file="$project_root/Fotty.xcodeproj/project.pbxproj"
project_config="$project_root/project.yml"

if [[ ! -f "$project_file" ]]; then
    echo "Could not find Fotty.xcodeproj/project.pbxproj." >&2
    exit 66
fi

/usr/bin/perl -0pi -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $marketing_version;/g; s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $build_number;/g" "$project_file"

if [[ -f "$project_config" ]]; then
    /usr/bin/perl -0pi -e "s/MARKETING_VERSION: [^\n]+/MARKETING_VERSION: $marketing_version/g; s/CURRENT_PROJECT_VERSION: [^\n]+/CURRENT_PROJECT_VERSION: $build_number/g" "$project_config"
fi

version_values="$(/usr/bin/grep -E 'MARKETING_VERSION = ' "$project_file" | /usr/bin/awk '{print $3}' | /usr/bin/tr -d ';' | /usr/bin/sort -u)"
build_values="$(/usr/bin/grep -E 'CURRENT_PROJECT_VERSION = ' "$project_file" | /usr/bin/awk '{print $3}' | /usr/bin/tr -d ';' | /usr/bin/sort -u)"

if [[ "$version_values" != "$marketing_version" || "$build_values" != "$build_number" ]]; then
    echo "Version update did not converge across all targets." >&2
    echo "Marketing values: $version_values" >&2
    echo "Build values: $build_values" >&2
    exit 65
fi

if [[ -f "$project_config" ]]; then
    config_version_values="$(/usr/bin/grep -E 'MARKETING_VERSION: ' "$project_config" | /usr/bin/awk '{print $2}' | /usr/bin/sort -u)"
    config_build_values="$(/usr/bin/grep -E 'CURRENT_PROJECT_VERSION: ' "$project_config" | /usr/bin/awk '{print $2}' | /usr/bin/sort -u)"
    if [[ "$config_version_values" != "$marketing_version" || "$config_build_values" != "$build_number" ]]; then
        echo "Version update did not converge in project.yml." >&2
        echo "Marketing values: $config_version_values" >&2
        echo "Build values: $config_build_values" >&2
        exit 65
    fi
fi

echo "Fotty version set to $marketing_version ($build_number) across Xcode targets and source configuration."
