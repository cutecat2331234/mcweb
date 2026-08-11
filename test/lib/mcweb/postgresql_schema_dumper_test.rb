# frozen_string_literal: true

require "test_helper"
require "stringio"

module Mcweb
  class PostgresqlSchemaDumperTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @connection = ActiveRecord::Base.connection
      @schema = "mcweb_trigger_contract_#{Process.pid}_#{SecureRandom.hex(4)}"
      @quoted_schema = @connection.quote_column_name(@schema)
      @original_dump_schemas = ActiveRecord.dump_schemas
      @original_schema_search_path = @connection.schema_search_path

      @connection.execute("CREATE SCHEMA #{@quoted_schema}")
      @connection.schema_search_path = "#{@schema}, public"
    end

    teardown do
      ActiveRecord.dump_schemas = @original_dump_schemas
      @connection.schema_search_path = @original_schema_search_path
      @connection.execute("DROP SCHEMA IF EXISTS #{@quoted_schema} CASCADE")
    end

    test "schema dump and fresh load preserve trigger-backed invariants" do
      create_append_only_ledger
      source = dump_schema

      assert_includes source, "CREATE OR REPLACE FUNCTION #{@schema}.reject_ledger_change()"
      assert_includes source, "CREATE TRIGGER ledger_entries_immutable"
      assert_includes source, "User-defined PostgreSQL trigger functions and triggers"
      refute source.lines.any? { |line| line.match?(/[ \t]+\r?\n\z/) },
             "schema dump must not add trailing whitespace to blank SQL lines"

      reload_schema(source)

      assert_equal 1, user_trigger_count
      @connection.execute("INSERT INTO #{@quoted_schema}.ledger_entries (payload) VALUES ('original')")

      error = assert_raises(ActiveRecord::StatementInvalid) do
        @connection.execute("UPDATE #{@quoted_schema}.ledger_entries SET payload = 'changed'")
      end
      assert_match(/ledger_entries is append-only/, error.message)
    end

    test "fresh load preserves a non-default trigger state" do
      create_append_only_ledger
      @connection.execute(<<~SQL)
        ALTER TABLE #{@quoted_schema}.ledger_entries
        DISABLE TRIGGER ledger_entries_immutable
      SQL

      source = dump_schema

      assert_includes source, "DISABLE TRIGGER \"ledger_entries_immutable\""
      reload_schema(source)
      assert_equal "D", trigger_state
    end

    test "schema dump and fresh load preserve standalone sequences without duplicating column-owned sequences" do
      create_append_only_ledger
      @connection.execute(<<~SQL)
        CREATE SEQUENCE #{@quoted_schema}.authority_version_seq
        AS bigint
        INCREMENT BY 7
        MINVALUE 7
        MAXVALUE 7000
        START WITH 21
        CACHE 3
        CYCLE
      SQL

      source = dump_schema

      assert_includes source, "Standalone PostgreSQL sequences"
      assert_includes source, "CREATE SEQUENCE \"#{@schema}\".\"authority_version_seq\""
      assert_includes source, "INCREMENT BY 7"
      assert_includes source, "START WITH 21"
      assert_includes source, "CACHE 3"
      assert_includes source, "CYCLE"
      refute_includes source, "CREATE SEQUENCE \"#{@schema}\".\"ledger_entries_id_seq\""

      reload_schema(source)

      assert_equal 21, @connection.select_value(
        "SELECT nextval(#{@connection.quote("#{@schema}.authority_version_seq")})"
      ).to_i
      assert_equal 1, standalone_sequence_count
    end

    private

    def create_append_only_ledger
      @connection.execute(<<~SQL)
        CREATE TABLE #{@quoted_schema}.ledger_entries (
          id bigserial PRIMARY KEY,
          payload text NOT NULL
        );

        CREATE FUNCTION #{@quoted_schema}.reject_ledger_change()
        RETURNS trigger AS $function$
        BEGIN

          RAISE EXCEPTION '% is append-only', TG_TABLE_NAME
            USING ERRCODE = 'integrity_constraint_violation';
        END;
        $function$ LANGUAGE plpgsql;

        CREATE TRIGGER ledger_entries_immutable
        BEFORE UPDATE OR DELETE ON #{@quoted_schema}.ledger_entries
        FOR EACH ROW EXECUTE FUNCTION #{@quoted_schema}.reject_ledger_change();
      SQL
    end

    def dump_schema
      ActiveRecord.dump_schemas = @schema
      schema = StringIO.new
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, schema)
      schema.string
    end

    def reload_schema(source)
      @connection.schema_search_path = "public"
      @connection.execute("DROP SCHEMA #{@quoted_schema} CASCADE")
      @connection.schema_search_path = "#{@schema}, public"
      eval(source, TOPLEVEL_BINDING, "mcweb_trigger_schema_contract.rb") # rubocop:disable Security/Eval
    end

    def trigger_state
      @connection.select_value(<<~SQL)
        SELECT trigger_object.tgenabled
        FROM pg_trigger trigger_object
        INNER JOIN pg_class table_object ON table_object.oid = trigger_object.tgrelid
        INNER JOIN pg_namespace table_namespace ON table_namespace.oid = table_object.relnamespace
        WHERE trigger_object.tgisinternal = FALSE
          AND table_namespace.nspname = #{@connection.quote(@schema)}
          AND table_object.relname = 'ledger_entries'
          AND trigger_object.tgname = 'ledger_entries_immutable'
      SQL
    end

    def user_trigger_count
      @connection.select_value(<<~SQL).to_i
        SELECT COUNT(*)
        FROM pg_trigger trigger_object
        INNER JOIN pg_class table_object ON table_object.oid = trigger_object.tgrelid
        INNER JOIN pg_namespace table_namespace ON table_namespace.oid = table_object.relnamespace
        WHERE trigger_object.tgisinternal = FALSE
          AND table_namespace.nspname = #{@connection.quote(@schema)}
          AND table_object.relname = 'ledger_entries'
      SQL
    end

    def standalone_sequence_count
      @connection.select_value(<<~SQL).to_i
        SELECT COUNT(*)
        FROM pg_class sequence_object
        INNER JOIN pg_namespace sequence_namespace
          ON sequence_namespace.oid = sequence_object.relnamespace
        WHERE sequence_object.relkind = 'S'
          AND sequence_namespace.nspname = #{@connection.quote(@schema)}
          AND sequence_object.relname = 'authority_version_seq'
      SQL
    end
  end
end
