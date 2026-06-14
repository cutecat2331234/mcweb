# frozen_string_literal: true

module Admin
  module Store
    class ProductsController < BaseController
      before_action -> { require_permission("store.products.manage") }
      before_action :set_product, only: %i[show edit update destroy]

      def index
        products = ::Commerce::Product.order(:name)

        render inertia: "Admin/Generic/Index", props: {
          title: "商品",
          columns: [
            admin_column(:name, "名称", link: true),
            admin_column(:slug, "标识"),
            admin_column(:status, "状态"),
            admin_column(:price, "价格")
          ],
          rows: products.map do |product|
            admin_row(
              name: product.name,
              slug: product.slug,
              status: product.status,
              price: format_price(product),
              url: admin_store_product_path(product)
            )
          end,
          actions: [{ label: "新建商品", href: new_admin_store_product_path }]
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @product.name,
          subtitle: @product.slug,
          fields: [
            { label: "类型", value: @product.product_type },
            { label: "状态", value: @product.status },
            { label: "价格", value: format_price(@product) },
            { label: "库存", value: @product.stock.nil? ? "无限" : @product.stock.to_s },
            { label: "描述", value: @product.description || "—" }
          ],
          backUrl: admin_store_products_path,
          actions: [
            { label: "编辑", href: edit_admin_store_product_path(@product) },
            { label: "归档", href: admin_store_product_path(@product), method: "delete", confirm: "确定归档此商品？" }
          ]
        }
      end

      def new
        render inertia: "Admin/Store/Products/Form", props: form_props(::Commerce::Product.new)
      end

      def create
        product = ::Commerce::Product.new(product_params)
        if product.save
          redirect_to admin_store_product_path(product), notice: "商品已创建。"
        else
          render inertia: "Admin/Store/Products/Form",
                 props: form_props(product),
                 status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Store/Products/Form", props: form_props(@product)
      end

      def update
        if @product.update(product_params)
          redirect_to admin_store_product_path(@product), notice: "商品已更新。"
        else
          render inertia: "Admin/Store/Products/Form",
                 props: form_props(@product),
                 status: :unprocessable_entity
        end
      end

      def destroy
        @product.update!(status: :archived)
        redirect_to admin_store_products_path, notice: "商品已归档。"
      end

      private

      def set_product
        @product = ::Commerce::Product.find_by!(public_id: params[:id])
      end

      def product_params
        params.require(:product).permit(
          :name, :slug, :description, :product_type, :status,
          :price_cents, :currency, :stock, :store_category_id, :purchase_limit
        )
      end

      def form_props(product)
        {
          title: product.persisted? ? "编辑商品" : "新建商品",
          product: {
            public_id: product.public_id,
            name: product.name || "",
            slug: product.slug || "",
            description: product.description || "",
            product_type: product.product_type || "virtual",
            status: product.status || "draft",
            price_cents: product.price_cents || 0,
            currency: product.currency || "CNY",
            stock: product.stock,
            store_category_id: product.store_category_id,
            purchase_limit: product.purchase_limit
          },
          categories: ::Commerce::Category.ordered.map { |c| { id: c.id, name: c.name } },
          submitUrl: product.persisted? ? admin_store_product_path(product) : admin_store_products_path,
          method: product.persisted? ? "patch" : "post",
          backUrl: admin_store_products_path
        }
      end
    end
  end
end
