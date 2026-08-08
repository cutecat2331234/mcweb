# frozen_string_literal: true

module Api
  module V1
    # Self-describing index: version, the authenticated key's scopes/user, the
    # event catalog, and the available resource endpoints.
    class RootController < BaseController
      def index
        resources = %w[
          me categories tags topics posts users notifications conversations
          bookmarks profile_posts
        ]
        resources << "staff" if current_api_key.allows?("staff.moderation.read")

        render json: {
          version: "v1",
          authenticated_as: {
            key: current_api_key.name,
            scopes: current_api_key.scope_list,
            user: api_user&.username
          },
          events: Mcweb::Events::CATALOG,
          resources: resources
        }
      end
    end
  end
end
