# frozen_string_literal: true

module Admin
  module Forum
    class SectionsController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_section, only: %i[show edit update]

      def index
        sections = ::Community::Section.ordered.includes(:category)

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("sections.title"),
          columns: [
            admin_column(:name, t("mcweb.admin.forum.col_name"), link: true),
            admin_column(:slug, t("mcweb.admin.forum.col_slug")),
            admin_column(:category, t("mcweb.admin.forum.col_category"))
          ],
          rows: sections.map do |section|
            admin_row(
              name: section.name,
              slug: section.slug,
              category: section.category&.name,
              url: admin_forum_section_path(section)
            )
          end,
          actions: [ { label: t("mcweb.admin.forum.action_new_section"), href: new_admin_forum_section_path } ]
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @section.name,
          subtitle: @section.slug,
          fields: [
            { label: forum_t("sections.field_category"), value: @section.category&.name || forum_na },
            { label: t("mcweb.admin.forum.field_description"), value: @section.description || forum_na },
            { label: t("mcweb.admin.forum.col_position"), value: @section.position.to_s },
            { label: forum_t("sections.field_create_permission"), value: forum_permission_label(@section.permissions["create_topic"]) },
            { label: forum_t("sections.field_reply_permission"), value: forum_permission_label(@section.permissions["reply"]) },
            { label: forum_t("sections.field_required_tags"), value: forum_list_join(@section.required_tags.pluck(:name)).presence || forum_na },
            { label: forum_t("sections.field_required_tag_groups"), value: forum_list_join(@section.required_tag_groups.pluck(:name)).presence || forum_na },
            { label: forum_t("sections.field_allowed_tags"), value: forum_list_join(@section.allowed_tags.pluck(:name)).presence || forum_na },
            { label: forum_t("sections.field_prefix_required"), value: forum_yes_no(@section.prefix_required?) },
            { label: forum_t("sections.field_min_trust_create"), value: @section.min_trust_level_create.to_i },
            { label: forum_t("sections.field_min_trust_reply"), value: @section.min_trust_level_reply.to_i },
            { label: forum_t("sections.field_read_only"), value: forum_yes_no(@section.read_only?) },
            { label: forum_t("sections.field_login_required"), value: forum_yes_no(@section.login_required?) },
            { label: t("mcweb.admin.forum.field_color"), value: @section.color_hex.presence || forum_na },
            { label: t("mcweb.admin.forum.field_icon"), value: @section.icon.presence || forum_na },
            { label: forum_t("sections.field_banner"), value: @section.banner_text.presence || forum_na },
            { label: forum_t("sections.field_link_url"), value: @section.link_url.presence || forum_na },
            { label: forum_t("sections.field_default_notification"), value: section_notification_label(@section.default_notification_level) },
            { label: forum_t("sections.field_moderators"), value: forum_list_join(@section.moderators.order(:username).pluck(:username)).presence || forum_na }
          ],
          backUrl: admin_forum_sections_path,
          actions: [ { label: t("mcweb.admin.forum.action_edit"), href: edit_admin_forum_section_path(@section) } ]
        }
      end

      def new
        render inertia: "Admin/Forum/Sections/Form", props: form_props(::Community::Section.new)
      end

      def create
        section = ::Community::Section.new(section_params)
        if section.save
          mod_result = sync_section_moderators(section)
          notice = t("mcweb.flash.created", resource: t("mcweb.resources.section"))
          notice = "#{notice} #{mod_result.error}" if mod_result&.failure?
          redirect_to admin_forum_section_path(section), notice: notice
        else
          render inertia: "Admin/Forum/Sections/Form", props: form_props(section), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/Sections/Form", props: form_props(@section)
      end

      def update
        if @section.update(section_params)
          mod_result = sync_section_moderators(@section)
          notice = t("mcweb.flash.updated", resource: t("mcweb.resources.section"))
          notice = "#{notice} #{mod_result.error}" if mod_result&.failure?
          redirect_to admin_forum_section_path(@section), notice: notice
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
          :min_trust_level_create, :min_trust_level_reply, :read_only, :login_required, :color_hex, :icon, :banner_text, :link_url, :link_label,
          :default_notification_level, :seo_title, :seo_description,
          required_tag_ids: [], allowed_tag_ids: [], default_tag_ids: [], required_tag_group_ids: []
        )
        prefixes = if permitted[:prefixes].is_a?(String)
                     Community::SectionPrefixes.parse_form(permitted[:prefixes])
        elsif permitted[:prefixes].is_a?(Array)
                     Community::SectionPrefixes.normalize(permitted[:prefixes])
        else
                     []
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
          login_required: ActiveModel::Type::Boolean.new.cast(permitted[:login_required]),
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

      def sync_section_moderators(section)
        return ServiceResult.success unless params.dig(:section, :moderator_usernames)

        Community::SyncSectionModerators.call(
          section: section,
          usernames: params.dig(:section, :moderator_usernames)
        )
      end

      def form_props(section)
        {
          title: section.persisted? ? forum_t("sections.form_edit") : forum_t("sections.form_new"),
          section: {
            id: section.id,
            name: section.name || "",
            slug: section.slug || "",
            description: section.description || "",
            position: section.position || 0,
            forum_category_id: section.forum_category_id,
            parent_id: section.parent_id,
            prefixes: Community::SectionPrefixes.to_form_text(section.prefixes),
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
            login_required: section.login_required?,
            color_hex: section.color_hex || "",
            icon: section.icon || "",
            banner_text: section.banner_text || "",
            link_url: section.link_url || "",
            link_label: section.link_label || "",
            seo_title: section.seo["title"].to_s,
            seo_description: section.seo["description"].to_s,
            default_notification_level: section.default_notification_level.presence || "watching",
            moderator_usernames: section.moderators.order(:username).pluck(:username).join(", ")
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
