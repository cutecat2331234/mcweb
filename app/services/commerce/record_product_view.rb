# frozen_string_literal: true

module Commerce
  class RecordProductView < ApplicationService
    MAX_RECENT = 20

    def initialize(user:, product:)
      @user = user
      @product = product
    end

    def call
      return ServiceResult.success unless @user

      view = Commerce::ProductView.find_or_initialize_by(user: @user, product: @product)
      view.viewed_at = Time.current
      view.save!

      trim_old_views!

      ServiceResult.success(view)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def trim_old_views!
      ids = Commerce::ProductView.where(user: @user).order(viewed_at: :desc).offset(MAX_RECENT).pluck(:id)
      Commerce::ProductView.where(id: ids).delete_all if ids.any?
    end
  end
end
