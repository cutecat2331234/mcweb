# frozen_string_literal: true

module Admin
  module Forum
    class SectionsController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_section, only: %i[show edit update]

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
          end,
          actions: [{ label: "新建板块", href: new_admin_forum_section_path }]
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @section.name,
          subtitle: @section.slug,
          fields: [
            { label: "分类", value: @section.category&.name || "—" },
            { label: "描述", value: @section.description || "—" },
            { label: "排序", value: @section.position.to_s },
            { label: "发帖权限", value: permission_label(@section.permissions["create_topic"]) },
            { label: "回复权限", value: permission_label(@section.permissions["reply"]) }
          ],
          backUrl: admin_forum_sections_path,
          actions: [{ label: "编辑", href: edit_admin_forum_section_path(@section) }]
        }
      end

      def new
        render inertia: "Admin/Forum/Sections/Form", props: form_props(::Community::Section.new)
      end

      def create
        section = ::Community::Section.new(section_params)
        if section.save
          redirect_to admin_forum_section_path(section), notice: "板块已创建。"
        else
          render inertia: "Admin/Forum/Sections/Form", props: form_props(section), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/Sections/Form", props: form_props(@section)
      end

      def update
        if @section.update(section_params)
          redirect_to admin_forum_section_path(@section), notice: "板块已更新。"
        else
          render inertia: "Admin/Forum/Sections/Form", props: form_props(@section), status: :unprocessable_entity
        end
      end

      private

      def set_section
        @section = ::Community::Section.find(params[:id])
      end

      def section_params
        permitted = params.require(:section).permit(
          :name, :slug, :description, :position, :forum_category_id, :parent_id,
          :create_topic_roles, :reply_roles, :prefixes
        )
        prefixes = if permitted[:prefixes].is_a?(String)
                     permitted[:prefixes].lines.map(&:strip).reject(&:blank?)
                   else
                     Array(permitted[:prefixes])
                   end
        {
          name: permitted[:name],
          slug: permitted[:slug],
          description: permitted[:description],
          position: permitted[:position],
          forum_category_id: permitted[:forum_category_id],
          parent_id: permitted[:parent_id],
          prefixes: prefixes,
          permissions: {
            "create_topic" => parse_roles(permitted[:create_topic_roles]),
            "reply" => parse_roles(permitted[:reply_roles])
          }.reject { |_, roles| roles.empty? }
        }
      end

      def parse_roles(raw)
        raw.to_s.split(/[,\s]+/).map(&:strip).reject(&:blank?)
      end

      def permission_label(roles)
        roles.present? ? Array(roles).join(", ") : "所有人"
      end

      def form_props(section)
        {
          title: section.persisted? ? "编辑板块" : "新建板块",
          section: {
            id: section.id,
            name: section.name || "",
            slug: section.slug || "",
            description: section.description || "",
            position: section.position || 0,
            forum_category_id: section.forum_category_id,
            parent_id: section.parent_id,
            prefixes: Array(section.prefixes).join("\n"),
            create_topic_roles: Array(section.permissions["create_topic"]).join(", "),
            reply_roles: Array(section.permissions["reply"]).join(", ")
          },
          categories: ::Community::Category.order(:name).map { |c| { id: c.id, name: c.name } },
          parentSections: ::Community::Section.roots.where.not(id: section.id).order(:name).map { |s| { id: s.id, name: s.name } },
          submitUrl: section.persisted? ? admin_forum_section_path(section) : admin_forum_sections_path,
          method: section.persisted? ? "patch" : "post",
          backUrl: admin_forum_sections_path
        }
      end
    end
  end
end
