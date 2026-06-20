# frozen_string_literal: true

class AddFulfillmentUniquenessIndexes < ActiveRecord::Migration[8.0]
  def up
    dedupe_fulfillments
    dedupe_connector_tasks

    remove_index :store_fulfillments, :store_order_item_id, if_exists: true
    add_index :store_fulfillments, :store_order_item_id, unique: true

    remove_index :minecraft_connector_tasks, :store_fulfillment_id, if_exists: true
    add_index :minecraft_connector_tasks, :store_fulfillment_id, unique: true
  end

  def down
    remove_index :store_fulfillments, :store_order_item_id, if_exists: true
    add_index :store_fulfillments, :store_order_item_id

    remove_index :minecraft_connector_tasks, :store_fulfillment_id, if_exists: true
    add_index :minecraft_connector_tasks, :store_fulfillment_id
  end

  private

  def dedupe_fulfillments
    execute <<~SQL.squish
      DELETE FROM store_fulfillments
      WHERE id NOT IN (
        SELECT MIN(id) FROM store_fulfillments GROUP BY store_order_item_id
      )
    SQL
  end

  def dedupe_connector_tasks
    execute <<~SQL.squish
      DELETE FROM minecraft_connector_tasks
      WHERE id NOT IN (
        SELECT MIN(id) FROM minecraft_connector_tasks
        WHERE store_fulfillment_id IS NOT NULL
        GROUP BY store_fulfillment_id
      )
    SQL
  end
end
