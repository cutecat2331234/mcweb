# frozen_string_literal: true

require "test_helper"

module Operations
  class ManualTaskCatalogTest < ActiveSupport::TestCase
    setup do
      @original_registrars = Array(
        Rails.application.config.x.operations_manual_task_registrars
      ).dup
      Rails.application.config.x.operations_manual_task_registrars = []
      Operations::ManualTaskCatalog.reset_registry!
    end

    teardown do
      Rails.application.config.x.operations_manual_task_registrars = @original_registrars
      Operations::ManualTaskCatalog.reset_registry!
    end

    test "registry accepts only explicit valid executors and freezes after construction" do
      registry = Operations::ManualTaskRegistry.new
      entry = registry.register(
        key: "example.profile.refresh",
        label_key: "example.title",
        description_key: "example.description",
        permissions: %w[system.jobs.manage example.profiles.manage],
        argument_schema: {
          "profile_id" => {
            type: "integer",
            required: true,
            minimum: 1,
            label_key: "example.profile_id"
          }
        }
      ) { |_run| { ok: true } }

      assert_equal "example.profile.refresh", entry.key
      assert_equal %w[system.jobs.manage example.profiles.manage], entry.permissions
      assert_equal "example.profile_id", entry.argument_schema.dig("profile_id", :label_key)
      assert_raises(ArgumentError) do
        registry.register(
          key: "example.profile.refresh",
          label_key: "duplicate",
          description_key: "duplicate",
          permissions: [ "system.jobs.manage" ]
        ) { nil }
      end
      assert_raises(ArgumentError) do
        registry.register(
          key: "Kernel",
          label_key: "unsafe",
          description_key: "unsafe",
          permissions: [ "system.jobs.manage" ]
        ) { nil }
      end
      assert_raises(ArgumentError) do
        registry.register(
          key: "example.missing_executor",
          label_key: "missing",
          description_key: "missing",
          permissions: [ "system.jobs.manage" ]
        )
      end

      registry.freeze!
      assert_predicate registry, :frozen?
      assert_raises(FrozenError) do
        registry.register(
          key: "example.after_freeze",
          label_key: "frozen",
          description_key: "frozen",
          permissions: [ "system.jobs.manage" ]
        ) { nil }
      end
    end

    test "downstream registrar adds schema keys before the catalog is frozen" do
      Rails.application.config.x.operations_manual_task_registrars = [
        lambda do |registry|
          registry.register(
            key: "downstream.profile.transition",
            label_key: "downstream.title",
            description_key: "downstream.description",
            permissions: [ "system.jobs.manage" ],
            argument_schema: {
              "profile_id" => { type: "integer", required: true, minimum: 1 },
              "desired_state_ids" => {
                type: "integer_list",
                required: true,
                minimum: 1,
                maximum_items: 10
              }
            }
          ) { |_run| { transitioned: true } }
        end
      ]

      entry = Operations::ManualTaskCatalog.entry("downstream.profile.transition")
      assert entry
      assert_predicate Operations::ManualTaskCatalog, :registry_frozen?
      assert_equal 9, Operations::ManualTaskCatalog.normalize_arguments(
        entry,
        "profile_id" => "9",
        "desired_state_ids" => "2, 3 3"
      ).fetch("profile_id")
      assert_equal [ 2, 3 ], Operations::ManualTaskCatalog.normalize_arguments(
        entry,
        "profile_id" => "9",
        "desired_state_ids" => "2, 3 3"
      ).fetch("desired_state_ids")

      error = assert_raises(Operations::ManualTaskCatalog::InvalidTask) do
        Operations::ManualTaskCatalog.normalize_arguments(
          entry,
          "profile_id" => "9",
          "desired_state_ids" => "2",
          "job_class" => "Kernel"
        )
      end
      assert_equal "unsupported_arguments", error.message
    end

    test "all declared permissions are required" do
      actor = create_user
      entry = Operations::ManualTaskRegistry.new.register(
        key: "example.permission.check",
        label_key: "example.title",
        description_key: "example.description",
        permissions: %w[system.jobs.manage minecraft.players.manage]
      ) { nil }

      grant_permission(actor, "system.jobs.manage")
      actor.reload
      refute Operations::ManualTaskCatalog.allowed?(actor, entry)

      grant_permission(actor, "minecraft.players.manage")
      actor.reload
      assert Operations::ManualTaskCatalog.allowed?(actor, entry)
    end
  end
end
