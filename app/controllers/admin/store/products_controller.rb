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
          end
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
          backUrl: admin_store_products_path
        }
      end

      def new
        @product = ::Commerce::Product.new
      end

      def create
        @product = ::Commerce::Product.new(product_params)

        if @product.save
          redirect_to admin_store_product_path(@product), notice: "Product created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @product.update(product_params)
          redirect_to admin_store_product_path(@product), notice: "Product updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @product.update!(status: :archived)
        redirect_to admin_store_products_path, notice: "Product archived."
      end

      private

      def set_product
        @product = ::Commerce::Product.find_by!(public_id: params[:id])
      end

      def product_params
        params.expect(product: %i[name slug description product_type status price_cents currency stock store_category_id fulfillment_config])[:product]
      end
    end
  end
end
