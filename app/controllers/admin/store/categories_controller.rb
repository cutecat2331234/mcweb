# frozen_string_literal: true

module Admin
  module Store
    class CategoriesController < BaseController
      before_action -> { require_permission("store.products.manage") }
      before_action :set_category, only: %i[show edit update destroy]

      def index
        categories = ::Commerce::Category.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: "商品分类",
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
              url: admin_store_category_path(category)
            )
          end,
          actions: [{ label: "新建分类", href: new_admin_store_category_path }]
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @category.name,
          fields: [
            { label: "标识", value: @category.slug },
            { label: "排序", value: @category.position.to_s }
          ],
          backUrl: admin_store_categories_path,
          actions: [{ label: "编辑", href: edit_admin_store_category_path(@category) }]
        }
      end

      def new
        render inertia: "Admin/Store/Categories/Form", props: form_props(::Commerce::Category.new)
      end

      def create
        category = ::Commerce::Category.new(category_params)
        if category.save
          redirect_to admin_store_category_path(category), notice: "分类已创建。"
        else
          render inertia: "Admin/Store/Categories/Form", props: form_props(category), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Store/Categories/Form", props: form_props(@category)
      end

      def update
        if @category.update(category_params)
          redirect_to admin_store_category_path(@category), notice: "分类已更新。"
        else
          render inertia: "Admin/Store/Categories/Form", props: form_props(@category), status: :unprocessable_entity
        end
      end

      def destroy
        @category.destroy!
        redirect_to admin_store_categories_path, notice: "分类已删除。"
      end

      private

      def set_category
        @category = ::Commerce::Category.find(params[:id])
      end

      def category_params
        params.require(:category).permit(:name, :slug, :position)
      end

      def form_props(category)
        {
          title: category.persisted? ? "编辑分类" : "新建分类",
          category: {
            id: category.id,
            name: category.name || "",
            slug: category.slug || "",
            position: category.position || 0
          },
          submitUrl: category.persisted? ? admin_store_category_path(category) : admin_store_categories_path,
          method: category.persisted? ? "patch" : "post",
          backUrl: admin_store_categories_path
        }
      end
    end
  end
end
