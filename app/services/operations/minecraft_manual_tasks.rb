# frozen_string_literal: true

module Operations
  module MinecraftManualTasks
    module_function

    PERMISSIONS = %w[system.jobs.manage minecraft.players.manage].freeze

    def register(registry)
      register_skin_tasks(registry)
      register_diagnostic_tasks(registry)
    end

    def register_skin_tasks(registry)
      registry.register(
        key: "minecraft.skin.refresh_identity",
        label_key: "admin.jobsPage.manualTasks.tasks.refreshSkin.title",
        description_key: "admin.jobsPage.manualTasks.tasks.refreshSkin.description",
        permissions: PERMISSIONS,
        argument_schema: {
          "identity_id" => {
            type: "integer",
            required: true,
            minimum: 1,
            label_key: "admin.jobsPage.manualTasks.identityId",
            help_key: "admin.jobsPage.manualTasks.identityIdHelp"
          }
        }
      ) do |run|
        identity = Minecraft::PlayerIdentity.active.bound.find_by(
          id: run.arguments.fetch("identity_id")
        )
        raise_execution("minecraft_identity_unavailable") unless identity

        result = Minecraft::RequestSkinRefresh.call(
          player_identity: identity,
          actor: run.requested_by,
          request_id: "manual-task-run:#{run.id}",
          trigger: "manual",
          force: true
        )
        unwrap!(result, "skin_refresh_rejected")
        request = result.value.fetch(:request)
        { skin_refresh_request_id: request.id, enqueued: !result.value[:replayed] }
      end

      {
        "minecraft.skin.refresh_due" => [ false, nil ],
        "minecraft.skin.refresh_all" => [ true, nil ],
        "minecraft.skin.refresh_missing" => [ true, "missing" ],
        "minecraft.skin.retry_failed" => [ true, "failed" ]
      }.each do |key, (force, scope)|
        name = {
          "minecraft.skin.refresh_due" => "refreshDueSkins",
          "minecraft.skin.refresh_all" => "refreshAllSkins",
          "minecraft.skin.refresh_missing" => "refreshMissingSkins",
          "minecraft.skin.retry_failed" => "retryFailedSkins"
        }.fetch(key)
        registry.register(
          key: key,
          label_key: "admin.jobsPage.manualTasks.tasks.#{name}.title",
          description_key: "admin.jobsPage.manualTasks.tasks.#{name}.description",
          permissions: PERMISSIONS
        ) do |run|
          result = Minecraft::RequestAllSkinRefreshes.call(
            actor: run.requested_by,
            request_id: "manual-task-run:#{run.id}",
            force: force,
            scope: scope
          )
          unwrap!(result, "skin_refresh_batch_rejected")
          { enqueued: true, selection: scope || (force ? "all" : "due") }
        end
      end

      registry.register(
        key: "minecraft.skin.refresh_selected",
        label_key: "admin.jobsPage.manualTasks.tasks.refreshSelectedSkins.title",
        description_key: "admin.jobsPage.manualTasks.tasks.refreshSelectedSkins.description",
        permissions: PERMISSIONS,
        argument_schema: {
          "identity_ids" => {
            type: "integer_list",
            required: true,
            minimum: 1,
            maximum_items: 200,
            label_key: "admin.jobsPage.manualTasks.identityIds",
            help_key: "admin.jobsPage.manualTasks.identityIdsHelp"
          }
        }
      ) do |run|
        result = Minecraft::RequestAllSkinRefreshes.call(
          actor: run.requested_by,
          request_id: "manual-task-run:#{run.id}",
          force: true,
          scope: "selected",
          identity_ids: run.arguments.fetch("identity_ids")
        )
        unwrap!(result, "skin_refresh_batch_rejected")
        { enqueued: true, selection: "selected" }
      end

      registry.register(
        key: "minecraft.skin.rebuild_derivatives",
        label_key: "admin.jobsPage.manualTasks.tasks.rebuildSkinDerivatives.title",
        description_key: "admin.jobsPage.manualTasks.tasks.rebuildSkinDerivatives.description",
        permissions: PERMISSIONS
      ) do |run|
        unwrap!(
          Minecraft::RebuildSkinDerivatives.call(actor: run.requested_by),
          "skin_derivative_rebuild_failed"
        ).value
      end
    end

    def register_diagnostic_tasks(registry)
      {
        "minecraft.skin.validate_cache" => [ "validateSkinCache", "cache_files" ],
        "minecraft.accounts.check_uuid_duplicates" => [ "checkUuidDuplicates", "duplicate_uuids" ],
        "minecraft.accounts.check_primary_constraints" => [ "checkPrimaryAccounts", "primary_accounts" ]
      }.each do |key, (name, kind)|
        registry.register(
          key: key,
          label_key: "admin.jobsPage.manualTasks.tasks.#{name}.title",
          description_key: "admin.jobsPage.manualTasks.tasks.#{name}.description",
          permissions: PERMISSIONS
        ) do |_run|
          unwrap!(
            Minecraft::SkinCacheDiagnostics.call(kind: kind),
            "skin_diagnostic_failed"
          ).value
        end
      end
    end

    def unwrap!(result, fallback_code)
      return result if result.success?

      code = result.respond_to?(:code) && result.code.present? ? result.code : fallback_code
      error = result.respond_to?(:error) ? result.error : nil
      raise Operations::ManualTaskCatalog::ExecutionError.new(
        code,
        error.to_s.presence || code
      )
    end

    def raise_execution(code)
      raise Operations::ManualTaskCatalog::ExecutionError.new(code)
    end
  end
end
