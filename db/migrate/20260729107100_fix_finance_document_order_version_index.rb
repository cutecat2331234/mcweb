# frozen_string_literal: true

class FixFinanceDocumentOrderVersionIndex < ActiveRecord::Migration[8.1]
  INDEX_NAME = "idx_finance_documents_order_kind_version"

  def up
    remove_index :store_finance_documents, name: INDEX_NAME, if_exists: true
    add_index :store_finance_documents,
      %i[store_order_id document_kind version],
      unique: true,
      where: "document_kind = 'invoice'",
      name: INDEX_NAME
  end

  def down
    remove_index :store_finance_documents, name: INDEX_NAME, if_exists: true
    add_index :store_finance_documents,
      %i[store_order_id document_kind version],
      unique: true,
      name: INDEX_NAME
  end
end
