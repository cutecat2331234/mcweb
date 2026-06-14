# frozen_string_literal: true

module Admin
  module Forum
    class SectionsController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_section, only: %i[show edit update destroy]

      def index
        sections = ::Community::Section.ordered.includes(:category)

        render inertia: "Admin/Generic/Index", props: {
          title: "论坛板块",
          columns: [
            admin_column(:name, "名称", link: true),
            admin_column(:slug, "标识"),
            admin_column(:category, "分类")
          ],
          rows: sections.map do |section|
            admin_row(
              name: section.name,
              slug: section.slug,
              category: section.category&.name,
              url: admin_forum_section_path(section)
            )
          end
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @section.name,
          subtitle: @section.slug,
          fields: [
            { label: "分类", value: @section.category&.name || "—" },
            { label: "描述", value: @section.description || "—" },
            { label: "排序", value: @section.position.to_s }
          ],
          backUrl: admin_forum_sections_path
        }
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
