# frozen_string_literal: true

require "test_helper"

class WebsiteThemeVersionGovernanceTest < ActiveSupport::TestCase
  setup do
    @actor = create_user(account_type: "staff")
    created = Website::MutateTheme.call(
      operation: :create,
      theme: Website::Theme.new,
      actor: @actor,
      attributes: {
        name: "Governed Theme",
        key: "governed-theme-#{SecureRandom.hex(4)}",
        tokens: { "color" => { "primary" => "#123456" } }
      }
    )
    assert_predicate created, :success?, created.error
    @theme = created.value.fetch(:theme)
  end

  test "creation records a baseline and editing appends an immutable pre-change revision" do
    created = @theme.revisions.order(:revision_number).first
    assert_equal 1, created.revision_number
    assert_equal "create", created.event_type
    assert_equal "Governed Theme", created.snapshot.fetch("name")
    assert_equal 0, created.source_lock_version

    result = Website::MutateTheme.call(
      operation: :update,
      theme: @theme,
      actor: @actor,
      expected_lock_version: @theme.lock_version,
      attributes: {
        name: "Governed Theme Two",
        key: @theme.key,
        tokens: { "color" => { "primary" => "#abcdef" } }
      }
    )

    assert_predicate result, :success?, result.error
    edited = result.value.fetch(:revision)
    assert_equal 2, edited.revision_number
    assert_equal "update", edited.event_type
    assert_equal @actor, edited.actor
    assert_equal "Governed Theme", edited.snapshot.fetch("name")
    assert_equal "#123456", edited.snapshot.dig("tokens", "color", "primary")
    assert_equal "Governed Theme Two", @theme.reload.name
    assert_not edited.update(reason: "rewrite history")
    assert_not edited.destroy
  end

  test "timestamp advancement remains monotonic without Numeric microsecond extensions" do
    contract = Class.new do
      include Website::ThemeVersionContract
    end.new
    original = Time.current.change(usec: 123_456)
    timestamp_holder = Struct.new(:updated_at).new(original)

    Time.stub(:current, original) do
      contract.send(:advance_theme_timestamp, timestamp_holder)
    end

    assert_equal original + Rational(1, 1_000_000), timestamp_holder.updated_at
  end

  test "activation serializes the global active set and revisions every changed Theme" do
    created = Website::MutateTheme.call(
      operation: :create,
      theme: Website::Theme.new,
      actor: @actor,
      attributes: {
        name: "Current Theme",
        key: "current-theme-#{SecureRandom.hex(4)}",
        tokens: {}
      }
    )
    assert_predicate created, :success?, created.error
    current = created.value.fetch(:theme)
    activated = Website::MutateTheme.call(
      operation: :activate,
      theme: current,
      actor: @actor,
      expected_lock_version: current.lock_version
    )
    assert_predicate activated, :success?, activated.error

    candidate_version = @theme.reload.lock_version
    switched = Website::MutateTheme.call(
      operation: :activate,
      theme: @theme,
      actor: @actor,
      expected_lock_version: candidate_version
    )

    assert_predicate switched, :success?, switched.error
    assert_equal [ @theme.id ], Website::Theme.active_themes.pluck(:id)
    assert_equal "activate", @theme.revisions.ordered.first.event_type
    assert_equal "deactivate", current.revisions.ordered.first.event_type
    assert_equal false, @theme.revisions.ordered.first.snapshot.fetch("active")
    assert_equal true, current.revisions.ordered.first.snapshot.fetch("active")
  end

  test "restore preserves activation and creates one successor with attributable audit" do
    activated = Website::MutateTheme.call(
      operation: :activate,
      theme: @theme,
      actor: @actor,
      expected_lock_version: @theme.lock_version
    )
    assert_predicate activated, :success?, activated.error
    source = @theme.revisions.order(:revision_number).first
    changed = Website::MutateTheme.call(
      operation: :update,
      theme: @theme,
      actor: @actor,
      expected_lock_version: @theme.reload.lock_version,
      attributes: {
        name: "Changed Theme",
        key: "changed-theme-#{SecureRandom.hex(4)}",
        tokens: { "spacing" => 12 }
      }
    )
    assert_predicate changed, :success?, changed.error
    expected = @theme.reload.lock_version
    request_id = "theme-restore-#{SecureRandom.uuid}"
    source_before = source.attributes.deep_dup

    restored = Website::RestoreThemeRevision.call(
      theme: @theme,
      revision: source,
      actor: @actor,
      reason: "Return to the reviewed visual baseline",
      confirmation: source.revision_number.to_s,
      expected_lock_version: expected,
      idempotency_key: request_id
    )

    assert_predicate restored, :success?, restored.error
    successor = restored.value.fetch(:revision)
    @theme.reload
    assert_equal "Governed Theme", @theme.name
    assert_equal source.snapshot.fetch("key"), @theme.key
    assert @theme.active?, "version recovery must not deactivate the live Theme"
    assert_equal "restore", successor.event_type
    assert_equal source.id, successor.source_revision_id
    assert_equal expected, successor.source_lock_version
    assert_equal "Changed Theme", successor.snapshot.fetch("name")
    assert successor.snapshot.fetch("active")
    assert_equal source_before, source.reload.attributes

    audit = AuditLog.where(
      action: "website.theme.revision_restored",
      resource_type: "Website::Theme",
      resource_id: @theme.id
    ).order(:id).last
    assert_equal @actor, audit.actor
    assert_equal "Return to the reviewed visual baseline", audit.reason
    assert_equal source.revision_number, audit.metadata.fetch("source_revision_number")
    assert_equal expected, audit.metadata.fetch("submitted_lock_version")
    assert_equal @theme.lock_version, audit.metadata.fetch("current_lock_version")
    assert_equal successor.revision_number, audit.metadata.fetch("successor_revision_number")
  end

  test "identical restore retries converge while conflicting reuse fails closed" do
    source = @theme.revisions.first
    updated = Website::MutateTheme.call(
      operation: :update,
      theme: @theme,
      actor: @actor,
      expected_lock_version: @theme.lock_version,
      attributes: {
        name: "Temporary Theme",
        key: @theme.key,
        tokens: { "temporary" => true }
      }
    )
    assert_predicate updated, :success?, updated.error
    expected = @theme.reload.lock_version
    request_id = "theme-retry-#{SecureRandom.uuid}"
    attributes = {
      theme: @theme,
      revision: source,
      actor: @actor,
      reason: "Retry-safe recovery",
      confirmation: source.revision_number.to_s,
      expected_lock_version: expected,
      idempotency_key: request_id
    }

    first = Website::RestoreThemeRevision.call(**attributes)
    second = Website::RestoreThemeRevision.call(**attributes)
    conflict = Website::RestoreThemeRevision.call(
      **attributes.merge(reason: "A different recovery operation")
    )

    assert_predicate first, :success?, first.error
    assert_predicate second, :success?, second.error
    assert second.value.fetch(:replayed)
    assert_equal first.value.fetch(:revision).id, second.value.fetch(:revision).id
    assert_predicate conflict, :failure?
    assert_equal "website_theme_idempotency_key_reused", conflict.code
    assert_equal 1, @theme.revisions.where(event_type: "restore").count
    assert_equal 1, AuditLog.where(
      action: "website.theme.revision_restored",
      resource_type: "Website::Theme",
      resource_id: @theme.id
    ).count
  end

  test "stale restore leaves Theme revision and audit state unchanged" do
    source = @theme.revisions.first
    stale_version = @theme.lock_version
    updated = Website::MutateTheme.call(
      operation: :update,
      theme: @theme,
      actor: @actor,
      expected_lock_version: stale_version,
      attributes: { name: "Concurrent Theme", key: @theme.key, tokens: {} }
    )
    assert_predicate updated, :success?, updated.error
    revision_count = @theme.revisions.count
    audit_count = AuditLog.count

    result = Website::RestoreThemeRevision.call(
      theme: @theme,
      revision: source,
      actor: @actor,
      reason: "Stale recovery must fail",
      confirmation: source.revision_number.to_s,
      expected_lock_version: stale_version,
      idempotency_key: "theme-stale-#{SecureRandom.uuid}"
    )

    assert_predicate result, :failure?
    assert_equal "website_theme_conflict", result.code
    assert_equal "Concurrent Theme", @theme.reload.name
    assert_equal revision_count, @theme.revisions.count
    assert_equal audit_count, AuditLog.count
  end

  test "concurrent identical restores converge on one successor" do
    source = @theme.revisions.first
    changed = Website::MutateTheme.call(
      operation: :update,
      theme: @theme,
      actor: @actor,
      expected_lock_version: @theme.lock_version,
      attributes: { name: "Concurrent Candidate", key: @theme.key, tokens: {} }
    )
    assert_predicate changed, :success?, changed.error
    expected = @theme.reload.lock_version
    request_id = "theme-concurrent-#{SecureRandom.uuid}"
    ready = Queue.new
    gate = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          Website::RestoreThemeRevision.call(
            theme: Website::Theme.find(@theme.id),
            revision: Website::ThemeRevision.find(source.id),
            actor: User.find(@actor.id),
            reason: "Concurrent retry convergence",
            confirmation: source.revision_number.to_s,
            expected_lock_version: expected,
            idempotency_key: request_id
          )
        end
      end
    end
    2.times { ready.pop }
    2.times { gate << true }
    results = threads.map(&:value)

    assert results.all?(&:success?), results.map(&:error).inspect
    assert_equal 1, results.map { |result| result.value.fetch(:revision).id }.uniq.length
    assert_equal 1, @theme.revisions.where(event_type: "restore").count
  end

  test "Themes with immutable history cannot be hard-deleted" do
    revision_ids = @theme.revisions.pluck(:id)

    assert_not @theme.destroy

    assert Website::Theme.exists?(@theme.id)
    assert_equal revision_ids, Website::ThemeRevision.where(website_theme_id: @theme.id).pluck(:id)
  end
end
