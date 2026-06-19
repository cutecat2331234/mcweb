# frozen_string_literal: true

module Admin
  module Forum
    class CategoriesController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_category, only: %i[show edit update destroy]

      def index
        categories = ::Community::Category.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: "论坛分类",
          columns: [
            admin_column(:name, "名称", link: true),
            admin_column(:slug, "标识"),
            admin_column(:position, "排序")
          ],
          rows: categories.map do |category|
            admin_row(
              name: category.name,
              slug: category.slug,
              position: category.position.to_s,
              url: admin_forum_category_path(category)
            )
          end,
          actions: [ { label: "新建分类", href: new_admin_forum_category_path } ]
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @category.name,
          fields: [
            { label: "标识", value: @category.slug },
            { label: "排序", value: @category.position.to_s },
            { label: "颜色", value: @category.color_hex.presence || "—" },
            { label: "图标", value: @category.icon.presence || "—" },
            { label: "描述", value: @category.description.presence || "—" },
            { label: "板块数", value: @category.sections.count.to_s }
          ],
          backUrl: admin_forum_categories_path,
          actions: [ { label: "编辑", href: edit_admin_forum_category_path(@category) } ]
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
          title: category.persisted? ? "编辑分类" : "新建分类",
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
