# frozen_string_literal: true

module Commerce
  class CreateOrderStaffNote < ApplicationService
    def initialize(actor:, order:, body:, visible_to_customer: false)
      @actor = actor
      @order = order
      @body = body.to_s.strip
      @visible_to_customer = ActiveModel::Type::Boolean.new.cast(visible_to_customer)
    end

    def call
      return ServiceResult.failure(error: "staff_note_unauthorized") unless authorized?
      return ServiceResult.failure(error: "staff_note_blank") if @body.blank?

      note = Commerce::OrderStaffNote.create!(
        order: @order,
        author: @actor,
        body: @body,
        visible_to_customer: @visible_to_customer
      )

      ServiceResult.success(note)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def authorized?
      @actor.permission?("store.orders.read") || @actor.permission?("admin.access")
    end
  end
end
