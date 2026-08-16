#!/bin/bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="$ROOT/test/fixtures/container_startup"
TEST_ROOT="$(mktemp -d)"
APP_ROOT="$TEST_ROOT/app"
KAMAL_ROOT="$TEST_ROOT/kamal"
TRACE_FILE="$TEST_ROOT/trace.log"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_status() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  [ "$actual" -eq "$expected" ] || fail "$label: expected status $expected, got $actual"
}

assert_trace() {
  local expected="$1"
  local label="$2"
  local actual

  actual="$(tr -d '\r' < "$TRACE_FILE")"
  [ "$actual" = "$expected" ] || {
    printf 'Expected trace for %s:\n%s\nActual trace:\n%s\n' "$label" "$expected" "$actual" >&2
    exit 1
  }
}

run_entrypoint() {
  local prepare_exit="$1"
  local schema_exit="$2"
  local release_exit="$3"
  shift 3

  : > "$TRACE_FILE"
  set +e
  (
    cd "$APP_ROOT"
    PATH="$APP_ROOT/fake-bin:$PATH" \
      TRACE_FILE="$TRACE_FILE" \
      PREPARE_EXIT="$prepare_exit" \
      SCHEMA_EXIT="$schema_exit" \
      RELEASE_EXIT="$release_exit" \
      ./bin/docker-entrypoint "$@"
  )
  RUN_STATUS=$?
  set -e
}

mkdir -p "$APP_ROOT" "$KAMAL_ROOT/.kamal/hooks"
cp -R "$FIXTURES/app/." "$APP_ROOT/"
cp "$ROOT/bin/docker-entrypoint" "$APP_ROOT/bin/docker-entrypoint"
cp -R "$FIXTURES/kamal/." "$KAMAL_ROOT/"
cp "$ROOT/.kamal/hooks/pre-deploy" "$KAMAL_ROOT/.kamal/hooks/pre-deploy"
chmod +x \
  "$APP_ROOT/bin/docker-entrypoint" \
  "$APP_ROOT/bin/docker-release" \
  "$APP_ROOT/bin/rails" \
  "$APP_ROOT/fake-bin/bundle" \
  "$KAMAL_ROOT/bin/kamal" \
  "$KAMAL_ROOT/.kamal/hooks/pre-deploy"

run_entrypoint 0 0 0 release
assert_status 0 "$RUN_STATUS" "release succeeds"
assert_trace $'rails:db:prepare\nrelease-hook' "release ordering"

run_entrypoint 23 0 0 release
assert_status 23 "$RUN_STATUS" "migration failure is returned"
assert_trace 'rails:db:prepare' "migration failure stops the release hook"

run_entrypoint 0 0 29 release
assert_status 29 "$RUN_STATUS" "downstream release failure is returned"
assert_trace $'rails:db:prepare\nrelease-hook' "release hook runs after migration"

run_entrypoint 0 0 0 release unexpected
assert_status 64 "$RUN_STATUS" "release rejects extra commands"
assert_trace '' "invalid release does not access the database"

run_entrypoint 0 0 0 web
assert_status 0 "$RUN_STATUS" "web role starts"
assert_trace $'rails:db:abort_if_pending_migrations\nprocess:exec puma -C config/puma.rb' "web role ordering"

run_entrypoint 0 0 0 worker
assert_status 0 "$RUN_STATUS" "worker role starts"
assert_trace $'rails:db:abort_if_pending_migrations\nprocess:exec sidekiq -C config/sidekiq.yml' "worker role ordering"

run_entrypoint 0 0 0 bundle exec puma -C config/puma.rb
assert_status 0 "$RUN_STATUS" "direct Puma command starts"
assert_trace $'rails:db:abort_if_pending_migrations\nprocess:exec puma -C config/puma.rb' "direct Puma remains guarded"

run_entrypoint 0 0 0 bundle exec sidekiq -C config/sidekiq.yml
assert_status 0 "$RUN_STATUS" "direct Sidekiq command starts"
assert_trace $'rails:db:abort_if_pending_migrations\nprocess:exec sidekiq -C config/sidekiq.yml' "direct Sidekiq remains guarded"

run_entrypoint 0 0 0 ./bin/rails server
assert_status 0 "$RUN_STATUS" "Rails server command starts"
assert_trace $'rails:db:abort_if_pending_migrations\nrails:server' "Rails server remains guarded"

run_entrypoint 0 31 0 bundle exec puma -C config/puma.rb
assert_status 31 "$RUN_STATUS" "pending migrations block Puma"
assert_trace 'rails:db:abort_if_pending_migrations' "Puma never runs with a pending schema"

: > "$TRACE_FILE"
set +e
(
  cd "$KAMAL_ROOT"
  TRACE_FILE="$TRACE_FILE" \
    KAMAL_VERSION=release-sha \
    KAMAL_DESTINATION=production \
    ./.kamal/hooks/pre-deploy
)
RUN_STATUS=$?
set -e
assert_status 0 "$RUN_STATUS" "Kamal release hook succeeds"
assert_trace \
  'kamal:app exec --primary --roles web --version release-sha --destination production release' \
  "Kamal runs one release container on the primary web host"

: > "$TRACE_FILE"
set +e
(
  cd "$KAMAL_ROOT"
  TRACE_FILE="$TRACE_FILE" KAMAL_VERSION=release-sha KAMAL_EXIT=47 ./.kamal/hooks/pre-deploy
)
RUN_STATUS=$?
set -e
assert_status 47 "$RUN_STATUS" "Kamal propagates release failure"
assert_trace \
  'kamal:app exec --primary --roles web --version release-sha release' \
  "Kamal failure uses the selected image"

: > "$TRACE_FILE"
set +e
(
  cd "$KAMAL_ROOT"
  TRACE_FILE="$TRACE_FILE" ./.kamal/hooks/pre-deploy
)
RUN_STATUS=$?
set -e
assert_status 64 "$RUN_STATUS" "Kamal requires an immutable image version"
assert_trace '' "missing version never starts a container"

printf 'container startup contract: PASS\n'
