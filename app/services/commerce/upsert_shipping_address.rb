# frozen_string_literal: true

module Commerce
  class UpsertShippingAddress < ApplicationService
    def initialize(user:, params:, address: nil, make_default: false)
      @user = user
      @params = params
      @address = address
      @make_default = make_default
    end

    def call
      address = @address || Commerce::ShippingAddress.new(user: @user)
      address.assign_attributes(
        label: @params[:label].to_s.strip.presence,
        name: @params[:name].to_s.strip,
        phone: @params[:phone].to_s.strip,
        line1: @params[:line1].to_s.strip,
        line2: @params[:line2].to_s.strip.presence,
        city: @params[:city].to_s.strip,
        province: @params[:province].to_s.strip,
        postal_code: @params[:postal_code].to_s.strip.presence
      )

      return ServiceResult.failure(errors: address.errors.to_hash) unless address.valid?

      Commerce::ShippingAddress.transaction do
        if @make_default
          @user.shipping_addresses.where.not(id: address.id).update_all(default_address: false)
          address.default_address = true
        end
        address.save!
      end

      ServiceResult.success(address)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
