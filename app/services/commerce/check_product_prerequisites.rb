# frozen_string_literal: true

module Commerce
  class CheckProductPrerequisites < ApplicationService
    PURCHASED_STATUSES = %w[paid processing fulfilling fulfilled completed].freeze

    def initialize(user:, product:)
      @user = user
      @product = product
    end

    def call
      prerequisites = @product.prerequisites.includes(:required_product).to_a
      return ServiceResult.success if prerequisites.empty?

      return ServiceResult.failure(error: I18n.t("commerce.prerequisites.login_required")) unless @user

      results = prerequisites.map { |prerequisite| satisfied?(prerequisite) }

      satisfied = if @product.prerequisite_match_any?
                    results.any?
      else
                    results.all?
      end

      unless satisfied
        names = prerequisites.reject.with_index { |_, i| results[i] }.map { |p| p.required_product.name }
        return ServiceResult.failure(
          error: I18n.t("commerce.prerequisites.not_met", products: names.to_sentence)
        )
      end

      ServiceResult.success
    end

    def self.satisfied?(user:, prerequisite:)
      new(user: user, product: prerequisite.product).send(:satisfied?, prerequisite)
    end

    def self.purchased?(user:, product:)
      return false unless user

      Commerce::OrderItem
        .joins(:order)
        .where(store_orders: { user_id: user.id, status: PURCHASED_STATUSES })
        .where(store_product_id: product.id)
        .exists?
    end

    def self.active_entitlement?(user:, product:)
      return false unless user

      if product.membership_product? && product.store_membership_type_id.present?
        return Commerce::UserMembership
          .currently_active
          .where(user: user, store_membership_type_id: product.store_membership_type_id)
          .exists?
      end

      Commerce::UserEntitlement
        .currently_active
        .where(user: user, store_product_id: product.id)
        .exists?
    end

    private

    def satisfied?(prerequisite)
      case prerequisite.requirement_mode
      when "ever_purchased"
        self.class.purchased?(user: @user, product: prerequisite.required_product)
      when "active"
        self.class.active_entitlement?(user: @user, product: prerequisite.required_product)
      else
        false
      end
    end
  end
end
