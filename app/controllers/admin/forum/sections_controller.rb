# frozen_string_literal: true

module Admin
  module Forum
    class SectionsController < BaseController
      before_action -> { require_permission("admin.forum.manage") }
      before_action :set_section, only: %i[show edit update destroy]

      def index
        @sections = ::Community::Section.ordered.includes(:category)
      end

      def show
      end

      def new
        @section = ::Community::Section.new
      end

      def create
        @section = ::Community::Section.new(section_params)

        if @section.save
          redirect_to admin_forum_section_path(@section), notice: "Section created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @section.update(section_params)
          redirect_to admin_forum_section_path(@section), notice: "Section updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @section.destroy!
        redirect_to admin_forum_sections_path, notice: "Section deleted."
      end

      private

      def set_section
        @section = ::Community::Section.find(params[:id])
      end

      def section_params
        params.expect(section: %i[name slug description position forum_category_id parent_id permissions])[:section]
      end
    end
  end
end
