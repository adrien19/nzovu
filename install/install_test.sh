#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

version="0.0.1"
tag="v${version}"
commit="0123456789abcdef0123456789abcdef01234567"
build_date="2026-08-17T12:34:56Z"
case "$(uname -s)" in
    Linux) os="linux" ;;
    Darwin) os="darwin" ;;
    *) echo "unsupported test operating system: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    aarch64 | arm64) arch="arm64" ;;
    armv7* | armhf) arch="arm" ;;
    *) echo "unsupported test architecture: $(uname -m)" >&2; exit 1 ;;
esac
binary_name="nzovu-${tag}-${os}-${arch}"
release_dir="${test_root}/releases/download/${tag}"
staging_dir="${test_root}/staging"
install_dir="${test_root}/install"
mkdir -p "${release_dir}" "${staging_dir}"

(
    cd "${repository_root}"
    CGO_ENABLED=0 go build -trimpath \
        -ldflags="-X github.com/adrien19/nzovu/pkg/version.Version=${version} -X github.com/adrien19/nzovu/pkg/version.GitCommit=${commit} -X github.com/adrien19/nzovu/pkg/version.BuildDate=${build_date}" \
        -o "${staging_dir}/${binary_name}" .
)
write_checksum() {
    (
        cd "${release_dir}"
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "${binary_name}.tar.gz"
        else
            shasum -a 256 "${binary_name}.tar.gz"
        fi > "${binary_name}.tar.gz.sha256"
    )
}

printf 'version=%s\ncommit=%s\nbuild_date=%s\n' \
    "${tag}" "${commit}" "${build_date}" > "${staging_dir}/${binary_name}.release"
tar -C "${staging_dir}" -czf "${release_dir}/${binary_name}.tar.gz" \
    "${binary_name}" "${binary_name}.release"
write_checksum

create_archive() {
    tar -C "${staging_dir}" -czf "${release_dir}/${binary_name}.tar.gz" \
        "${binary_name}" "${binary_name}.release"
    write_checksum
}

install_version() {
    NZOVU_RELEASES_URL="file://${test_root}/releases" \
    NZOVU_API_URL="file://${test_root}/latest.json" \
    NZOVU_INSTALL_DIR="${install_dir}" \
        bash "${repository_root}/install/install.sh" "$@"
}

expect_failure() {
    local expected="$1"
    shift
    if install_version "$@" > "${test_root}/failure.log" 2>&1; then
        echo "installation unexpectedly succeeded: ${expected}" >&2
        exit 1
    fi
    grep -Fq "${expected}" "${test_root}/failure.log"
    cmp "${install_dir}/nzovu" "${staging_dir}/${binary_name}"
}

install_version "${version}"
output="$("${install_dir}/nzovu" --version)"
grep -Fq "Nzovu v${version}" <<<"${output}"
grep -Fq "Git Commit: ${commit}" <<<"${output}"
grep -Fq "Built:      ${build_date}" <<<"${output}"
test ! -e "${install_dir}/chronoqueue"

printf '{"tag_name":"%s"}\n' "${tag}" > "${test_root}/latest.json"
install_version
install_version "${tag}"

printf 'version=v0.0.2\ncommit=%s\nbuild_date=%s\n' \
    "${commit}" "${build_date}" > "${staging_dir}/${binary_name}.release"
create_archive
expect_failure "does not match requested version" "${version}"

printf 'version=%s\ncommit=abcdefabcdefabcdefabcdefabcdefabcdefabcd\nbuild_date=%s\n' \
    "${tag}" "${build_date}" > "${staging_dir}/${binary_name}.release"
create_archive
expect_failure "commit does not match" "${version}"

printf 'version=%s\ncommit=%s\nbuild_date=%s\n' \
    "${tag}" "${commit}" "${build_date}" > "${staging_dir}/${binary_name}.release"
create_archive
printf '%064d  %s\n' 0 "${binary_name}.tar.gz" > "${release_dir}/${binary_name}.tar.gz.sha256"
expect_failure "Checksum mismatch" "${version}"

tar -C "${staging_dir}" -czf "${release_dir}/${binary_name}.tar.gz" "${binary_name}.release"
write_checksum
expect_failure "Binary '${binary_name}' not found" "${version}"

expect_failure "Invalid version" "not-semver"
expect_failure "Invalid version" "0.0.1-01"
echo "Unix installer fixtures passed."
