# frozen_string_literal: true

module Community
  class SectionsController < ApplicationController
    def index
      @pagy, @sections = pagy(Community::Section.roots.ordered.includes(:category, :children), limit: 20)
    end

    def show
      @section = Community::Section.find_by!(slug: params[:id])
      @pagy, @topics = pagy(@section.topics.pinned_first, limit: 20)
    end
  end
end
