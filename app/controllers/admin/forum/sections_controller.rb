# frozen_string_literal: true

module Admin
  module Forum
    class SectionsController < BaseController
      SECTION_BROWSE_PERMISSIONS = %w[
        forum.sections.manage forum.sections.lifecycle forum.sections.delete
      ].freeze

      before_action :require_section_browse_permission, only: %i[index show lifecycle]
      before_action -> { require_permission("forum.sections.manage") },
        only: %i[new create edit update]
      before_action -> { require_permission("forum.sections.lifecycle") },
        only: %i[archive restore migrate_topics]
      before_action -> { require_permission("forum.topics.move") },
        only: %i[migrate_topics]
      before_action -> { require_permission("forum.sections.delete") },
        only: %i[destroy]
      before_action :set_section, only: %i[show edit update lifecycle archive restore migrate_topics destroy]

      def index
        all_sections = ::Community::Section.ordered.includes(:category).to_a
        selected_status = params[:status].presence_in(section_statuses) || "all"
        sections = if selected_status == "all"
          all_sections
        else
          all_sections.select { |section| section.lifecycle_status.to_s == selected_status }
        end
        topic_counts = ::Community::Topic.where(forum_section_id: all_sections.map(&:id)).group(:forum_section_id).count
        status_counts = all_sections.group_by { |section| section.lifecycle_status.to_s }.transform_values(&:size)

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("sections.title"),
          columns: [
            admin_column(:name, t("mcweb.admin.forum.col_name"), link: true),
            admin_column(:slug, t("mcweb.admin.forum.col_slug")),
            admin_column(:category, t("mcweb.admin.forum.col_category")),
            admin_column(:status, forum_t("sections.field_status")),
            admin_column(:topics, forum_t("sections.field_topics_count"))
          ],
          rows: sections.map do |section|
            admin_row(
              name: section.name,
              slug: section.slug,
              category: section.category&.name,
              status: section_status_label(section),
              topics: topic_counts.fetch(section.id, 0).to_s,
              url: admin_forum_section_path(section.id)
            )
          end,
          actions: section_index_actions,
          statusTabs: section_status_tabs(selected_status, status_counts, all_sections.length)
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @section.name,
          subtitle: @section.slug,
          fields: [
            { label: forum_t("sections.field_category"), value: @section.category&.name || forum_na },
            { label: forum_t("sections.field_status"), value: section_status_label(@section) },
            { label: forum_t("sections.field_archived_at"), value: @section.archived_at ? l(@section.archived_at, format: :short) : forum_na },
            { label: forum_t("sections.field_archived_by"), value: @section.archived_by&.username || forum_na },
            { label: forum_t("sections.field_archived_reason"), value: @section.archived_reason.presence || forum_na },
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
          actions: section_show_actions
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
          redirect_to admin_forum_section_path(section.id), notice: notice
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
          redirect_to admin_forum_section_path(@section.id), notice: notice
        else
          render inertia: "Admin/Forum/Sections/Form", props: form_props(@section), status: :unprocessable_entity
        end
      end

      def lifecycle
        impact = ::Community::SectionLifecycleImpact.call(section: @section)
        archived_ancestor = @section.archived_ancestor

        render inertia: "Admin/Forum/Sections/Lifecycle", props: {
          title: forum_t("sections.lifecycle_title", name: @section.name),
          section: {
            id: @section.id,
            name: @section.name,
            slug: @section.slug,
            archived: @section.self_archived?,
            self_archived: @section.self_archived?,
            inherited_archived: @section.inherited_archived?,
            effectively_active: @section.publicly_active?,
            lifecycle_status: @section.lifecycle_status.to_s,
            archived_ancestor: archived_ancestor && {
              id: archived_ancestor.id,
              name: archived_ancestor.name,
              slug: archived_ancestor.slug,
              lifecycle_url: lifecycle_admin_forum_section_path(archived_ancestor.id)
            },
            archived_at: @section.archived_at&.iso8601,
            archived_by: @section.archived_by&.username,
            archived_reason: @section.archived_reason
          },
          impact: impact,
          destroyBlockers: destroy_blockers(impact),
          archiveUrl: archive_admin_forum_section_path(@section.id),
          restoreUrl: restore_admin_forum_section_path(@section.id),
          destroyUrl: admin_forum_section_path(@section.id),
          migrateTopicsUrl: migrate_topics_admin_forum_section_path(@section.id),
          migrationTargets: migration_targets,
          canManageLifecycle: current_user.permission?("forum.sections.lifecycle"),
          canMigrateTopics: current_user.permission?("forum.sections.lifecycle") &&
            current_user.permission?("forum.topics.move") && !@section.publicly_active?,
          canDelete: current_user.permission?("forum.sections.delete"),
          confirmations: {
            archive: lifecycle_confirmation("archive"),
            restore: lifecycle_confirmation("restore"),
            destroy: lifecycle_confirmation("destroy")
          },
          backUrl: admin_forum_section_path(@section.id)
        }
      end

      def archive
        run_lifecycle_operation("archive")
      end

      def restore
        run_lifecycle_operation("restore")
      end

      def migrate_topics
        target = ::Community::Section.find_by(id: params[:target_section_id])
        unless target
          redirect_to lifecycle_admin_forum_section_path(@section.id),
            alert: forum_t("sections.migration_target_required")
          return
        end

        result = ::Community::MigrateArchivedSectionTopics.call(
          source_section: @section,
          target_section: target,
          actor: current_user,
          reason: params[:reason],
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          request_id: request.request_id
        )

        if result.success?
          redirect_to lifecycle_admin_forum_section_path(@section.id),
            notice: forum_t(
              "sections.migration_success",
              count: result.value.fetch(:moved_topics).length,
              target: result.value.fetch(:target_section).name
            )
        else
          redirect_to lifecycle_admin_forum_section_path(@section.id), alert: result.error
        end
      end

      def destroy
        run_lifecycle_operation("destroy")
      end

      private

      def require_section_browse_permission
        require_login
        return if performed?
        return if SECTION_BROWSE_PERMISSIONS.any? { |permission| current_user.permission?(permission) }

        redirect_to root_path, alert: t("mcweb.flash.permission_denied")
      end

      def set_section
        @section = ::Community::Section.find(params[:id])
      end

      def run_lifecycle_operation(operation)
        result = ::Community::ManageSectionLifecycle.call(
          section: @section,
          actor: current_user,
          operation: operation,
          reason: params[:reason],
          confirmation: params[:confirmation],
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          request_id: request.request_id
        )

        if result.success?
          if operation == "destroy"
            redirect_to admin_forum_sections_path, notice: forum_t("sections.lifecycle_success_destroy")
          else
            redirect_to lifecycle_admin_forum_section_path(@section.id),
              notice: forum_t("sections.lifecycle_success_#{operation}")
          end
        else
          redirect_to lifecycle_admin_forum_section_path(@section.id), alert: result.error
        end
      end

      def lifecycle_confirmation(operation)
        ::Community::ManageSectionLifecycle.confirmation_for(
          section: @section,
          operation: operation
        )
      end

      def destroy_blockers(impact)
        blockers = []
        blockers << forum_t("sections.blocker_not_archived") if @section.archived_at.blank?
        blockers << forum_t("sections.blocker_descendants", count: impact.fetch(:descendants)) if impact.fetch(:descendants).positive?
        blockers << forum_t("sections.blocker_topics", count: impact.fetch(:topics)) if impact.fetch(:topics).positive?
        if impact.fetch(:moderation_cases).positive?
          blockers << forum_t("sections.blocker_moderation_cases", count: impact.fetch(:moderation_cases))
        end
        blockers
      end

      def section_statuses
        %w[effectively_active self_archived inherited_archived]
      end

      def section_status_label(section)
        forum_t("sections.status_#{section.lifecycle_status}")
      end

      def section_status_tabs(selected_status, status_counts, total)
        ([ "all" ] + section_statuses).map do |status|
          {
            label: forum_t("sections.filter_#{status}"),
            href: admin_forum_sections_path(status: status == "all" ? nil : status),
            active: selected_status == status,
            count: status == "all" ? total : status_counts.fetch(status, 0)
          }
        end
      end

      def section_show_actions
        actions = []
        if current_user.permission?("forum.sections.manage")
          actions << { label: t("mcweb.admin.forum.action_edit"), href: edit_admin_forum_section_path(@section.id) }
        end
        actions << {
          label: forum_t("sections.action_lifecycle"),
          href: lifecycle_admin_forum_section_path(@section.id),
          variant: "outline"
        }
        actions
      end

      def section_index_actions
        return [] unless current_user.permission?("forum.sections.manage")

        [ { label: t("mcweb.admin.forum.action_new_section"), href: new_admin_forum_section_path } ]
      end

      def migration_targets
        return [] unless current_user.permission?("forum.sections.lifecycle")
        return [] unless current_user.permission?("forum.topics.move")

        ::Community::Section.effectively_active.includes(:category).where.not(id: @section.id).order(:name).map do |section|
          {
            id: section.id,
            name: section.name,
            category: section.category&.name
          }
        end
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
          parentSections: ::Community::Section.active.roots.where.not(id: section.id).order(:name).map { |s| { id: s.id, name: s.name } },
          submitUrl: section.persisted? ? admin_forum_section_path(section.id) : admin_forum_sections_path,
          method: section.persisted? ? "patch" : "post",
          backUrl: admin_forum_sections_path
        }
      end
    end
  end
end
