# frozen_string_literal: true

class AddReasonKindToStoreRefunds < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LEGACY_REASON_KINDS = {
    "customer_request" => [ "Customer request", "客户申请" ],
    "admin_refund" => [ "Admin refund", "后台退款" ],
    "superseded_by_admin_refund" => [ "Superseded by admin refund", "已被后台退款取代" ]
  }.freeze

  def up
    add_column :store_refunds, :reason_kind, :string
    add_check_constraint :store_refunds,
      "reason_kind IS NULL OR " \
        "(reason IS NULL AND reason_kind IN " \
        "('customer_request', 'admin_refund', 'superseded_by_admin_refund'))",
      name: "store_refunds_reason_kind_valid",
      validate: false

    LEGACY_REASON_KINDS.each do |kind, reasons|
      quoted_reasons = reasons.map { |reason| connection.quote(reason) }.join(", ")
      request_scope = case kind
      when "customer_request" then "AND requested_by_customer = TRUE"
      when "admin_refund" then "AND requested_by_customer = FALSE"
      else ""
      end
      execute <<~SQL.squish
        UPDATE store_refunds
        SET reason_kind = #{connection.quote(kind)}, reason = NULL
        WHERE reason IN (#{quoted_reasons})
          #{request_scope}
      SQL
    end
    validate_check_constraint :store_refunds, name: "store_refunds_reason_kind_valid"
  end

  def down
    LEGACY_REASON_KINDS.each do |kind, reasons|
      execute <<~SQL.squish
        UPDATE store_refunds
        SET reason = #{connection.quote(reasons.first)}
        WHERE reason_kind = #{connection.quote(kind)} AND reason IS NULL
      SQL
    end
    remove_check_constraint :store_refunds, name: "store_refunds_reason_kind_valid"
    remove_column :store_refunds, :reason_kind
  end
end
