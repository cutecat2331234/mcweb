# frozen_string_literal: true

module Admin
  module Store
    class ProductsController < BaseController
      before_action -> { require_permission("store.products.manage") }
      before_action :set_product, only: %i[show edit update destroy]

      def index
        products_scope = ::Commerce::Product.order(:name)
        if params[:q].present?
          q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
          products_scope = products_scope.where("name ILIKE :q OR slug ILIKE :q", q: q)
        end
        @pagy, products = pagy(:offset, products_scope, limit: 50)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.store.products.title"),
          columns: [
            admin_column(:name, t("mcweb.admin.store.products.col_name"), link: true),
            admin_column(:slug, t("mcweb.admin.store.products.col_slug")),
            admin_column(:status, t("mcweb.admin.store.products.col_status")),
            admin_column(:price, t("mcweb.admin.store.products.col_price")),
            admin_column(:stock, t("mcweb.admin.store.products.col_stock"))
          ],
          rows: products.map do |product|
            stock_label = product.stock.nil? ? "∞" : product.stock.to_s
            stock_label = "#{stock_label} ⚠" if product.stock.present? && product.stock <= 5
            admin_row(
              name: product.name,
              slug: product.slug,
              status: product_status_label(product.status),
              price: format_price(product),
              stock: stock_label,
              url: admin_store_product_path(product)
            )
          end,
          pagination: pagy_props(@pagy),
          actions: [ { label: t("mcweb.admin.store.products.new"), href: new_admin_store_product_path } ]
        }
      end

      def show
        product = ::Commerce::Product.includes(:membership_type, :prerequisites).find_by!(public_id: params[:id])
        fields = [
          { label: t("mcweb.admin.store.products.field_type"), value: product_type_label(product.product_type) },
          { label: t("mcweb.admin.store.products.field_status"), value: product_status_label(product.status) }
        ]
        if product.membership_product?
          fields << {
            label: t("mcweb.admin.store.products.field_membership_type"),
            value: product.membership_type&.name || t("mcweb.labels.not_available")
          }
        end
        fields << {
          label: t("mcweb.admin.store.products.field_prerequisites"),
          value: product.prerequisites.any? ? t("mcweb.admin.store.products.prerequisite_count", count: product.prerequisites.size) : t("mcweb.admin.store.products.prerequisite_none")
        }
        if product.prerequisites.any?
          fields << {
            label: t("mcweb.admin.store.products.field_prerequisite_match"),
            value: prerequisite_match_mode_label(product.prerequisite_match_mode)
          }
        end
        fields.concat([
          { label: t("mcweb.admin.store.products.field_price"), value: format_price(product) },
          { label: t("mcweb.admin.store.products.field_stock"), value: product.stock.nil? ? "∞" : product.stock.to_s },
          { label: t("mcweb.admin.store.products.field_backorder"), value: product.allow_backorder? ? t("mcweb.labels.yes") : t("mcweb.labels.no") },
          { label: t("mcweb.admin.store.products.field_minimum_quantity"), value: product.minimum_quantity.to_s },
          { label: t("mcweb.admin.store.products.field_description"), value: product.description || t("mcweb.labels.not_available") }
        ])

        render inertia: "Admin/Generic/Show", props: {
          title: product.name,
          subtitle: product.slug,
          fields: fields,
          backUrl: admin_store_products_path,
          actions: [
            { label: t("mcweb.admin.store.action_edit"), href: edit_admin_store_product_path(product) },
            { label: t("mcweb.admin.store.products.action_duplicate"), href: duplicate_admin_store_product_path(product), method: "post" },
            { label: t("mcweb.admin.store.products.action_archive"), href: admin_store_product_path(product), method: "delete", confirm: t("mcweb.admin.store.products.confirm_archive") }
          ]
        }
      end

      def new
        render inertia: "Admin/Store/Products/Form", props: form_props(::Commerce::Product.new)
      end

      def create
        if physical_product_rejected?(product_params)
          product = ::Commerce::Product.new(product_params)
          product.errors.add(:product_type, t("mcweb.admin.store.products.physical_products_disabled"))
          return render inertia: "Admin/Store/Products/Form",
                        props: form_props(product),
                        status: :unprocessable_entity
        end

        product = ::Commerce::Product.new(product_params)
        if product.save
          Commerce::EnsureProductDiscussionTopic.call(product: product) if product.active?
          redirect_to admin_store_product_path(product), notice: t("mcweb.flash.created", resource: t("mcweb.resources.product"))
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
        if physical_product_rejected?(product_params)
          @product.assign_attributes(product_params)
          @product.errors.add(:product_type, t("mcweb.admin.store.products.physical_products_disabled"))
          return render inertia: "Admin/Store/Products/Form",
                        props: form_props(@product),
                        status: :unprocessable_entity
        end

        changelog_changed = product_params[:changelog].present? && product_params[:changelog] != @product.changelog
        version_changed = product_params[:version].present? && product_params[:version] != @product.version

        if @product.update(product_params)
          if @product.low_stock?
            Commerce::NotifyLowStockStaffJob.perform_later(@product.id)
          end
          @product.variants.each do |variant|
            if variant.low_stock?
              Commerce::NotifyLowStockStaffJob.perform_later(@product.id, variant.id)
            end
          end
          if @product.saved_change_to_price_cents? && @product.price_cents < @product.price_cents_before_last_save.to_i
            Commerce::NotifyPriceDropJob.perform_later(@product.id)
          end
          if @product.saved_change_to_stock? && @product.stock.to_i.positive?
            Commerce::NotifyStockRestockedJob.perform_later(@product.id)
          end
          @product.variants.each do |variant|
            if variant.saved_change_to_stock? && variant.stock.to_i.positive?
              Commerce::NotifyStockRestockedJob.perform_later(@product.id, variant.id)
            end
          end
          if (changelog_changed || version_changed) && @product.changelog.present?
            Commerce::NotifyProductChangelogJob.perform_later(@product.id)
          end
          if @product.active? && @product.forum_topic_id.blank?
            Commerce::EnsureProductDiscussionTopic.call(product: @product)
          end
          redirect_to admin_store_product_path(@product), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.product"))
        else
          render inertia: "Admin/Store/Products/Form",
                 props: form_props(@product),
                 status: :unprocessable_entity
        end
      end

      def destroy
        @product.update!(status: :archived)
        redirect_to admin_store_products_path, notice: t("mcweb.flash.archived", resource: t("mcweb.resources.product"))
      end

      def duplicate
        result = Commerce::DuplicateProduct.call(product: @product)
        if result.success?
          redirect_to edit_admin_store_product_path(result.value), notice: t("mcweb.flash.product_copied")
        else
          redirect_to admin_store_product_path(@product), alert: service_error_message(result)
        end
      end

      private

      def set_product
        @product = ::Commerce::Product.find_by!(public_id: params[:id])
      end

      def product_params
        permitted = params.require(:product).permit(
          :name, :slug, :description, :summary, :product_type, :status,
          :price_cents, :compare_at_price_cents, :currency, :stock, :store_category_id, :purchase_limit, :minimum_quantity, :maximum_quantity, :requires_shipping, :allow_backorder, :image_url, :gallery_urls,
          :fulfillment_config, :featured, :version, :changelog, :seo_title, :seo_description, :available_at, :unavailable_at,
          :store_membership_type_id, :prerequisite_match_mode,
          variants_attributes: [ :id, :name, :sku, :price_cents, :compare_at_price_cents, :stock, :_destroy ],
          prerequisites_attributes: [ :id, :required_product_id, :requirement_mode, :_destroy ]
        )
        if permitted[:gallery_urls].is_a?(String)
          permitted[:gallery_urls] = permitted[:gallery_urls].lines.map(&:strip).reject(&:blank?)
        end
        if permitted[:fulfillment_config].is_a?(String)
          raw = permitted[:fulfillment_config].strip
          begin
            permitted[:fulfillment_config] = raw.present? ? JSON.parse(raw) : {}
          rescue JSON::ParserError
            raise ActionController::BadRequest, t("mcweb.admin.store.products.fulfillment_config_json_invalid")
          end
        end
        if permitted.key?(:seo_title) || permitted.key?(:seo_description)
          permitted[:seo] = {
            "title" => permitted.delete(:seo_title).to_s.presence,
            "description" => permitted.delete(:seo_description).to_s.presence
          }.compact
        end
        normalize_store_feature_product_params!(permitted)
        permitted
      end

      def normalize_store_feature_product_params!(permitted)
        return if Commerce::StoreFeatures.enabled?(:shipping)

        permitted[:requires_shipping] = false if permitted.key?(:requires_shipping)
      end

      def physical_product_rejected?(permitted)
        return false if Commerce::StoreFeatures.enabled?(:physical_products)

        permitted[:product_type].to_s == "physical"
      end

      def form_props(product)
        product = product.persisted? ? ::Commerce::Product.includes(:variants, :prerequisites).find(product.id) : product
        {
          title: product.persisted? ? t("mcweb.admin.store.products.edit") : t("mcweb.admin.store.products.new"),
          product: {
            public_id: product.public_id,
            name: product.name || "",
            slug: product.slug || "",
            description: product.description || "",
            summary: product.summary || "",
            product_type: product.product_type || "virtual",
            status: product.status || "draft",
            price_cents: product.price_cents || 0,
            compare_at_price_cents: product.compare_at_price_cents,
            currency: product.currency || "CNY",
            stock: product.stock,
            allow_backorder: product.allow_backorder?,
            minimum_quantity: product.minimum_quantity || 1,
            maximum_quantity: product.maximum_quantity,
            requires_shipping: product.requires_shipping?,
            store_category_id: product.store_category_id,
            store_membership_type_id: product.store_membership_type_id,
            prerequisite_match_mode: product.prerequisite_match_mode || "all",
            purchase_limit: product.purchase_limit,
            image_url: product.image_url || "",
            gallery_urls: (product.gallery_urls || []).join("\n"),
            fulfillment_config: JSON.pretty_generate(product.fulfillment_config.presence || {}),
            featured: product.featured || false,
            version: product.version || "",
            changelog: product.changelog || "",
            seo_title: product.seo&.dig("title").to_s,
            seo_description: product.seo&.dig("description").to_s,
            available_at: product.available_at&.strftime("%Y-%m-%dT%H:%M"),
            unavailable_at: product.unavailable_at&.strftime("%Y-%m-%dT%H:%M"),
            variants: product.variants.map do |v|
              { id: v.id, name: v.name, sku: v.sku, price_cents: v.price_cents, compare_at_price_cents: v.compare_at_price_cents, stock: v.stock }
            end,
            prerequisites: product.prerequisites.map do |p|
              { id: p.id, required_product_id: p.required_product_id, requirement_mode: p.requirement_mode }
            end
          },
          categories: ::Commerce::Category.ordered.map { |c| { id: c.id, name: c.name } },
          membership_types: ::Commerce::MembershipType.active_types.by_display_priority.map { |type| { id: type.id, name: type.name } },
          prerequisite_products: ::Commerce::Product.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } },
          submitUrl: product.persisted? ? admin_store_product_path(product) : admin_store_products_path,
          method: product.persisted? ? "patch" : "post",
          backUrl: admin_store_products_path,
          uploadUrl: product.persisted? ? admin_store_uploads_path(product_id: product.public_id) : nil
        }
      end
    end
  end
end
