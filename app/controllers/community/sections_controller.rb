# frozen_string_literal: true

module Community
  class SectionsController < ApplicationController
    def index
      @pagy, sections = pagy(Community::Section.roots.ordered.includes(:category, :children), limit: 20)

      render inertia: "Community/Sections/Index", props: {
        sections: sections.map { |section| serialize_section(section) },
        pagination: pagy_props(@pagy)
      }
    end

    def show
      section = Community::Section.find_by!(slug: params[:id])
      @pagy, topics = pagy(section.topics.pinned_first, limit: 20)

      render inertia: "Community/Sections/Show", props: {
        section: {
          name: section.name,
          slug: section.slug,
          description: section.description,
          new_topic_url: logged_in? ? new_forum_topic_path(section_id: section.slug) : nil
        },
        topics: topics.map { |topic| serialize_topic(topic) },
        pagination: pagy_props(@pagy),
        canCreateTopic: logged_in?
      }
    end
  end
end
