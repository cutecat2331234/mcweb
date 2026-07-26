# frozen_string_literal: true

require_relative "commerce_snapshot"
require_relative "result"

module Mcweb
  module PluginApi
    module V1
      # Read-only payment-domain facade. Customer callers can only inspect
      # their own orders. Cross-customer reads reuse the host's canonical
      # store.orders.read permission and every missing/hidden lookup shares the
      # same response so identifiers cannot be used as an existence oracle.
      class Commerce
        DEFAULT_LIMIT = 50
        MAX_LIMIT = 100
        MAX_SELECTOR_LENGTH = 255
        ORDER_READ_PERMISSION = "store.orders.read"

        def initialize(capability_auditor: nil)
          @capability_auditor = capability_auditor
          freeze
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

          order, failure = resolve_order(
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

        def accessible_orders(user)
          if user.permission?(ORDER_READ_PERMISSION)
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
