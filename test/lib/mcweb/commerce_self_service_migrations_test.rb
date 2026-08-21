# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260821100000_add_commerce_self_service_lifecycles")
require Rails.root.join("db/migrate/20260821100500_add_commerce_self_service_indexes")
require Rails.root.join("db/migrate/20260821101000_add_commerce_self_service_state_shapes")
require Rails.root.join("db/migrate/20260821102000_add_revisions_to_commerce_user_content")
require Rails.root.join("db/migrate/20260821103000_add_reason_kind_to_store_refunds")
require Rails.root.join("db/migrate/20260821104000_add_provider_unknown_refund_status")
require Rails.root.join("db/migrate/20260821105000_enforce_one_active_payment_per_order")

class CommerceSelfServiceMigrationsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @connection = ApplicationRecord.connection
    @original_search_path = @connection.schema_search_path
    @original_migration_verbosity = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    @schema_name = "commerce_migration_#{SecureRandom.hex(6)}"
    @connection.execute("CREATE SCHEMA #{@connection.quote_table_name(@schema_name)}")
    @connection.schema_search_path = @schema_name
    @connection.schema_cache.clear!
    create_legacy_tables!
  end

  teardown do
    @connection.schema_search_path = @original_search_path
    @connection.schema_cache.clear!
    @connection.execute("DROP SCHEMA IF EXISTS #{@connection.quote_table_name(@schema_name)} CASCADE")
    ActiveRecord::Migration.verbose = @original_migration_verbosity
  end

  test "lifecycle migration resumes after columns and an unvalidated constraint already exist" do
    @connection.add_column :store_refunds, :withdrawn_at, :datetime
    @connection.add_column :store_refunds, :withdrawn_by_id, :bigint
    @connection.add_foreign_key :store_refunds,
      :users,
      column: :withdrawn_by_id,
      validate: false
    @connection.add_check_constraint :store_reviews,
      "status IN ('published', 'hidden', 'deleted')",
      name: "store_reviews_status_valid",
      validate: false

    migration = migration_for(AddCommerceSelfServiceLifecycles)
    migration.up
    migration.up

    assert @connection.column_exists?(:store_refunds, :withdrawn_by_id)
    assert @connection.foreign_key_exists?(:store_refunds, :users, column: :withdrawn_by_id)
    assert constraint_validated?(:store_reviews, "store_reviews_status_valid")
    assert constraint_validated?(:store_refunds, "store_refunds_status_valid")

    migration.down
    migration.down
    assert_not @connection.column_exists?(:store_refunds, :withdrawn_at)
    assert_not @connection.check_constraint_exists?(:store_reviews, name: "store_reviews_status_valid")
  end

  test "concurrent index migration resumes with one index already complete" do
    migration_for(AddCommerceSelfServiceLifecycles).up
    @connection.add_index :store_refunds,
      :withdrawn_by_id,
      name: "index_store_refunds_on_withdrawn_by_id",
      algorithm: :concurrently
    @connection.execute(<<~SQL.squish)
      INSERT INTO store_product_answers (store_product_question_id, status)
      VALUES (99, 'published'), (99, 'published')
    SQL
    assert_raises(ActiveRecord::StatementInvalid) do
      @connection.execute(<<~SQL.squish)
        CREATE UNIQUE INDEX CONCURRENTLY index_store_product_answers_on_question_and_status
        ON store_product_answers (store_product_question_id, status)
      SQL
    end
    assert_not postgres_index_valid?("index_store_product_answers_on_question_and_status")

    migration = migration_for(AddCommerceSelfServiceIndexes)
    migration.up
    migration.up

    assert postgres_index_valid?("index_store_refunds_on_withdrawn_by_id")
    assert postgres_index_valid?("index_store_product_answers_on_question_and_status")

    migration.down
    migration.down
    assert_not @connection.index_exists?(:store_refunds, name: "index_store_refunds_on_withdrawn_by_id")
  end

  test "state shape migration resumes with a partially installed constraint set" do
    migration_for(AddCommerceSelfServiceLifecycles).up
    @connection.add_check_constraint :store_refunds,
      "(status = 'withdrawn' AND withdrawn_at IS NOT NULL AND withdrawn_by_id IS NOT NULL) OR " \
        "(status <> 'withdrawn' AND withdrawn_at IS NULL AND withdrawn_by_id IS NULL)",
      name: "store_refunds_withdrawn_shape",
      validate: false

    migration = migration_for(AddCommerceSelfServiceStateShapes)
    migration.up
    migration.up

    %w[
      store_refunds_withdrawn_shape
      store_reviews_deleted_shape
      store_product_questions_deleted_shape
      store_product_answers_deleted_shape
    ].each do |name|
      table = name.sub(/_(withdrawn|deleted)_shape\z/, "")
      assert constraint_validated?(table, name), name
    end

    migration.down
    migration.down
  end

  test "revision migration resumes after only one lock column was installed" do
    migration_for(AddCommerceSelfServiceLifecycles).up
    @connection.add_column :store_reviews, :lock_version, :integer, null: false, default: 0
    @connection.add_check_constraint :store_reviews,
      "lock_version >= 0",
      name: "store_reviews_lock_version_nonnegative",
      validate: false

    migration = migration_for(AddRevisionsToCommerceUserContent)
    migration.up
    migration.up

    %i[store_reviews store_product_questions store_product_answers].each do |table|
      assert @connection.column_exists?(table, :lock_version)
      assert constraint_validated?(table, "#{table}_lock_version_nonnegative")
    end

    migration.down
    migration.down
  end

  test "reason kind backfill resumes in batches and rollback restores exact legacy values" do
    ids = {
      english_customer: insert_refund(reason: "Customer request", customer: true),
      chinese_customer: insert_refund(reason: "客户申请", customer: true),
      freeform_customer: insert_refund(reason: "The package arrived damaged", customer: true),
      blank_customer: insert_refund(reason: nil, customer: true),
      english_admin: insert_refund(reason: "Admin refund", customer: false),
      chinese_superseded: insert_refund(reason: "已被后台退款取代", customer: false)
    }
    migration = migration_for(AddReasonKindToStoreRefunds)
    @connection.add_column :store_refunds, :reason_kind, :string
    migration.send(:ensure_backfill_ledger!)
    @connection.execute(<<~SQL.squish)
      INSERT INTO store_refund_reason_kind_backfills (store_refund_id, legacy_reason)
      VALUES (#{ids.fetch(:english_customer)}, 'Customer request')
    SQL
    @connection.execute(<<~SQL.squish)
      UPDATE store_refunds
      SET reason = NULL, reason_kind = 'customer_request'
      WHERE id = #{ids.fetch(:english_customer)}
    SQL

    migration.up
    migration.up

    assert_equal "customer_request", refund_value(ids.fetch(:chinese_customer), :reason_kind)
    assert_equal "customer_request", refund_value(ids.fetch(:freeform_customer), :reason_kind)
    assert_equal "customer_request", refund_value(ids.fetch(:blank_customer), :reason_kind)
    assert_equal "admin_refund", refund_value(ids.fetch(:english_admin), :reason_kind)
    assert_equal "superseded_by_admin_refund", refund_value(ids.fetch(:chinese_superseded), :reason_kind)
    assert_nil refund_value(ids.fetch(:chinese_customer), :reason)
    assert_equal "The package arrived damaged", refund_value(ids.fetch(:freeform_customer), :reason)
    assert_nil refund_value(ids.fetch(:blank_customer), :reason)
    assert_equal 6, @connection.select_value("SELECT COUNT(*) FROM store_refund_reason_kind_backfills").to_i

    new_refund_id = insert_refund(
      reason: "Verified support exception",
      customer: false,
      reason_kind: "admin_refund"
    )
    new_default_refund_id = insert_refund(reason: nil, customer: false, reason_kind: "admin_refund")
    migration.down
    migration.down

    assert_equal "Customer request", refund_value(ids.fetch(:english_customer), :reason)
    assert_equal "客户申请", refund_value(ids.fetch(:chinese_customer), :reason)
    assert_equal "The package arrived damaged", refund_value(ids.fetch(:freeform_customer), :reason)
    assert_nil refund_value(ids.fetch(:blank_customer), :reason)
    assert_equal "Admin refund", refund_value(ids.fetch(:english_admin), :reason)
    assert_equal "已被后台退款取代", refund_value(ids.fetch(:chinese_superseded), :reason)
    assert_equal "Verified support exception", refund_value(new_refund_id, :reason)
    assert_equal "Admin refund", refund_value(new_default_refund_id, :reason)
    assert_not @connection.column_exists?(:store_refunds, :reason_kind)
    assert_not @connection.table_exists?(:store_refund_reason_kind_backfills)
  end

  test "provider unknown status migration resumes between validation removal and rename" do
    migration_for(AddCommerceSelfServiceLifecycles).up
    @connection.add_check_constraint :store_refunds,
      AddProviderUnknownRefundStatus::UP_EXPRESSION,
      name: AddProviderUnknownRefundStatus::UP_CONSTRAINT_NAME,
      validate: false

    migration = migration_for(AddProviderUnknownRefundStatus)
    migration.up
    migration.up

    definition = constraint_definition(:store_refunds, AddProviderUnknownRefundStatus::CONSTRAINT_NAME)
    assert_includes definition, "provider_unknown"
    assert constraint_validated?(:store_refunds, AddProviderUnknownRefundStatus::CONSTRAINT_NAME)
    assert_not @connection.check_constraint_exists?(
      :store_refunds,
      name: AddProviderUnknownRefundStatus::UP_CONSTRAINT_NAME
    )

    migration.down
    migration.down
    definition = constraint_definition(:store_refunds, AddProviderUnknownRefundStatus::CONSTRAINT_NAME)
    refute_includes definition, "provider_unknown"
  end

  test "active payment index recovers from a failed concurrent unique index build" do
    order_id = @connection.select_value(<<~SQL.squish).to_i
      INSERT INTO store_orders DEFAULT VALUES RETURNING id
    SQL
    first_id = insert_payment(order_id:, status: "pending")
    second_id = insert_payment(order_id:, status: "processing")

    migration = migration_for(EnforceOneActivePaymentPerOrder)
    duplicate_error = assert_raises(ActiveRecord::MigrationError) { migration.up }
    assert_includes duplicate_error.message, order_id.to_s
    assert_not postgres_index_present?(EnforceOneActivePaymentPerOrder::INDEX_NAME)

    assert_raises(ActiveRecord::StatementInvalid) do
      @connection.execute(<<~SQL.squish)
        CREATE UNIQUE INDEX CONCURRENTLY #{EnforceOneActivePaymentPerOrder::INDEX_NAME}
        ON payment_records (store_order_id)
        WHERE #{EnforceOneActivePaymentPerOrder::ACTIVE_PREDICATE}
      SQL
    end
    assert postgres_index_present?(EnforceOneActivePaymentPerOrder::INDEX_NAME)
    assert_not postgres_index_valid?(EnforceOneActivePaymentPerOrder::INDEX_NAME)

    @connection.execute("DELETE FROM payment_records WHERE id = #{second_id}")
    migration.up
    migration.up

    assert postgres_index_valid?(EnforceOneActivePaymentPerOrder::INDEX_NAME)
    assert_raises(ActiveRecord::RecordNotUnique) do
      insert_payment(order_id:, status: "processing")
    end
    insert_payment(order_id:, status: "succeeded")
    assert_equal first_id, @connection.select_value("SELECT id FROM payment_records WHERE status = 'pending'").to_i

    migration.down
    migration.down
    assert_not postgres_index_present?(EnforceOneActivePaymentPerOrder::INDEX_NAME)
  end

  private

  def create_legacy_tables!
    @connection.execute(<<~SQL)
      CREATE TABLE users (
        id bigserial PRIMARY KEY
      );
      CREATE TABLE store_refunds (
        id bigserial PRIMARY KEY,
        status varchar NOT NULL DEFAULT 'pending',
        reason text,
        requested_by_customer boolean NOT NULL DEFAULT false
      );
      CREATE TABLE store_reviews (
        id bigserial PRIMARY KEY,
        status varchar NOT NULL DEFAULT 'published'
      );
      CREATE TABLE store_product_questions (
        id bigserial PRIMARY KEY,
        status varchar NOT NULL DEFAULT 'published'
      );
      CREATE TABLE store_product_answers (
        id bigserial PRIMARY KEY,
        store_product_question_id bigint NOT NULL
      );
      CREATE TABLE store_orders (
        id bigserial PRIMARY KEY
      );
      CREATE TABLE payment_records (
        id bigserial PRIMARY KEY,
        store_order_id bigint NOT NULL,
        status varchar NOT NULL DEFAULT 'pending'
      );
    SQL
  end

  def migration_for(migration_class)
    migration_class.new.tap do |migration|
      migration.instance_variable_set(:@connection, @connection)
    end
  end

  def insert_refund(reason:, customer:, reason_kind: :column_absent)
    columns = [ "status", "reason", "requested_by_customer" ]
    values = [ "'pending'", @connection.quote(reason), @connection.quote(customer) ]
    unless reason_kind == :column_absent
      columns << "reason_kind"
      values << @connection.quote(reason_kind)
    end
    @connection.select_value(<<~SQL.squish).to_i
      INSERT INTO store_refunds (#{columns.join(', ')})
      VALUES (#{values.join(', ')})
      RETURNING id
    SQL
  end

  def refund_value(id, column)
    @connection.select_value(<<~SQL.squish)
      SELECT #{@connection.quote_column_name(column)}
      FROM store_refunds
      WHERE id = #{Integer(id)}
    SQL
  end

  def insert_payment(order_id:, status:)
    @connection.select_value(<<~SQL.squish).to_i
      INSERT INTO payment_records (store_order_id, status)
      VALUES (#{Integer(order_id)}, #{@connection.quote(status)})
      RETURNING id
    SQL
  end

  def constraint_validated?(table, name)
    @connection.select_value(<<~SQL.squish) == true
      SELECT constraint_state.convalidated
      FROM pg_constraint constraint_state
      WHERE constraint_state.conrelid = #{@connection.quote(table.to_s)}::regclass
        AND constraint_state.conname = #{@connection.quote(name)}
    SQL
  end

  def constraint_definition(table, name)
    @connection.select_value(<<~SQL.squish)
      SELECT pg_get_constraintdef(constraint_state.oid, true)
      FROM pg_constraint constraint_state
      WHERE constraint_state.conrelid = #{@connection.quote(table.to_s)}::regclass
        AND constraint_state.conname = #{@connection.quote(name)}
    SQL
  end

  def postgres_index_valid?(name)
    @connection.select_value(<<~SQL.squish) == true
      SELECT index_state.indisvalid AND index_state.indisready
      FROM pg_index index_state
      WHERE index_state.indexrelid = to_regclass(#{@connection.quote(name)})
    SQL
  end

  def postgres_index_present?(name)
    @connection.select_value(<<~SQL.squish).present?
      SELECT to_regclass(#{@connection.quote(name)})::oid
    SQL
  end
end
