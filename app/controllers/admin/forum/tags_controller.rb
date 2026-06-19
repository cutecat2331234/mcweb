# frozen_string_literal: true

module Admin
  module Forum
    class TagsController < BaseController
      before_action -> { require_permission("forum.tags.manage") }
      before_action :set_tag, only: %i[edit update destroy]

      def index
        tags = Community::Tag.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: "论坛标签",
          columns: [
            { key: "name", label: "名称" },
            { key: "slug", label: "标识" },
            { key: "topics_count", label: "主题数" },
            { key: "staff_only", label: "仅工作人员" }
          ],
          rows: tags.map do |tag|
            {
              id: tag.id,
              name: tag.name,
              slug: tag.slug,
              topics_count: tag.topics.count,
              staff_only: tag.staff_only? ? "是" : "否",
              url: edit_admin_forum_tag_path(tag)
            }
          end,
          actions: [ { label: "新建标签", href: new_admin_forum_tag_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/Tags/Form", props: form_props(Community::Tag.new)
      end

      def edit
        render inertia: "Admin/Forum/Tags/Form", props: form_props(@tag)
      end

      def create
        tag = Community::Tag.new(tag_params)
        if tag.save
          redirect_to admin_forum_tags_path, notice: t("mcweb.flash.created", resource: t("mcweb.resources.tag"))
        else
          render inertia: "Admin/Forum/Tags/Form", props: form_props(tag), status: :unprocessable_entity
        end
      end

      def update
        if @tag.update(tag_params)
          redirect_to admin_forum_tags_path, notice: t("mcweb.flash.updated", resource: t("mcweb.resources.tag"))
        else
          render inertia: "Admin/Forum/Tags/Form", props: form_props(@tag), status: :unprocessable_entity
        end
      end

      def destroy
        @tag.destroy!
        redirect_to admin_forum_tags_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.tag"))
      end

      private

      def set_tag
        @tag = Community::Tag.find(params[:id])
      end

      def tag_params
        params.require(:tag).permit(:name, :slug, :description, :staff_only, :color_hex, :canonical_tag_id)
      end

      def form_props(tag)
        canonical_options = Community::Tag.where.not(id: tag.id).where(canonical_tag_id: nil).ordered.map do |t|
          { id: t.id, name: t.name }
        end
        {
          title: tag.persisted? ? "编辑标签" : "新建标签",
          tag: {
            id: tag.id,
            name: tag.name || "",
            slug: tag.slug || "",
            description: tag.description || "",
            staff_only: tag.staff_only || false,
            color_hex: tag.color_hex || "",
            canonical_tag_id: tag.canonical_tag_id
          },
          canonicalTags: canonical_options,
          submitUrl: tag.persisted? ? admin_forum_tag_path(tag) : admin_forum_tags_path,
          method: tag.persisted? ? "patch" : "post",
          backUrl: admin_forum_tags_path
        }
      end
    end
  end
end
