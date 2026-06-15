# frozen_string_literal: true

module Commerce
  class ShippingAddressesController < ApplicationController
    before_action :require_login
    before_action :set_address, only: %i[update destroy make_default]

    def index
      addresses = current_user.shipping_addresses.ordered
      render inertia: "Commerce/ShippingAddresses/Index", props: {
        addresses: addresses.map { |address| serialize_address(address) }
      }
    end

    def create
      result = Commerce::UpsertShippingAddress.call(
        user: current_user,
        params: address_params,
        make_default: params[:make_default] == "1" || params[:make_default] == true
      )

      if result.success?
        redirect_to store_shipping_addresses_path, notice: "地址已保存。"
      else
        redirect_to store_shipping_addresses_path, alert: service_error_message(result)
      end
    end

    def update
      result = Commerce::UpsertShippingAddress.call(
        user: current_user,
        params: address_params,
        address: @address,
        make_default: params[:make_default] == "1" || params[:make_default] == true
      )

      if result.success?
        redirect_to store_shipping_addresses_path, notice: "地址已更新。"
      else
        redirect_to store_shipping_addresses_path, alert: service_error_message(result)
      end
    end

    def destroy
      @address.destroy!
      redirect_to store_shipping_addresses_path, notice: "地址已删除。"
    end

    def make_default
      Commerce::ShippingAddress.transaction do
        current_user.shipping_addresses.update_all(default_address: false)
        @address.update!(default_address: true)
      end
      redirect_to store_shipping_addresses_path, notice: "已设为默认地址。"
    end

    private

    def set_address
      @address = current_user.shipping_addresses.find(params[:id])
    end

    def address_params
      params.require(:address).permit(:label, :name, :phone, :line1, :line2, :city, :province, :postal_code)
    end

    def serialize_address(address)
      {
        id: address.id,
        label: address.label,
        summary: address.summary_label,
        name: address.name,
        phone: address.phone,
        line1: address.line1,
        line2: address.line2,
        city: address.city,
        province: address.province,
        postal_code: address.postal_code,
        default_address: address.default_address?,
        make_default_url: make_default_store_shipping_address_path(address),
        update_url: store_shipping_address_path(address),
        delete_url: store_shipping_address_path(address)
      }
    end
  end
end
