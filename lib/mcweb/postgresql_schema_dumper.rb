# frozen_string_literal: true

module Mcweb
  # Active Record's Ruby schema format does not include PostgreSQL triggers.
  # Keep trigger-backed database invariants in fresh databases by appending the
  # user-defined trigger functions and triggers to db/schema.rb.
  module PostgresqlSchemaDumper
    private

    def trailer(stream)
      dump_postgresql_triggers(stream)
      super
    end

    def dump_postgresql_triggers(stream)
      rows = postgresql_trigger_rows.reject do |row|
        ignored?(row.fetch("table_name")) ||
          ignored?("#{row.fetch('table_schema')}.#{row.fetch('table_name')}")
      end
      return if rows.empty?

      stream.puts
      stream.puts "  # User-defined PostgreSQL trigger functions and triggers."
      stream.puts "  # These database invariants must also exist after db:schema:load."

      rows.reject { |row| row.fetch("function_owned_by_extension") == 1 }
        .uniq { |row| row.fetch("function_oid") }
        .sort_by { |row| [ row.fetch("function_schema"), row.fetch("function_name"), row.fetch("function_oid") ] }
        .each { |row| write_execute(stream, row.fetch("function_definition")) }

      rows.sort_by { |row| [ row.fetch("table_schema"), row.fetch("table_name"), row.fetch("trigger_name") ] }
        .each do |row|
          write_execute(stream, row.fetch("trigger_definition"))
          write_trigger_state(stream, row)
        end

      stream.puts
    end

    def postgresql_trigger_rows
      schemas = instance_variable_get(:@dump_schemas)
      schemas = @connection.current_schemas if schemas.blank?
      return [] if schemas.empty?

      quoted_schemas = schemas.map { |schema| @connection.quote(schema) }.join(", ")

      @connection.select_all(<<~SQL.squish, "McWeb PostgreSQL trigger schema dump").to_a
        SELECT
          trigger_object.oid AS trigger_oid,
          table_namespace.nspname AS table_schema,
          table_object.relname AS table_name,
          trigger_object.tgname AS trigger_name,
          trigger_object.tgenabled AS trigger_enabled,
          function_object.oid AS function_oid,
          function_namespace.nspname AS function_schema,
          function_object.proname AS function_name,
          pg_get_triggerdef(trigger_object.oid, false) AS trigger_definition,
          pg_get_functiondef(function_object.oid) AS function_definition,
          CASE WHEN extension_dependency.objid IS NULL THEN 0 ELSE 1 END AS function_owned_by_extension
        FROM pg_trigger trigger_object
        INNER JOIN pg_class table_object
          ON table_object.oid = trigger_object.tgrelid
        INNER JOIN pg_namespace table_namespace
          ON table_namespace.oid = table_object.relnamespace
        INNER JOIN pg_proc function_object
          ON function_object.oid = trigger_object.tgfoid
        INNER JOIN pg_namespace function_namespace
          ON function_namespace.oid = function_object.pronamespace
        LEFT JOIN pg_depend extension_dependency
          ON extension_dependency.classid = 'pg_proc'::regclass
          AND extension_dependency.objid = function_object.oid
          AND extension_dependency.refclassid = 'pg_extension'::regclass
          AND extension_dependency.deptype = 'e'
        WHERE trigger_object.tgisinternal = FALSE
          AND table_object.relkind IN ('r', 'p')
          AND table_namespace.nspname IN (#{quoted_schemas})
        ORDER BY
          table_namespace.nspname,
          table_object.relname,
          trigger_object.tgname
      SQL
    end

    def write_execute(stream, sql)
      statement = sql.rstrip
      statement = "#{statement};" unless statement.end_with?(";")
      delimiter = heredoc_delimiter(statement)

      stream.puts "  execute <<~'#{delimiter}'"
      statement.each_line { |line| stream.print "    #{line}" }
      stream.puts unless statement.end_with?("\n")
      stream.puts "  #{delimiter}"
      stream.puts
    end

    def write_trigger_state(stream, row)
      state = row.fetch("trigger_enabled")
      action = {
        "D" => "DISABLE TRIGGER",
        "A" => "ENABLE ALWAYS TRIGGER",
        "R" => "ENABLE REPLICA TRIGGER"
      }.fetch(state, nil)
      return unless action

      table = @connection.quote_table_name("#{row.fetch('table_schema')}.#{row.fetch('table_name')}")
      trigger = @connection.quote_column_name(row.fetch("trigger_name"))
      write_execute(stream, "ALTER TABLE #{table} #{action} #{trigger}")
    end

    def heredoc_delimiter(statement)
      suffix = 0
      loop do
        delimiter = suffix.zero? ? "MCWEB_SCHEMA_SQL" : "MCWEB_SCHEMA_SQL_#{suffix}"
        return delimiter unless statement.lines.any? { |line| line.chomp == delimiter }

        suffix += 1
      end
    end
  end
end
