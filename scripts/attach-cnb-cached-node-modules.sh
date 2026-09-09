#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "$#" != 2 ]]; then
  printf 'Usage: bash scripts/attach-cnb-cached-node-modules.sh CACHE_PACKAGE WORKSPACE_PACKAGE\n' >&2
  exit 2
fi

cache_package="$(cd -- "$1" && pwd -P)"
workspace_package="$(cd -- "$2" && pwd -P)"
cache_modules="${cache_package}/node_modules"
workspace_modules="${workspace_package}/node_modules"

if [[ ! -d "${cache_modules}" || -L "${cache_modules}" ]]; then
  printf 'Cached node_modules must be a real directory: %s\n' "${cache_modules}" >&2
  exit 1
fi

for manifest in package.json package-lock.json; do
  cmp -- "${workspace_package}/${manifest}" "${cache_package}/${manifest}"
done

# A fresh checkout is required. In particular, -e alone misses dangling links;
# never follow or replace an existing dependency tree, link, or partial copy.
if [[ -e "${workspace_modules}" || -L "${workspace_modules}" ]]; then
  printf 'Refusing to replace existing node_modules: %s\n' "${workspace_modules}" >&2
  exit 1
fi
mkdir -- "${workspace_modules}"

# Astro keys component metadata by real path. A top-level symlink into /opt can
# make its virtual CSS requests resolve relative to the checked-out site instead.
# Materialize only the cached tree, retaining relative package/bin links and
# modes. Reflinks are optional; the fallback is a copy, never a new npm install.
cp -a --reflink=auto -- "${cache_modules}/." "${workspace_modules}/"
