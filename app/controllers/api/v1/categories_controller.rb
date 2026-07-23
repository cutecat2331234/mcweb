# frozen_string_literal: true

module Api
  module V1
    class CategoriesController < BaseController
      include Serialization
      include ForumVisibility

      # GET /api/v1/categories
      # Lists categories with the sections visible to this key.
      def index
        visible_ids = visible_section_ids
        categories = Community::Category.ordered.to_a

        payload = categories.filter_map do |category|
          sections = category.sections.ordered.select { |s| visible_ids.include?(s.id) }
          next if sections.empty?

          serialize_category(category).merge(sections: sections.map { |s| serialize_section(s) })
        end

        render json: { data: payload }
      end
    end
  end
end
