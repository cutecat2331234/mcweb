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
          actions: [ { label: "新建板块", href: new_admin_forum_section_path } ]
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
            { label: "回复权限", value: permission_label(@section.permissions["reply"]) },
            { label: "必填标签", value: @section.required_tags.pluck(:name).join("、").presence || "—" },
            { label: "必填标签组", value: @section.required_tag_groups.pluck(:name).join("、").presence || "—" },
            { label: "允许标签", value: @section.allowed_tags.pluck(:name).join("、").presence || "—" },
            { label: "前缀必填", value: @section.prefix_required? ? "是" : "否" },
            { label: "最低发帖信任等级", value: @section.min_trust_level_create.to_i },
            { label: "最低回复信任等级", value: @section.min_trust_level_reply.to_i },
            { label: "只读分区", value: @section.read_only? ? "是" : "否" },
            { label: "颜色", value: @section.color_hex.presence || "—" },
            { label: "图标", value: @section.icon.presence || "—" },
            { label: "公告横幅", value: @section.banner_text.presence || "—" },
            { label: "外链", value: @section.link_url.presence || "—" },
            { label: "默认订阅级别", value: @section.default_notification_level == "tracking" ? "跟踪" : "关注" }
          ],
          backUrl: admin_forum_sections_path,
          actions: [ { label: "编辑", href: edit_admin_forum_section_path(@section) } ]
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
          :create_topic_roles, :reply_roles, :prefixes, :prefix_required, :topic_template,
          :min_trust_level_create, :min_trust_level_reply, :read_only, :color_hex, :icon, :banner_text, :link_url, :link_label,
          :default_notification_level, :seo_title, :seo_description,
          required_tag_ids: [], allowed_tag_ids: [], default_tag_ids: [], required_tag_group_ids: []
        )
        prefixes = if permitted[:prefixes].is_a?(String)
                     permitted[:prefixes].lines.map(&:strip).reject(&:blank?)
        else
                     Array(permitted[:prefixes])
        end
        required_tag_ids = Array(permitted[:required_tag_ids]).map(&:to_i).reject(&:zero?).uniq
        allowed_tag_ids = Array(permitted[:allowed_tag_ids]).map(&:to_i).reject(&:zero?).uniq
        default_tag_ids = Array(permitted[:default_tag_ids]).map(&:to_i).reject(&:zero?).uniq
        required_tag_group_ids = Array(permitted[:required_tag_group_ids]).map(&:to_i).reject(&:zero?).uniq
        {
          name: permitted[:name],
          slug: permitted[:slug],
          description: permitted[:description],
          position: permitted[:position],
          forum_category_id: permitted[:forum_category_id],
          parent_id: permitted[:parent_id],
          prefixes: prefixes,
          required_tag_ids: required_tag_ids,
          allowed_tag_ids: allowed_tag_ids,
          default_tag_ids: default_tag_ids,
          required_tag_group_ids: required_tag_group_ids,
          prefix_required: ActiveModel::Type::Boolean.new.cast(permitted[:prefix_required]),
          topic_template: permitted[:topic_template],
          min_trust_level_create: permitted[:min_trust_level_create].to_i,
          min_trust_level_reply: permitted[:min_trust_level_reply].to_i,
          read_only: ActiveModel::Type::Boolean.new.cast(permitted[:read_only]),
          color_hex: permitted[:color_hex].to_s.strip.presence,
          icon: permitted[:icon].to_s.strip.presence,
          banner_text: permitted[:banner_text].to_s.strip.presence,
          link_url: permitted[:link_url].to_s.strip.presence,
          link_label: permitted[:link_label].to_s.strip.presence,
          default_notification_level: permitted[:default_notification_level].presence_in(Community::Subscription::NOTIFICATION_LEVELS) || "watching",
          seo: {
            "title" => permitted[:seo_title].to_s.strip.presence,
            "description" => permitted[:seo_description].to_s.strip.presence
          }.compact,
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
            reply_roles: Array(section.permissions["reply"]).join(", "),
            required_tag_ids: Array(section.required_tag_ids).map(&:to_i),
            allowed_tag_ids: Array(section.allowed_tag_ids).map(&:to_i),
            default_tag_ids: Array(section.default_tag_ids).map(&:to_i),
            required_tag_group_ids: Array(section.required_tag_group_ids).map(&:to_i),
            prefix_required: section.prefix_required?,
            topic_template: section.topic_template || "",
            min_trust_level_create: section.min_trust_level_create.to_i,
            min_trust_level_reply: section.min_trust_level_reply.to_i,
            read_only: section.read_only?,
            color_hex: section.color_hex || "",
            icon: section.icon || "",
            banner_text: section.banner_text || "",
            link_url: section.link_url || "",
            link_label: section.link_label || "",
            seo_title: section.seo["title"].to_s,
            seo_description: section.seo["description"].to_s,
            default_notification_level: section.default_notification_level.presence || "watching"
          },
          tags: ::Community::Tag.order(:name).map { |tag| { id: tag.id, name: tag.name } },
          tagGroups: ::Community::TagGroup.ordered.map { |g| { id: g.id, name: g.name } },
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
