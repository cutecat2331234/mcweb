# frozen_string_literal: true

module Commerce
  class CreateOrderStaffNote < ApplicationService
    def initialize(actor:, order:, body:)
      @actor = actor
      @order = order
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "无权添加员工备注。") unless authorized?
      return ServiceResult.failure(error: "请填写备注内容。") if @body.blank?

      note = Commerce::OrderStaffNote.create!(
        order: @order,
        author: @actor,
        body: @body
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
