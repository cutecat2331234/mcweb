#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

canary_path="${repository_root}/tmp/rails-failure-canary-$$"
mkdir -p -- "${repository_root}/tmp"
cleanup() {
  rm -f -- "${canary_path}"
}
trap cleanup EXIT

if MCWEB_CI_FAILURE_CANARY_PATH="${canary_path}" \
  bin/rails test test/fixtures/ci_exit_status_failure_test.rb; then
  echo "Rails test runner returned success for an intentional failure" >&2
  exit 1
fi

if [[ ! -f "${canary_path}" ]] || [[ "$(<"${canary_path}")" != "executed" ]]; then
  echo "Rails failure canary did not execute" >&2
  exit 1
fi

bin/rails test "$@"
