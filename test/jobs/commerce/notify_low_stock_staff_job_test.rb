# frozen_string_literal: true

require "test_helper"

module Commerce
  class NotifyLowStockStaffJobTest < ActiveJob::TestCase
    test "read and manage permissions receive low stock notifications from roles or identity groups" do
      product = Commerce::Product.create!(
        name: "Low stock item",
        slug: "low-stock-item-#{SecureRandom.hex(4)}",
        product_type: "virtual",
        status: :active,
        price_cents: 100,
        currency: "CNY",
        minimum_quantity: 1,
        stock: 1
      )
      reader = create_user
      manager = create_user
      group_reader = create_user
      admin_only = create_user
      grant_permission(reader, "store.products.read")
      grant_permission(manager, "store.products.manage")
      grant_permission(admin_only, "admin.access")
      group = Community::UserGroup.create!(
        name: "Stock readers",
        priority: 1,
        permissions: [ "store.products.read" ]
      )
      Community::GroupMembership.create!(
        user: group_reader,
        user_group: group,
        is_primary: true
      )

      Commerce::NotifyLowStockStaffJob.perform_now(product.id)

      [ reader, manager, group_reader ].each do |recipient|
        assert Notification.exists?(
          user: recipient,
          notification_type: "commerce.low_stock"
        )
      end
      assert_not Notification.exists?(
        user: admin_only,
        notification_type: "commerce.low_stock"
      )
    end
  end
end
