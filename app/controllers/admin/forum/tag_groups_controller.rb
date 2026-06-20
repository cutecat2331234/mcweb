# frozen_string_literal: true

module Admin
  module Forum
    class TagGroupsController < BaseController
      before_action -> { require_permission("forum.tags.manage") }
      before_action :set_tag_group, only: %i[edit update destroy]

      def index
        groups = Community::TagGroup.ordered.includes(:tags)

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("tag_groups.title"),
          columns: [
            { key: "name", label: t("mcweb.admin.forum.col_name") },
            { key: "slug", label: t("mcweb.admin.forum.col_slug") },
            { key: "tags_count", label: forum_t("tag_groups.col_tags_count") },
            { key: "one_per_topic", label: forum_t("tag_groups.col_one_per_topic") },
            { key: "color_hex", label: forum_t("tag_groups.col_color") }
          ],
          rows: groups.map do |group|
            {
              id: group.id,
              name: group.name,
              slug: group.slug,
              tags_count: group.tags.count,
              one_per_topic: forum_yes_no(group.one_per_topic?),
              color_hex: group.color_hex.presence || forum_na,
              url: edit_admin_forum_tag_group_path(group)
            }
          end,
          actions: [ { label: forum_t("tag_groups.action_new"), href: new_admin_forum_tag_group_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/TagGroups/Form", props: form_props(Community::TagGroup.new)
      end

      def edit
        render inertia: "Admin/Forum/TagGroups/Form", props: form_props(@tag_group)
      end

      def create
        group = Community::TagGroup.new(tag_group_params)
        if group.save
          sync_tags!(group)
          redirect_to admin_forum_tag_groups_path, notice: t("mcweb.flash.created", resource: t("mcweb.resources.tag_group"))
        else
          render inertia: "Admin/Forum/TagGroups/Form", props: form_props(group), status: :unprocessable_entity
        end
      end

      def update
        if @tag_group.update(tag_group_params)
          sync_tags!(@tag_group)
          redirect_to admin_forum_tag_groups_path, notice: t("mcweb.flash.updated", resource: t("mcweb.resources.tag_group"))
        else
          render inertia: "Admin/Forum/TagGroups/Form", props: form_props(@tag_group), status: :unprocessable_entity
        end
      end

      def destroy
        @tag_group.destroy!
        redirect_to admin_forum_tag_groups_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.tag_group"))
      end

      private

      def set_tag_group
        @tag_group = Community::TagGroup.find(params[:id])
      end

      def tag_group_params
        params.require(:tag_group).permit(:name, :slug, :description, :one_per_topic, :color_hex)
      end

      def sync_tags!(group)
        ids = Array(params.dig(:tag_group, :tag_ids)).map(&:to_i).reject(&:zero?)
        group.memberships.where.not(forum_tag_id: ids).destroy_all
        ids.each do |tag_id|
          Community::TagGroupMembership.find_or_create_by!(tag_group: group, tag_id: tag_id)
        end
      end

      def form_props(group)
        {
          title: group.persisted? ? forum_t("tag_groups.form_edit") : forum_t("tag_groups.form_new"),
          tagGroup: {
            id: group.id,
            name: group.name || "",
            slug: group.slug || "",
            description: group.description || "",
            one_per_topic: group.one_per_topic || false,
            color_hex: group.color_hex || "",
            tag_ids: group.persisted? ? group.tag_ids : []
          },
          tags: Community::Tag.ordered.map { |t| { id: t.id, name: t.name } },
          submitUrl: group.persisted? ? admin_forum_tag_group_path(group) : admin_forum_tag_groups_path,
          method: group.persisted? ? "patch" : "post",
          backUrl: admin_forum_tag_groups_path
        }
      end
    end
  end
end
