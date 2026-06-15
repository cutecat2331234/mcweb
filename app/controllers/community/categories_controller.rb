# frozen_string_literal: true

module Community
  class CategoriesController < ApplicationController
    def show
      category = Community::Category.find_by!(slug: params[:slug])
      @pagy, sections = pagy(category.sections.roots.ordered.includes(:category, :children), limit: 20)
      unread_map = if logged_in?
                     sections.each_with_object({}) do |section, hash|
                       hash[section.id] = Community::ReadState.unread_count_for_section(current_user, section)
                       section.children.each do |child|
                         hash[child.id] = Community::ReadState.unread_count_for_section(current_user, child)
                       end
                     end
      else
                     {}
      end

      render inertia: "Community/Sections/Index", props: {
        sections: sections.map { |section| serialize_section(section, unread_map: unread_map) },
        categories: [ {
          slug: category.slug,
          name: category.name,
          description: category.description,
          icon: category.icon,
          color_hex: category.color_hex,
          seo_title: category.seo["title"],
          seo_description: category.seo["description"]
        } ],
        pagination: pagy_props(@pagy),
        activeCategory: category.slug
      }
    end
  end
end
