# frozen_string_literal: true

require "test_helper"

module Identity
  class AccountClosureRegistryTest < ActiveSupport::TestCase
    test "registry validates stable keys contributor contract duplicates and freeze boundary" do
      registry = AccountClosureRegistry.new
      contributor = recording_contributor([], "valid")

      entry = registry.register(key: "sample.valid", contributor:)
      assert_equal "sample.valid", entry.key
      assert_raises(ArgumentError) do
        registry.register(key: "sample.valid", contributor:)
      end
      assert_raises(ArgumentError) do
        registry.register(key: "invalid", contributor:)
      end
      assert_raises(ArgumentError) do
        registry.register(key: "sample.incomplete", contributor: Object.new)
      end

      registry.freeze!
      assert_predicate registry, :frozen?
      assert_raises(FrozenError) do
        registry.register(key: "sample.late", contributor:)
      end
    end

    test "core catalog is frozen and includes authored content" do
      keys = AccountClosureCatalog.entries.map(&:key)

      assert_includes keys, "identity.authored_content"
      assert AccountClosureCatalog.registry_frozen?
    end

    test "blocked preflight prevents every execution and returns module detail" do
      events = []
      blocker = Object.new
      blocker.define_singleton_method(:preflight) do |context:|
        events << [ :preflight, context.closure_mode ]
        AccountClosure::Contribution.blocked(
          code: "records_pending",
          details: { count: 2 }
        )
      end
      blocker.define_singleton_method(:execute) { |**| events << :execute }
      blocker.define_singleton_method(:compensate) { |**| events << :compensate }
      registry = AccountClosureRegistry.new
      registry.register(key: "sample.blocker", contributor: blocker)

      result = AccountClosure::Lifecycle.call(
        context: context,
        entries: registry.entries
      )

      assert_predicate result, :failure?
      assert_equal "account_close_preflight_blocked", result.code
      assert_equal [ [ :preflight, "anonymize" ] ], events
      payload = result.value.fetch(:contributions).fetch("sample.blocker")
      assert_equal "blocked", payload.fetch("status")
      assert_equal 2, payload.dig("details", "count")
    end

    test "execution failure compensates completed contributors in reverse order" do
      events = []
      first = recording_contributor(events, "first")
      second = recording_contributor(events, "second")
      failing = recording_contributor(events, "failing", fail_execute: true)
      registry = AccountClosureRegistry.new
      registry.register(key: "sample.first", contributor: first)
      registry.register(key: "sample.second", contributor: second)
      registry.register(key: "sample.failing", contributor: failing)

      result = AccountClosure::Lifecycle.call(context:, entries: registry.entries)

      assert_predicate result, :failure?
      assert_equal "account_close_contributor_failed", result.code
      assert_equal [
        "preflight:first", "preflight:second", "preflight:failing",
        "execute:first", "execute:second", "execute:failing",
        "compensate:second", "compensate:first"
      ], events
      compensations = result.value.fetch(:contributions).fetch("compensations")
      assert_equal "compensated", compensations.fetch("sample.second").fetch("status")
      assert_equal "compensated", compensations.fetch("sample.first").fetch("status")
    end

    test "finalizer failure also compensates every completed contributor" do
      events = []
      contributor = recording_contributor(events, "module")
      registry = AccountClosureRegistry.new
      registry.register(key: "sample.module", contributor:)

      result = AccountClosure::Lifecycle.call(
        context:,
        entries: registry.entries,
        finalize: ->(_contributions) { raise ActiveRecord::RecordInvalid }
      )

      assert_predicate result, :failure?
      assert_equal [ "preflight:module", "execute:module", "compensate:module" ], events
      assert_equal "failed",
                   result.value.fetch(:contributions)
                     .fetch("identity.finalization").fetch("status")
    end

    private

    def context
      AccountClosure::Context.new(
        user: nil,
        closure_mode: "anonymize",
        reason: "test",
        at: Time.current
      )
    end

    def recording_contributor(events, name, fail_execute: false)
      contributor = Object.new
      contributor.define_singleton_method(:preflight) do |context:|
        events << "preflight:#{name}"
        AccountClosure::Contribution.ready(details: { mode: context.closure_mode })
      end
      contributor.define_singleton_method(:execute) do |context:, preflight:|
        events << "execute:#{name}"
        if fail_execute
          AccountClosure::Contribution.failed(code: "injected")
        else
          AccountClosure::Contribution.completed(
            details: preflight.details,
            compensation_data: { name:, at: context.at }
          )
        end
      end
      contributor.define_singleton_method(:compensate) do |context:, execution:|
        events << "compensate:#{execution.compensation_data.fetch(:name)}"
        AccountClosure::Contribution.compensated(
          details: { at: context.at.iso8601 }
        )
      end
      contributor
    end
  end
end
