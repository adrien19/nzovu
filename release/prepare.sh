#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_EVENT_NAME}" == workflow_dispatch ]]; then
    TAG="${REQUESTED_TAG}"
else
    TAG="${GITHUB_REF#refs/tags/}"
fi
SEMVER='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$'
[[ "${TAG}" =~ ${SEMVER} ]] || { echo "Invalid release tag: ${TAG}" >&2; exit 1; }
TAG_COMMIT="$(git rev-parse --verify "refs/tags/${TAG}^{commit}")"
[[ "${TAG_COMMIT}" == "$(git rev-parse HEAD)" ]] || { echo 'Checkout does not match tag' >&2; exit 1; }
git merge-base --is-ancestor "${TAG_COMMIT}" refs/remotes/origin/main || { echo 'Release commit is not on main' >&2; exit 1; }
if [[ "${GITHUB_EVENT_NAME}" == push ]]; then
    [[ "${TAG_COMMIT}" == "${GITHUB_SHA}" ]] || { echo 'Tag does not match event commit' >&2; exit 1; }
fi
VERSION="${TAG#v}"
IMAGE_TAG="${VERSION//+/-}"
[[ ${#IMAGE_TAG} -le 128 ]] || { echo 'Release version exceeds container tag limit' >&2; exit 1; }
PRERELEASE=false
[[ "${VERSION%%+*}" == *-* ]] && PRERELEASE=true
BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
printf 'tag=%s\nversion=%s\nimage_tag=%s\nprerelease=%s\nbuild_date=%s\ncommit=%s\n' \
    "${TAG}" "${VERSION}" "${IMAGE_TAG}" "${PRERELEASE}" "${BUILD_DATE}" "${TAG_COMMIT}" >> "${GITHUB_OUTPUT}"

PREVIOUS_TAG="$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || true)"
if [[ -z "${PREVIOUS_TAG}" ]]; then
    printf '## Initial release %s\n' "${TAG}" > CHANGELOG.md
else
    {
        printf "## What's Changed in %s\n\n" "${TAG}"
        git log "${PREVIOUS_TAG}..HEAD" --pretty=format:'- %s (%h)' --reverse
        printf '\n\n**Full Changelog**: https://github.com/%s/compare/%s...%s\n' "${GITHUB_REPOSITORY}" "${PREVIOUS_TAG}" "${TAG}"
    } > CHANGELOG.md
fi
