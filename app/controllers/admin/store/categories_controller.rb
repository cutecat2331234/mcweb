# frozen_string_literal: true

module Admin
  module Store
    class CategoriesController < BaseController
      before_action -> { require_permission("store.products.manage") }
      before_action :set_category, only: %i[show edit update destroy]

      def index
        categories = ::Commerce::Category.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.store.categories.title"),
          columns: [
            admin_column(:name, t("mcweb.admin.store.categories.col_name"), link: true),
            admin_column(:slug, t("mcweb.admin.store.categories.col_slug")),
            admin_column(:position, t("mcweb.admin.store.categories.col_position"))
          ],
          rows: categories.map do |category|
            admin_row(
              name: category.name,
              slug: category.slug,
              position: category.position.to_s,
              url: admin_store_category_path(category)
            )
          end,
          actions: [ { label: t("mcweb.admin.store.categories.new"), href: new_admin_store_category_path } ]
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @category.name,
          fields: [
            { label: t("mcweb.admin.store.categories.field_slug"), value: @category.slug },
            { label: t("mcweb.admin.store.categories.field_position"), value: @category.position.to_s },
            { label: t("mcweb.admin.store.categories.field_description"), value: @category.description.presence || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.store.categories.field_icon"), value: @category.icon.presence || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.store.categories.field_color"), value: @category.color_hex.presence || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.store.categories.field_seo_title"), value: @category.seo["title"].presence || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.store.categories.field_seo_description"), value: @category.seo["description"].presence || t("mcweb.labels.not_available") }
          ],
          backUrl: admin_store_categories_path,
          actions: [ { label: t("mcweb.admin.store.action_edit"), href: edit_admin_store_category_path(@category) } ]
        }
      end

      def new
        render inertia: "Admin/Store/Categories/Form", props: form_props(::Commerce::Category.new)
      end

      def create
        category = ::Commerce::Category.new(category_params)
        if category.save
          redirect_to admin_store_category_path(category), notice: t("mcweb.flash.created", resource: t("mcweb.resources.category"))
        else
          render inertia: "Admin/Store/Categories/Form", props: form_props(category), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Store/Categories/Form", props: form_props(@category)
      end

      def update
        if @category.update(category_params)
          redirect_to admin_store_category_path(@category), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.category"))
        else
          render inertia: "Admin/Store/Categories/Form", props: form_props(@category), status: :unprocessable_entity
        end
      end

      def destroy
        @category.destroy!
        redirect_to admin_store_categories_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.category"))
      end

      private

      def set_category
        @category = ::Commerce::Category.find(params[:id])
      end

      def category_params
        permitted = params.require(:category).permit(
          :name, :slug, :position, :description, :icon, :color_hex, :seo_title, :seo_description
        )
        if permitted.key?(:seo_title) || permitted.key?(:seo_description)
          permitted[:seo] = {
            "title" => permitted.delete(:seo_title).to_s.presence,
            "description" => permitted.delete(:seo_description).to_s.presence
          }.compact
        end
        permitted
      end

      def form_props(category)
        {
          title: category.persisted? ? t("mcweb.admin.store.categories.edit") : t("mcweb.admin.store.categories.new"),
          category: {
            id: category.id,
            name: category.name || "",
            slug: category.slug || "",
            position: category.position || 0,
            description: category.description || "",
            icon: category.icon || "",
            color_hex: category.color_hex || "",
            seo_title: category.seo&.dig("title").to_s,
            seo_description: category.seo&.dig("description").to_s
          },
          submitUrl: category.persisted? ? admin_store_category_path(category) : admin_store_categories_path,
          method: category.persisted? ? "patch" : "post",
          backUrl: admin_store_categories_path
        }
      end
    end
  end
end
