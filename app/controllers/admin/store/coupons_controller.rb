# frozen_string_literal: true

module Admin
  module Store
    class CouponsController < BaseController
      before_action -> { require_permission("store.products.manage") }
      before_action :set_coupon, only: %i[show edit update]

      def index
        coupons = ::Commerce::Coupon.order(created_at: :desc)

        render inertia: "Admin/Generic/Index", props: {
          title: "优惠券",
          columns: [
            admin_column(:code, "代码", link: true),
            admin_column(:discount_type, "类型"),
            admin_column(:discount_value, "折扣"),
            admin_column(:active, "状态")
          ],
          rows: coupons.map do |coupon|
            admin_row(
              code: coupon.code,
              discount_type: coupon.discount_type,
              discount_value: coupon.discount_value.to_s,
              active: coupon.active? ? "启用" : "禁用",
              url: admin_store_coupon_path(coupon)
            )
          end,
          actions: [{ label: "新建优惠券", href: new_admin_store_coupon_path }]
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @coupon.code,
          fields: [
            { label: "类型", value: @coupon.discount_type },
            { label: "折扣值", value: @coupon.discount_value.to_s },
            { label: "最低消费", value: format_money(@coupon.min_amount_cents, "CNY") },
            { label: "使用次数", value: "#{@coupon.used_count} / #{@coupon.usage_limit || '∞'}" },
            { label: "状态", value: @coupon.active? ? "启用" : "禁用" }
          ],
          backUrl: admin_store_coupons_path,
          actions: [{ label: "编辑", href: edit_admin_store_coupon_path(@coupon) }]
        }
      end

      def new
        render inertia: "Admin/Store/Coupons/Form", props: form_props(::Commerce::Coupon.new)
      end

      def create
        coupon = ::Commerce::Coupon.new(coupon_params)
        if coupon.save
          redirect_to admin_store_coupon_path(coupon), notice: "优惠券已创建。"
        else
          render inertia: "Admin/Store/Coupons/Form",
                 props: form_props(coupon),
                 status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Store/Coupons/Form", props: form_props(@coupon)
      end

      def update
        if @coupon.update(coupon_params)
          redirect_to admin_store_coupon_path(@coupon), notice: "优惠券已更新。"
        else
          render inertia: "Admin/Store/Coupons/Form",
                 props: form_props(@coupon),
                 status: :unprocessable_entity
        end
      end

      private

      def set_coupon
        @coupon = ::Commerce::Coupon.find(params[:id])
      end

      def coupon_params
        params.require(:coupon).permit(
          :code, :discount_type, :discount_value, :min_amount_cents,
          :usage_limit, :active, :starts_at, :ends_at,
          product_ids: [], category_ids: []
        )
      end

      def form_props(coupon)
        {
          title: coupon.persisted? ? "编辑优惠券" : "新建优惠券",
          coupon: {
            id: coupon.id,
            code: coupon.code || "",
            discount_type: coupon.discount_type || "percentage",
            discount_value: coupon.discount_value || 10,
            min_amount_cents: coupon.min_amount_cents || 0,
            usage_limit: coupon.usage_limit,
            active: coupon.active.nil? ? true : coupon.active,
            starts_at: coupon.starts_at&.strftime("%Y-%m-%dT%H:%M"),
            ends_at: coupon.ends_at&.strftime("%Y-%m-%dT%H:%M"),
            product_ids: coupon.restricted_product_ids,
            category_ids: coupon.restricted_category_ids
          },
          products: ::Commerce::Product.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } },
          categories: ::Commerce::Category.ordered.pluck(:id, :name).map { |id, name| { id: id, name: name } },
          submitUrl: coupon.persisted? ? admin_store_coupon_path(coupon) : admin_store_coupons_path,
          method: coupon.persisted? ? "patch" : "post",
          backUrl: admin_store_coupons_path
        }
      end
    end
  end
end
