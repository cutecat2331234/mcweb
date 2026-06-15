# frozen_string_literal: true

module Admin
  module Forum
    class TagGroupsController < BaseController
      before_action -> { require_permission("forum.tags.manage") }
      before_action :set_tag_group, only: %i[edit update destroy]

      def index
        groups = Community::TagGroup.ordered.includes(:tags)

        render inertia: "Admin/Generic/Index", props: {
          title: "标签组",
          columns: [
            { key: "name", label: "名称" },
            { key: "slug", label: "标识" },
            { key: "tags_count", label: "标签数" },
            { key: "one_per_topic", label: "每主题限一" }
          ],
          rows: groups.map do |group|
            {
              id: group.id,
              name: group.name,
              slug: group.slug,
              tags_count: group.tags.count,
              one_per_topic: group.one_per_topic? ? "是" : "否",
              url: edit_admin_forum_tag_group_path(group)
            }
          end,
          actions: [ { label: "新建标签组", href: new_admin_forum_tag_group_path } ]
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
          redirect_to admin_forum_tag_groups_path, notice: "标签组已创建。"
        else
          render inertia: "Admin/Forum/TagGroups/Form", props: form_props(group), status: :unprocessable_entity
        end
      end

      def update
        if @tag_group.update(tag_group_params)
          sync_tags!(@tag_group)
          redirect_to admin_forum_tag_groups_path, notice: "标签组已更新。"
        else
          render inertia: "Admin/Forum/TagGroups/Form", props: form_props(@tag_group), status: :unprocessable_entity
        end
      end

      def destroy
        @tag_group.destroy!
        redirect_to admin_forum_tag_groups_path, notice: "标签组已删除。"
      end

      private

      def set_tag_group
        @tag_group = Community::TagGroup.find(params[:id])
      end

      def tag_group_params
        params.require(:tag_group).permit(:name, :slug, :description, :one_per_topic)
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
          title: group.persisted? ? "编辑标签组" : "新建标签组",
          tagGroup: {
            id: group.id,
            name: group.name || "",
            slug: group.slug || "",
            description: group.description || "",
            one_per_topic: group.one_per_topic || false,
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
