# frozen_string_literal: true



module Admin
  module Store
    class CouponsController < BaseController
      before_action -> { require_permission("store.products.manage") }

      before_action :set_coupon, only: %i[show edit update]



      def index
        coupons = ::Commerce::Coupon.order(created_at: :desc)



        render inertia: "Admin/Generic/Index", props: {

          title: t("mcweb.admin.store.coupons.title"),

          columns: [

            admin_column(:code, t("mcweb.admin.store.coupons.col_code"), link: true),

            admin_column(:discount_type, t("mcweb.admin.store.coupons.col_type")),

            admin_column(:discount_value, t("mcweb.admin.store.coupons.col_discount")),

            admin_column(:active, t("mcweb.admin.store.coupons.col_status"))

          ],

          rows: coupons.map do |coupon|
            admin_row(

              code: coupon.code,

              discount_type: coupon.discount_type,

              discount_value: coupon.discount_value.to_s,

              active: coupon_active_label(coupon.active?),

              url: admin_store_coupon_path(coupon)

            )
          end,

          actions: [ { label: t("mcweb.admin.store.coupons.new"), href: new_admin_store_coupon_path } ]

        }
      end



      def show
        render inertia: "Admin/Generic/Show", props: {

          title: @coupon.code,

          fields: [

            { label: t("mcweb.admin.store.coupons.field_type"), value: @coupon.discount_type },

            { label: t("mcweb.admin.store.coupons.field_discount_value"), value: @coupon.discount_value.to_s },

            { label: t("mcweb.admin.store.coupons.field_min_amount"), value: format_money(@coupon.min_amount_cents, "CNY") },

            {

              label: t("mcweb.admin.store.coupons.field_usage_count"),

              value: t(

                "mcweb.admin.store.coupons.usage_count",

                used: @coupon.used_count,

                limit: @coupon.usage_limit || t("mcweb.labels.unlimited")

              )

            },

            { label: t("mcweb.admin.store.coupons.col_status"), value: coupon_active_label(@coupon.active?) }

          ],

          backUrl: admin_store_coupons_path,

          actions: [ { label: t("mcweb.admin.store.action_edit"), href: edit_admin_store_coupon_path(@coupon) } ]

        }
      end



      def new
        render inertia: "Admin/Store/Coupons/Form", props: form_props(::Commerce::Coupon.new)
      end



      def create
        coupon = ::Commerce::Coupon.new(coupon_params)

        if coupon.save

          redirect_to admin_store_coupon_path(coupon), notice: t("mcweb.flash.created", resource: t("mcweb.resources.coupon"))

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

          redirect_to admin_store_coupon_path(@coupon), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.coupon"))

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
        permitted = params.require(:coupon).permit(

          :code, :discount_type, :discount_value, :min_amount_cents,

          :usage_limit, :active, :starts_at, :ends_at,

          :per_user_limit, :first_order_only, :max_discount_cents, :description, :free_shipping,

          product_ids: [], category_ids: []

        )

        permitted[:free_shipping] = false unless Commerce::StoreFeatures.enabled?(:shipping)

        permitted
      end



      def form_props(coupon)
        {

          title: coupon.persisted? ? t("mcweb.admin.store.coupons.edit") : t("mcweb.admin.store.coupons.new"),

          coupon: {

            id: coupon.id,

            code: coupon.code || "",

            discount_type: coupon.discount_type || "percentage",

            discount_value: coupon.discount_value || 10,

            min_amount_cents: coupon.min_amount_cents || 0,

            usage_limit: coupon.usage_limit,

            per_user_limit: coupon.per_user_limit,

            first_order_only: coupon.first_order_only || false,

            max_discount_cents: coupon.max_discount_cents,

            active: coupon.active.nil? ? true : coupon.active,

            starts_at: coupon.starts_at&.strftime("%Y-%m-%dT%H:%M"),

            ends_at: coupon.ends_at&.strftime("%Y-%m-%dT%H:%M"),

            product_ids: coupon.restricted_product_ids,

            category_ids: coupon.restricted_category_ids,

            description: coupon.description || "",

            free_shipping: coupon.free_shipping?

          },

          products: ::Commerce::Product.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } },

          categories: ::Commerce::Category.ordered.pluck(:id, :name).map { |id, name| { id: id, name: name } },

          submitUrl: coupon.persisted? ? admin_store_coupon_path(coupon) : admin_store_coupons_path,

          method: coupon.persisted? ? "patch" : "post",

          backUrl: admin_store_coupons_path

        }
      end



      def coupon_active_label(active)
        active ? t("mcweb.admin.store.coupons.status_enabled") : t("mcweb.admin.store.coupons.status_disabled")
      end
    end
  end
end
