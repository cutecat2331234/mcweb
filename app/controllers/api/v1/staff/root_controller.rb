# frozen_string_literal: true

module Api
  module V1
    module Staff
      class RootController < BaseController
        def index
          render json: {
            version: "v1",
            interface: "staff_moderation",
            authenticated_as: {
              key: current_api_key.name,
              user: api_user.username,
              scopes: current_api_key.scope_list
            },
            capabilities: {
              read: true,
              claim: current_api_key.allows?("staff.moderation.claim"),
              assign: current_api_key.allows?("staff.moderation.assign"),
              note: current_api_key.allows?("staff.moderation.note"),
              execute: current_api_key.allows?("staff.moderation.execute")
            },
            resources: {
              moderation_cases: {
                index: api_v1_staff_moderation_cases_path,
                authorize_action: authorize_action_api_v1_staff_moderation_cases_path,
                execute_action: execute_action_api_v1_staff_moderation_cases_path
              }
            },
            contracts: {
              pagination: "page_limit",
              concurrency: "lock_version",
              idempotency: "Idempotency-Key",
              destructive_confirmation: "signed_typed_challenge"
            },
            events: Mcweb::Events::CATALOG.grep(/\Aforum\./)
          }
        end
      end
    end
  end
end
