# frozen_string_literal: true

module Api
  module V1
    class TagsController < BaseController
      skip_before_action :require_read_scope!, only: :subscription
      before_action :require_writer!, only: :subscription

      # GET /api/v1/tags — canonical (non-synonym) tags usable by this key.
      def index
        scope = Community::Tag.where(canonical_tag_id: nil)
        scope = scope.where(staff_only: false) unless staff_key?
        scope = scope.ordered

        pagy, tags = api_paginate(scope)

        render json: {
          data: tags.map { |tag| { id: tag.slug, name: tag.name } },
          meta: pagination_meta(pagy)
        }
      end

      # POST /api/v1/tags/:id/subscription  (write scope) — follow/track a tag
      # params: level = watching | tracking | normal | off ; :id = tag slug
      def subscription
        tag = Community::Tag.resolve_by_slug(params[:id])
        raise ActiveRecord::RecordNotFound unless tag

        result = Community::SetSubscriptionLevel.call(user: api_user, subscribable: tag, level: params[:level].to_s)
        return render_service_error(result) if result.failure?

        render json: { data: { tag_id: tag.slug, notification_level: result.value[:notification_level] } }
      end

      private

      def staff_key?
        api_user&.permission?("forum.tags.manage") || api_user&.permission?("admin.access")
      end
    end
  end
end
