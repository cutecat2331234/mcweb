# frozen_string_literal: true

module Admin
  module Forum
    class CategoriesController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_category, only: %i[show edit update destroy]

      def index
        categories = ::Community::Category.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.forum.categories.title"),
          columns: [
            admin_column(:name, t("mcweb.admin.forum.col_name"), link: true),
            admin_column(:slug, t("mcweb.admin.forum.col_slug")),
            admin_column(:position, t("mcweb.admin.forum.col_position"))
          ],
          rows: categories.map do |category|
            admin_row(
              name: category.name,
              slug: category.slug,
              position: category.position.to_s,
              url: admin_forum_category_path(category)
            )
          end,
          actions: [ { label: t("mcweb.admin.forum.action_new_category"), href: new_admin_forum_category_path } ]
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @category.name,
          fields: [
            { label: t("mcweb.admin.forum.field_slug"), value: @category.slug },
            { label: t("mcweb.admin.forum.field_position"), value: @category.position.to_s },
            { label: t("mcweb.admin.forum.field_color"), value: @category.color_hex.presence || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.forum.field_icon"), value: @category.icon.presence || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.forum.field_description"), value: @category.description.presence || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.forum.field_sections_count"), value: @category.sections.count.to_s }
          ],
          backUrl: admin_forum_categories_path,
          actions: [ { label: t("mcweb.admin.forum.action_edit"), href: edit_admin_forum_category_path(@category) } ]
        }
      end

      def new
        render inertia: "Admin/Forum/Categories/Form", props: form_props(::Community::Category.new)
      end

      def create
        category = ::Community::Category.new(category_attributes)
        if category.save
          redirect_to admin_forum_category_path(category), notice: t("mcweb.flash.created", resource: t("mcweb.resources.category"))
        else
          render inertia: "Admin/Forum/Categories/Form", props: form_props(category), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/Categories/Form", props: form_props(@category)
      end

      def update
        if @category.update(category_attributes)
          redirect_to admin_forum_category_path(@category), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.category"))
        else
          render inertia: "Admin/Forum/Categories/Form", props: form_props(@category), status: :unprocessable_entity
        end
      end

      def destroy
        if @category.sections.exists?
          redirect_to admin_forum_categories_path, alert: t("mcweb.flash.category_has_sections")
        else
          @category.destroy!
          redirect_to admin_forum_categories_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.category"))
        end
      end

      private

      def set_category
        @category = ::Community::Category.find(params[:id])
      end

      def category_params
        params.require(:category).permit(:name, :slug, :position, :color_hex, :icon, :description, :seo_title, :seo_description)
      end

      def form_props(category)
        {
          title: category.persisted? ? t("mcweb.admin.forum.form_edit_category") : t("mcweb.admin.forum.form_new_category"),
          category: {
            id: category.id,
            name: category.name || "",
            slug: category.slug || "",
            position: category.position || 0,
            color_hex: category.color_hex || "",
            icon: category.icon || "",
            description: category.description || "",
            seo_title: category.seo["title"].to_s,
            seo_description: category.seo["description"].to_s
          },
          submitUrl: category.persisted? ? admin_forum_category_path(category) : admin_forum_categories_path,
          method: category.persisted? ? "patch" : "post",
          backUrl: admin_forum_categories_path
        }
      end

      def category_attributes
        attrs = category_params.to_h
        seo = {
          "title" => attrs.delete("seo_title"),
          "description" => attrs.delete("seo_description")
        }.compact
        attrs[:seo] = seo if seo.any?
        attrs
      end
    end
  end
end
