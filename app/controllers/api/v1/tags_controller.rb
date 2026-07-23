# frozen_string_literal: true

module Api
  module V1
    class TagsController < BaseController
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

      private

      def staff_key?
        api_user&.permission?("forum.tags.manage") || api_user&.permission?("admin.access")
      end
    end
  end
end
