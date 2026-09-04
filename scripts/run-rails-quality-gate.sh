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

rails_test_timeout_seconds="${MCWEB_RAILS_TEST_TIMEOUT_SECONDS:-12600}"
rails_test_kill_after_seconds="${MCWEB_RAILS_TEST_KILL_AFTER_SECONDS:-30}"

if [[ ! "${rails_test_timeout_seconds}" =~ ^[1-9][0-9]*$ ]]; then
  echo "MCWEB_RAILS_TEST_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi
if [[ ! "${rails_test_kill_after_seconds}" =~ ^[1-9][0-9]*$ ]]; then
  echo "MCWEB_RAILS_TEST_KILL_AFTER_SECONDS must be a positive integer" >&2
  exit 2
fi
if ! command -v timeout >/dev/null 2>&1; then
  echo "The Rails quality gate requires the timeout command" >&2
  exit 2
fi

printf 'Rails test watchdog timeout_seconds=%s kill_after_seconds=%s\n' \
  "${rails_test_timeout_seconds}" "${rails_test_kill_after_seconds}"
timeout --signal=TERM --kill-after="${rails_test_kill_after_seconds}s" \
  "${rails_test_timeout_seconds}s" bin/rails test "$@"
