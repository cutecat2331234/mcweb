# frozen_string_literal: true

require "digest"
require "json"
require_relative "commerce_snapshot"
require_relative "result"

module Mcweb
  module PluginApi
    module V1
      # User-bound commerce facade. Catalog reads expose only public,
      # allow-listed DTOs unless the caller has the canonical staff permission.
      # Every mutation delegates to a core commerce service and converts its
      # outcome into a stable, immutable Result protocol.
      class Commerce
        DEFAULT_LIMIT = 50
        MAX_LIMIT = 100
        MAX_SELECTOR_LENGTH = 255
        MAX_BULK_TARGETS = 100
        MAX_REASON_LENGTH = 1_000
        ORDER_READ_PERMISSION = "store.orders.read"
        PRODUCT_READ_PERMISSION = "store.products.read"
        INVENTORY_READ_PERMISSION = "store.inventory.read"
        FULFILLMENT_READ_PERMISSION = "store.fulfillments.read"
        ORDER_ACTIONS = %w[cancel_pending mark_paid mark_fulfilled].freeze
        FULFILLMENT_ACTIONS = %w[retry cancel].freeze
        INVENTORY_TARGET_TYPES = %w[product variant].freeze
        REFUND_REQUEST_EVENT = "refund_requested"
        REFUND_IDEMPOTENCY_KEYS = %w[
          plugin_id plugin_request_uuid plugin_request_fingerprint refund_id
        ].freeze

        SERVICE_ERROR_CODES = %w[
          automated_fulfillment_required
          fulfillment_action_invalid
          fulfillment_not_cancellable
          fulfillment_not_retryable
          fulfillment_state_changed
          high_risk_action_invalid
          high_risk_authorization_invalid
          high_risk_authorization_replayed
          high_risk_confirmation_invalid
          high_risk_idempotency_conflict
          high_risk_reason_required
          high_risk_reason_too_long
          high_risk_request_id_invalid
          high_risk_request_id_reused
          high_risk_target_invalid
          high_risk_unauthorized
          inventory_delta_invalid
          inventory_target_unavailable
          order_cannot_cancel
          order_cannot_mark_fulfilled
          order_cannot_mark_paid
          order_payment_expired
          orders_not_selected
          refund_amount_exceeds_limit
          refund_amount_invalid
        ].freeze

        SERVICE_ERROR_ALIASES = {
          "Not your order." => "forbidden",
          "Order is not refundable." => "order_not_refundable",
          "Refund window has expired." => "refund_window_expired",
          "No payment found." => "payment_not_found",
          "Refund already pending." => "refund_already_pending",
          "No refundable amount remaining." => "refund_balance_exhausted"
        }.freeze

        PUBLIC_ERROR_MESSAGES = {
          "forbidden" => "commerce access denied",
          "idempotency_conflict" => "request UUID was already used for different input",
          "not_found" => "commerce resource not found or not visible",
          "order_not_refundable" => "order is not refundable",
          "refund_already_pending" => "a refund is already pending",
          "refund_balance_exhausted" => "no refundable balance remains",
          "refund_window_expired" => "refund window has expired",
          "payment_not_found" => "refundable payment not found",
          "validation_failed" => "commerce operation validation failed"
        }.freeze

        def initialize(plugin_id: nil, capability_auditor: nil)
          @plugin_id = plugin_id&.to_s&.dup&.freeze
          @capability_auditor = capability_auditor
          freeze
        end

        def categories(user:, limit: DEFAULT_LIMIT)
          audit("commerce.catalog.read")
          user, failure = resolve_user(user)
          return failure if failure

          limit, failure = resolve_limit(limit)
          return failure if failure

          visible_category_ids = catalog_products(user)
            .where.not(store_category_id: nil)
            .select(:store_category_id)
          snapshots = ::Commerce::Category
            .where(id: visible_category_ids)
            .ordered
            .limit(limit)
            .map { |category| CommerceSnapshot.category(category) }
          Result.success(snapshots)
        rescue StandardError
          host_failure
        end

        def products(
          user:,
          category_slug: nil,
          available: nil,
          limit: DEFAULT_LIMIT
        )
          audit("commerce.catalog.read")
          user, failure = resolve_user(user)
          return failure if failure

          limit, failure = resolve_limit(limit)
          return failure if failure

          available, failure = resolve_optional_boolean(available, name: "available")
          return failure if failure

          relation = catalog_products(user)
          if category_slug.present?
            category, failure = resolve_visible_category(user, slug: category_slug)
            return failure if failure

            relation = relation.where(store_category_id: category.id)
          end
          relation = filter_product_availability(relation, available)
          snapshots = relation
            .includes(:category, :variants)
            .order(:name, :id)
            .limit(limit)
            .map { |product| CommerceSnapshot.product(product) }
          Result.success(snapshots)
        rescue StandardError
          host_failure
        end

        def find_product(user:, id: nil, public_id: nil, slug: nil)
          audit("commerce.catalog.read")
          user, failure = resolve_user(user)
          return failure if failure

          product, failure = resolve_product(
            user:,
            id:,
            public_id:,
            slug:
          )
          failure || Result.success(CommerceSnapshot.product(product))
        rescue StandardError
          host_failure
        end

        def prices(user:, id: nil, public_id: nil, slug: nil)
          audit("commerce.catalog.read")
          user, failure = resolve_user(user)
          return failure if failure

          product, failure = resolve_product(
            user:,
            id:,
            public_id:,
            slug:
          )
          failure || Result.success(CommerceSnapshot.pricing(product))
        rescue StandardError
          host_failure
        end

        def availability(user:, id: nil, public_id: nil, slug: nil)
          audit("commerce.catalog.read")
          user, failure = resolve_user(user)
          return failure if failure

          product, failure = resolve_product(
            user:,
            id:,
            public_id:,
            slug:
          )
          failure || Result.success(CommerceSnapshot.availability(product))
        rescue StandardError
          host_failure
        end

        def inventory(
          user:,
          product_public_id: nil,
          target_type: nil,
          limit: DEFAULT_LIMIT
        )
          audit("commerce.inventory.read")
          user, failure = resolve_user(user)
          return failure if failure
          return forbidden unless user.permission?(INVENTORY_READ_PERMISSION)

          limit, failure = resolve_limit(limit)
          return failure if failure

          target_type, failure = resolve_optional_inventory_target_type(target_type)
          return failure if failure

          products = ::Commerce::Product.order(:name, :id)
          if product_public_id.present?
            product_public_id, failure = resolve_public_selector(
              product_public_id,
              name: "product_public_id"
            )
            return failure if failure

            products = products.where(public_id: product_public_id)
          end

          targets = []
          if target_type.nil? || target_type == "product"
            targets.concat(products.limit(limit).to_a)
          end
          if (target_type.nil? || target_type == "variant") && targets.length < limit
            variants = ::Commerce::ProductVariant
              .joins(:product)
              .merge(products.reorder(nil))
              .includes(:product)
              .order("store_products.name", "store_product_variants.id")
              .limit(limit - targets.length)
            targets.concat(variants.to_a)
          end
          Result.success(targets.map { |target| inventory_snapshot(target) })
        rescue StandardError
          host_failure
        end

        def find_inventory(user:, target_type:, target_id:)
          audit("commerce.inventory.read")
          user, failure = resolve_user(user)
          return failure if failure
          return forbidden unless user.permission?(INVENTORY_READ_PERMISSION)

          target, failure = resolve_inventory_target(
            target_type:,
            target_id:
          )
          failure || Result.success(inventory_snapshot(target))
        rescue StandardError
          host_failure
        end

        def orders(user:, status: nil, limit: DEFAULT_LIMIT)
          audit("commerce.orders.read")
          user, failure = resolve_user(user)
          return failure if failure

          limit, failure = resolve_limit(limit)
          return failure if failure

          status, failure = resolve_order_status(status)
          return failure if failure

          relation = accessible_orders(user)
          relation = relation.where(status:) if status
          snapshots = relation
            .order(created_at: :desc, id: :desc)
            .limit(limit)
            .map { |order| CommerceSnapshot.order(order) }
          Result.success(snapshots)
        rescue StandardError
          host_failure
        end

        def find_order(user:, id: nil, public_id: nil)
          audit("commerce.orders.read")
          user, failure = resolve_user(user)
          return failure if failure

          order, failure = resolve_order(user:, id:, public_id:)
          failure || Result.success(CommerceSnapshot.order(order))
        rescue StandardError
          host_failure
        end

        def payments(user:, order_id: nil, order_public_id: nil, limit: DEFAULT_LIMIT)
          audit("commerce.payments.read")
          user, failure = resolve_user(user)
          return failure if failure

          limit, failure = resolve_limit(limit)
          return failure if failure

          order, failure = resolve_fulfillment_order(
            user:,
            id: order_id,
            public_id: order_public_id
          )
          return failure if failure

          snapshots = order.payment_records
            .order(created_at: :desc, id: :desc)
            .limit(limit)
            .map { |payment| CommerceSnapshot.payment(payment, order:) }
          Result.success(snapshots)
        rescue StandardError
          host_failure
        end

        def find_payment(user:, id:)
          audit("commerce.payments.read")
          user, failure = resolve_user(user)
          return failure if failure

          id, failure = resolve_positive_id(id)
          return failure if failure

          payment = ::Payments::Record
            .joins(:order)
            .merge(accessible_orders(user))
            .includes(:order)
            .find_by(id:)
          return not_visible("payment") unless payment

          Result.success(CommerceSnapshot.payment(payment, order: payment.order))
        rescue StandardError
          host_failure
        end

        def refunds(user:, order_id: nil, order_public_id: nil, limit: DEFAULT_LIMIT)
          audit("commerce.refunds.read")
          user, failure = resolve_user(user)
          return failure if failure

          limit, failure = resolve_limit(limit)
          return failure if failure

          order, failure = resolve_order(
            user:,
            id: order_id,
            public_id: order_public_id
          )
          return failure if failure

          snapshots = order.refunds
            .order(created_at: :desc, id: :desc)
            .limit(limit)
            .map { |refund| CommerceSnapshot.refund(refund, order:) }
          Result.success(snapshots)
        rescue StandardError
          host_failure
        end

        def find_refund(user:, id:)
          audit("commerce.refunds.read")
          user, failure = resolve_user(user)
          return failure if failure

          id, failure = resolve_positive_id(id)
          return failure if failure

          refund = ::Commerce::Refund
            .joins(:order)
            .merge(accessible_orders(user))
            .includes(:order)
            .find_by(id:)
          return not_visible("refund") unless refund

          Result.success(CommerceSnapshot.refund(refund, order: refund.order))
        rescue StandardError
          host_failure
        end

        def fulfillments(
          user:,
          order_id: nil,
          order_public_id: nil,
          limit: DEFAULT_LIMIT
        )
          audit("commerce.fulfillments.read")
          user, failure = resolve_user(user)
          return failure if failure

          limit, failure = resolve_limit(limit)
          return failure if failure

          order, failure = resolve_order(
            user:,
            id: order_id,
            public_id: order_public_id
          )
          return failure if failure

          snapshots = order.fulfillments
            .includes(:order, :order_item)
            .order(created_at: :desc, id: :desc)
            .limit(limit)
            .map { |fulfillment| CommerceSnapshot.fulfillment(fulfillment) }
          Result.success(snapshots)
        rescue StandardError
          host_failure
        end

        def find_fulfillment(user:, id: nil, delivery_id: nil)
          audit("commerce.fulfillments.read")
          user, failure = resolve_user(user)
          return failure if failure

          selector, failure = resolve_fulfillment_selector(
            id:,
            delivery_id:
          )
          return failure if failure

          relation = ::Commerce::Fulfillment
            .joins(:order)
            .merge(accessible_fulfillment_orders(user))
            .includes(:order, :order_item)
          fulfillment =
            if selector.fetch(:kind) == :id
              relation.find_by(id: selector.fetch(:value))
            else
              relation.find_by(delivery_id: selector.fetch(:value))
            end
          return not_visible("fulfillment") unless fulfillment

          Result.success(CommerceSnapshot.fulfillment(fulfillment))
        rescue StandardError
          host_failure
        end

        def authorize_order_action(
          actor:,
          order_public_ids:,
          action:,
          request_uuid:,
          reason:
        )
          audit("commerce.orders.write")
          actor, failure = resolve_actor(actor)
          return failure if failure

          action, failure = resolve_order_action(action)
          return failure if failure
          return forbidden unless actor.permission?(order_action_permission(action))

          orders, failure = resolve_action_orders(order_public_ids)
          return failure if failure

          service = ::Commerce::HighRiskOrderAction.new(
            actor:,
            order_public_ids: orders.map(&:public_id),
            action:,
            request_id: request_uuid,
            reason:
          )
          service_result = service.authorize
          return service_failure(service_result) if service_result.failure?

          Result.success(
            CommerceSnapshot.authorization(
              service_result.value,
              operation: "order.#{action}",
              targets: orders.map { |order| CommerceSnapshot.order(order) }
            )
          )
        rescue StandardError
          host_failure
        end

        def execute_order_action(
          actor:,
          order_public_ids:,
          action:,
          request_uuid:,
          reason:,
          authorization_token:,
          confirmation:
        )
          audit("commerce.orders.write")
          actor, failure = resolve_actor(actor)
          return failure if failure

          action, failure = resolve_order_action(action)
          return failure if failure
          return forbidden unless actor.permission?(order_action_permission(action))

          orders, failure = resolve_action_orders(order_public_ids)
          return failure if failure

          service_result = ::Commerce::HighRiskOrderAction.call(
            actor:,
            order_public_ids: orders.map(&:public_id),
            action:,
            request_id: request_uuid,
            reason:,
            authorization_token:,
            confirmation:
          )
          return service_failure(service_result) if service_result.failure?

          Result.success(
            CommerceSnapshot.order_action(service_result.value, action:)
          )
        rescue StandardError
          host_failure
        end

        def authorize_inventory_adjustment(
          actor:,
          target_type:,
          target_id:,
          delta:,
          request_uuid:,
          reason:
        )
          audit("commerce.inventory.write")
          actor, failure = resolve_actor(actor)
          return failure if failure
          return forbidden unless actor.permission?("store.inventory.adjust")

          target, failure = resolve_inventory_target(
            target_type:,
            target_id:
          )
          return failure if failure

          service_result = ::Commerce::InventoryAdjustment.call(
            actor:,
            target:,
            delta:,
            request_id: request_uuid,
            reason:,
            authorize_only: true
          )
          return service_failure(service_result) if service_result.failure?

          Result.success(
            CommerceSnapshot.authorization(
              service_result.value,
              operation: "inventory.adjust",
              targets: [ inventory_snapshot(target) ]
            )
          )
        rescue StandardError
          host_failure
        end

        def adjust_inventory(
          actor:,
          target_type:,
          target_id:,
          delta:,
          request_uuid:,
          reason:,
          authorization_token:,
          confirmation:
        )
          audit("commerce.inventory.write")
          actor, failure = resolve_actor(actor)
          return failure if failure
          return forbidden unless actor.permission?("store.inventory.adjust")

          target, failure = resolve_inventory_target(
            target_type:,
            target_id:
          )
          return failure if failure

          service_result = ::Commerce::InventoryAdjustment.call(
            actor:,
            target:,
            delta:,
            request_id: request_uuid,
            reason:,
            authorization_token:,
            confirmation:
          )
          return service_failure(service_result) if service_result.failure?

          Result.success(
            CommerceSnapshot.inventory_adjustment(
              service_result.value,
              target:
            )
          )
        rescue StandardError
          host_failure
        end

        def authorize_fulfillment_action(
          actor:,
          delivery_id:,
          action:,
          request_uuid:,
          reason:
        )
          audit("commerce.fulfillments.write")
          actor, failure = resolve_actor(actor)
          return failure if failure

          action, failure = resolve_fulfillment_action(action)
          return failure if failure
          return forbidden unless actor.permission?("store.fulfillments.#{action}")

          fulfillment, failure = resolve_fulfillment_for_action(delivery_id)
          return failure if failure

          service_result = ::Commerce::ManualFulfillmentAction.call(
            actor:,
            fulfillment:,
            action:,
            request_id: request_uuid,
            reason:,
            authorize_only: true
          )
          return service_failure(service_result) if service_result.failure?

          Result.success(
            CommerceSnapshot.authorization(
              service_result.value,
              operation: "fulfillment.#{action}",
              targets: [ CommerceSnapshot.fulfillment(fulfillment) ]
            )
          )
        rescue StandardError
          host_failure
        end

        def execute_fulfillment_action(
          actor:,
          delivery_id:,
          action:,
          request_uuid:,
          reason:,
          authorization_token:,
          confirmation:
        )
          audit("commerce.fulfillments.write")
          actor, failure = resolve_actor(actor)
          return failure if failure

          action, failure = resolve_fulfillment_action(action)
          return failure if failure
          return forbidden unless actor.permission?("store.fulfillments.#{action}")

          fulfillment, failure = resolve_fulfillment_for_action(delivery_id)
          return failure if failure

          service_result = ::Commerce::ManualFulfillmentAction.call(
            actor:,
            fulfillment:,
            action:,
            request_id: request_uuid,
            reason:,
            authorization_token:,
            confirmation:
          )
          return service_failure(service_result) if service_result.failure?

          Result.success(
            CommerceSnapshot.fulfillment_action(service_result.value)
          )
        rescue StandardError
          host_failure
        end

        def request_refund(
          actor:,
          order_public_id:,
          amount_cents: nil,
          reason:,
          request_uuid:
        )
          audit("commerce.refunds.write")
          actor, failure = resolve_actor(actor)
          return failure if failure

          request_uuid, failure = resolve_request_uuid(request_uuid)
          return failure if failure
          reason, failure = resolve_reason(reason)
          return failure if failure
          amount_cents, failure = resolve_optional_positive_amount(amount_cents)
          return failure if failure

          order_public_id, failure = resolve_public_selector(
            order_public_id,
            name: "order_public_id"
          )
          return failure if failure

          refund_request(
            actor:,
            order_public_id:,
            amount_cents:,
            reason:,
            request_uuid:
          )
        rescue StandardError
          host_failure
        end

        private

        def audit(capability)
          @capability_auditor&.call(capability)
        end

        def resolve_user(user)
          unless user.is_a?(::User) && user.persisted?
            return [ nil, Result.failure(
              code: "invalid_user",
              error: "a persisted user is required"
            ) ]
          end
          unless user.session_eligible?
            return [ nil, Result.failure(
              code: "forbidden",
              error: "commerce access denied"
            ) ]
          end

          [ user, nil ]
        end

        def resolve_actor(actor)
          unless actor.is_a?(::User) && actor.persisted?
            return [ nil, Result.failure(
              code: "invalid_actor",
              error: "a persisted actor is required"
            ) ]
          end
          return [ nil, forbidden ] unless actor.session_eligible?

          [ actor, nil ]
        end

        def catalog_products(user)
          if user.permission?(PRODUCT_READ_PERMISSION)
            ::Commerce::Product.all
          else
            ::Commerce::Product.available
          end
        end

        def resolve_visible_category(user, slug:)
          slug, failure = resolve_public_selector(slug, name: "category_slug")
          return [ nil, failure ] if failure

          visible_category_ids = catalog_products(user)
            .where.not(store_category_id: nil)
            .select(:store_category_id)
          category = ::Commerce::Category
            .where(id: visible_category_ids)
            .find_by(slug:)
          return [ category, nil ] if category

          [ nil, not_visible("category") ]
        end

        def resolve_product(user:, id:, public_id:, slug:)
          selectors = {
            id:,
            public_id:,
            slug:
          }.compact
          unless selectors.one?
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "provide exactly one of id, public_id, or slug"
            ) ]
          end

          kind, value = selectors.first
          if kind == :id
            value, failure = resolve_positive_id(value)
          else
            value, failure = resolve_public_selector(value, name: kind.to_s)
          end
          return [ nil, failure ] if failure

          product = catalog_products(user)
            .includes(:category, :variants)
            .find_by(kind => value)
          return [ product, nil ] if product

          [ nil, not_visible("product") ]
        end

        def filter_product_availability(relation, available)
          return relation if available.nil?

          available_ids = ::Commerce::Product.available.select(:id)
          if available
            relation.where(id: available_ids)
          else
            relation.where.not(id: available_ids)
          end
        end

        def resolve_optional_boolean(value, name:)
          return [ nil, nil ] if value.nil?
          return [ value, nil ] if value == true || value == false

          [ nil, Result.failure(
            code: "invalid_argument",
            error: "#{name} must be true or false"
          ) ]
        end

        def resolve_optional_inventory_target_type(value)
          return [ nil, nil ] if value.nil?

          type = value.to_s
          return [ type, nil ] if INVENTORY_TARGET_TYPES.include?(type)

          [ nil, Result.failure(
            code: "invalid_argument",
            error: "target_type must be product or variant"
          ) ]
        end

        def resolve_inventory_target(target_type:, target_id:)
          type, failure = resolve_optional_inventory_target_type(target_type)
          return [ nil, failure ] if failure
          unless type
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "target_type is required"
            ) ]
          end

          target =
            if type == "product"
              public_id, selector_failure = resolve_public_selector(
                target_id,
                name: "target_id"
              )
              return [ nil, selector_failure ] if selector_failure

              ::Commerce::Product.find_by(public_id:)
            else
              id, selector_failure = resolve_positive_id(target_id)
              return [ nil, selector_failure ] if selector_failure

              ::Commerce::ProductVariant.includes(:product).find_by(id:)
            end
          return [ target, nil ] if target

          [ nil, not_visible("inventory target") ]
        end

        def inventory_snapshot(target)
          reserved_quantity = ::Commerce::InventoryReservation.active
            .where(target:)
            .sum(:quantity)
          CommerceSnapshot.inventory(target, reserved_quantity:)
        end

        def accessible_orders(user)
          if user.permission?(ORDER_READ_PERMISSION)
            ::Commerce::Order.all
          else
            ::Commerce::Order.where(user_id: user.id)
          end
        end

        def accessible_fulfillment_orders(user)
          if user.permission?(FULFILLMENT_READ_PERMISSION)
            ::Commerce::Order.all
          else
            ::Commerce::Order.where(user_id: user.id)
          end
        end

        def resolve_order(user:, id:, public_id:)
          selector, failure = resolve_order_selector(id:, public_id:)
          return [ nil, failure ] if failure

          order =
            if selector.fetch(:kind) == :id
              accessible_orders(user).find_by(id: selector.fetch(:value))
            else
              accessible_orders(user).find_by(public_id: selector.fetch(:value))
            end
          return [ order, nil ] if order

          [ nil, not_visible("order") ]
        end

        def resolve_fulfillment_order(user:, id:, public_id:)
          selector, failure = resolve_order_selector(id:, public_id:)
          return [ nil, failure ] if failure

          order =
            if selector.fetch(:kind) == :id
              accessible_fulfillment_orders(user).find_by(id: selector.fetch(:value))
            else
              accessible_fulfillment_orders(user).find_by(public_id: selector.fetch(:value))
            end
          return [ order, nil ] if order

          [ nil, not_visible("order") ]
        end

        def resolve_order_selector(id:, public_id:)
          unless id.nil? ^ public_id.nil?
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "provide exactly one of id or public_id"
            ) ]
          end

          if id
            numeric_id, failure = resolve_positive_id(id)
            return [ nil, failure ] if failure

            return [ { kind: :id, value: numeric_id }, nil ]
          end

          value = public_id.to_s
          unless value.length.between?(1, MAX_SELECTOR_LENGTH)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "public_id must be between 1 and #{MAX_SELECTOR_LENGTH} characters"
            ) ]
          end

          [ { kind: :public_id, value: }, nil ]
        end

        def resolve_fulfillment_selector(id:, delivery_id:)
          unless id.nil? ^ delivery_id.nil?
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "provide exactly one of id or delivery_id"
            ) ]
          end

          if id
            numeric_id, failure = resolve_positive_id(id)
            return [ nil, failure ] if failure

            return [ { kind: :id, value: numeric_id }, nil ]
          end

          value, failure = resolve_public_selector(
            delivery_id,
            name: "delivery_id"
          )
          return [ nil, failure ] if failure

          [ { kind: :delivery_id, value: }, nil ]
        end

        def resolve_action_orders(values)
          public_ids = Array(values).map(&:to_s)
          unless public_ids.length.between?(1, MAX_BULK_TARGETS) &&
              public_ids.all? { |value| value.length.between?(1, MAX_SELECTOR_LENGTH) }
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "order_public_ids must contain 1 to #{MAX_BULK_TARGETS} valid identifiers"
            ) ]
          end

          public_ids = public_ids.uniq.sort
          orders = ::Commerce::Order
            .where(public_id: public_ids)
            .includes(:user, items: %i[product variant])
            .order(:id)
            .to_a
          return [ orders, nil ] if orders.length == public_ids.length

          [ nil, not_visible("order") ]
        end

        def resolve_order_action(value)
          action = value.to_s
          return [ action, nil ] if ORDER_ACTIONS.include?(action)

          [ nil, Result.failure(
            code: "invalid_argument",
            error: "order action must be one of: #{ORDER_ACTIONS.join(', ')}"
          ) ]
        end

        def order_action_permission(action)
          mapped_action = ::Commerce::HighRiskOrderAction::ACTION_MAP.fetch(action)
          ::Commerce::HighRiskActionAuthorization.permission_for(mapped_action)
        end

        def resolve_fulfillment_action(value)
          action = value.to_s
          return [ action, nil ] if FULFILLMENT_ACTIONS.include?(action)

          [ nil, Result.failure(
            code: "invalid_argument",
            error: "fulfillment action must be one of: #{FULFILLMENT_ACTIONS.join(', ')}"
          ) ]
        end

        def resolve_fulfillment_for_action(value)
          delivery_id, failure = resolve_public_selector(
            value,
            name: "delivery_id"
          )
          return [ nil, failure ] if failure

          fulfillment = ::Commerce::Fulfillment
            .includes(:order, order_item: :inventory_reservation)
            .find_by(delivery_id:)
          return [ fulfillment, nil ] if fulfillment

          [ nil, not_visible("fulfillment") ]
        end

        def resolve_positive_id(value)
          id = Integer(value, exception: false)
          unless id&.positive?
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "id must be a positive integer"
            ) ]
          end

          [ id, nil ]
        end

        def resolve_limit(value)
          limit = Integer(value, exception: false)
          unless limit&.between?(1, MAX_LIMIT)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "limit must be between 1 and #{MAX_LIMIT}"
            ) ]
          end

          [ limit, nil ]
        end

        def resolve_public_selector(value, name:)
          selector = value.to_s
          unless selector.length.between?(1, MAX_SELECTOR_LENGTH)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "#{name} must be between 1 and #{MAX_SELECTOR_LENGTH} characters"
            ) ]
          end

          [ selector, nil ]
        end

        def resolve_request_uuid(value)
          request_uuid = value.to_s.strip.downcase
          unless ::Commerce::HighRiskOperation::REQUEST_ID_FORMAT.match?(request_uuid)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "request_uuid must be a UUID"
            ) ]
          end

          [ request_uuid, nil ]
        end

        def resolve_reason(value)
          reason = value.to_s.strip
          unless reason.length.between?(1, MAX_REASON_LENGTH)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "reason must be between 1 and #{MAX_REASON_LENGTH} characters"
            ) ]
          end

          [ reason, nil ]
        end

        def resolve_optional_positive_amount(value)
          return [ nil, nil ] if value.nil?

          amount = Integer(value, exception: false)
          unless amount&.positive?
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "amount_cents must be a positive integer"
            ) ]
          end

          [ amount, nil ]
        end

        def resolve_order_status(value)
          return [ nil, nil ] if value.nil?

          status = value.to_s
          unless ::Commerce::Order::STATUSES.include?(status)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "order status is invalid"
            ) ]
          end

          [ status, nil ]
        end

        def refund_request(
          actor:,
          order_public_id:,
          amount_cents:,
          reason:,
          request_uuid:
        )
          return host_failure if @plugin_id.blank?

          fingerprint = refund_request_fingerprint(
            actor:,
            order_public_id:,
            amount_cents:,
            reason:,
            request_uuid:
          )
          result = nil

          ::User.transaction do
            locked_actor = ::User.lock.find(actor.id)
            unless locked_actor.session_eligible?
              result = forbidden
              raise ActiveRecord::Rollback
            end

            event = existing_refund_request_event(
              actor: locked_actor,
              request_uuid:
            )
            if event
              result = replay_refund_request(
                event:,
                fingerprint:,
                request_uuid:
              )
              raise ActiveRecord::Rollback if result.failure?
              next
            end

            order = ::Commerce::Order.lock.find_by(
              public_id: order_public_id,
              user_id: locked_actor.id
            )
            unless order
              result = not_visible("order")
              raise ActiveRecord::Rollback
            end

            service_result = ::Commerce::RequestRefund.call(
              order:,
              user: locked_actor,
              amount_cents:,
              reason:
            )
            if service_result.failure?
              result = service_failure(service_result)
              raise ActiveRecord::Rollback
            end

            refund = service_result.value
            event = order.events
              .where(actor: locked_actor, event_type: REFUND_REQUEST_EVENT)
              .where("metadata ->> 'refund_id' = ?", refund.id.to_s)
              .order(id: :desc)
              .first
            raise ActiveRecord::RecordNotFound unless event

            event.update!(
              metadata: event.metadata.merge(
                "plugin_id" => @plugin_id,
                "plugin_request_uuid" => request_uuid,
                "plugin_request_fingerprint" => fingerprint,
                "refund_id" => refund.id
              ).slice(*(event.metadata.keys + REFUND_IDEMPOTENCY_KEYS).uniq)
            )
            result = Result.success(
              CommerceSnapshot.refund_request(
                refund,
                request_uuid:,
                idempotent: false
              )
            )
          end

          result || host_failure
        end

        def existing_refund_request_event(actor:, request_uuid:)
          ::Commerce::OrderEvent
            .where(actor:, event_type: REFUND_REQUEST_EVENT)
            .where("metadata ->> 'plugin_id' = ?", @plugin_id)
            .where("metadata ->> 'plugin_request_uuid' = ?", request_uuid)
            .order(id: :asc)
            .first
        end

        def replay_refund_request(event:, fingerprint:, request_uuid:)
          stored_fingerprint = event.metadata["plugin_request_fingerprint"].to_s
          unless secure_match?(stored_fingerprint, fingerprint)
            return Result.failure(
              code: "idempotency_conflict",
              error: PUBLIC_ERROR_MESSAGES.fetch("idempotency_conflict")
            )
          end

          refund = ::Commerce::Refund.includes(:order).find_by(
            id: event.metadata["refund_id"],
            requested_by_id: event.actor_id
          )
          return host_failure unless refund

          Result.success(
            CommerceSnapshot.refund_request(
              refund,
              request_uuid:,
              idempotent: true
            )
          )
        end

        def refund_request_fingerprint(
          actor:,
          order_public_id:,
          amount_cents:,
          reason:,
          request_uuid:
        )
          Digest::SHA256.hexdigest(
            JSON.generate(
              plugin_id: @plugin_id,
              actor_id: actor.id,
              operation: "refund.request",
              order_public_id:,
              amount_cents:,
              reason:,
              request_uuid:
            )
          )
        end

        def service_failure(service_result)
          code = stable_service_error_code(service_result)
          Result.failure(
            code:,
            error: PUBLIC_ERROR_MESSAGES.fetch(
              code,
              "commerce operation was rejected"
            )
          )
        end

        def stable_service_error_code(service_result)
          return service_result.code if service_result.code.to_s.match?(/\A[a-z][a-z0-9_]*\z/)

          error = service_result.error.to_s
          alias_code = SERVICE_ERROR_ALIASES[error]
          return alias_code if alias_code

          SERVICE_ERROR_CODES.each do |code|
            translated = I18n.t(
              "mcweb.services.errors.#{code}",
              default: code
            ).to_s
            return code if error == code || error == translated
          end

          service_result.errors.present? ? "validation_failed" : "service_failure"
        end

        def secure_match?(left, right)
          left = left.to_s
          right = right.to_s
          left.bytesize == right.bytesize &&
            ActiveSupport::SecurityUtils.secure_compare(left, right)
        end

        def forbidden
          Result.failure(
            code: "forbidden",
            error: PUBLIC_ERROR_MESSAGES.fetch("forbidden")
          )
        end

        def not_visible(resource)
          Result.failure(
            code: "not_found",
            error: "#{resource} not found or not visible"
          )
        end

        def host_failure
          Result.failure(
            code: "host_error",
            error: "commerce host operation failed"
          )
        end
      end
    end
  end
end
