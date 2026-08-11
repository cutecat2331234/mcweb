# frozen_string_literal: true

module Mcweb
  # Active Record's Ruby schema format does not include standalone PostgreSQL
  # sequences or triggers. Keep authority counters and trigger-backed database
  # invariants in fresh databases by appending their definitions to schema.rb.
  module PostgresqlSchemaDumper
    private

    def trailer(stream)
      dump_postgresql_sequences(stream)
      dump_postgresql_triggers(stream)
      super
    end

    def dump_postgresql_sequences(stream)
      rows = postgresql_sequence_rows.reject do |row|
        ignored?(row.fetch("sequence_name")) ||
          ignored?("#{row.fetch('sequence_schema')}.#{row.fetch('sequence_name')}")
      end
      return if rows.empty?

      stream.puts
      stream.puts "  # Standalone PostgreSQL sequences."
      stream.puts "  # Column-owned sequences are emitted with their tables by Active Record."
      rows.each { |row| write_execute(stream, sequence_definition(row)) }
      stream.puts
    end

    def postgresql_sequence_rows
      schemas = instance_variable_get(:@dump_schemas)
      schemas = @connection.current_schemas if schemas.blank?
      return [] if schemas.empty?

      quoted_schemas = schemas.map { |schema| @connection.quote(schema) }.join(", ")

      @connection.select_all(<<~SQL.squish, "McWeb PostgreSQL sequence schema dump").to_a
        SELECT
          sequence_namespace.nspname AS sequence_schema,
          sequence_object.relname AS sequence_name,
          format_type(sequence_data.seqtypid, NULL) AS data_type,
          sequence_data.seqstart AS start_value,
          sequence_data.seqincrement AS increment_by,
          sequence_data.seqmin AS minimum_value,
          sequence_data.seqmax AS maximum_value,
          sequence_data.seqcache AS cache_size,
          sequence_data.seqcycle AS cycles
        FROM pg_class sequence_object
        INNER JOIN pg_namespace sequence_namespace
          ON sequence_namespace.oid = sequence_object.relnamespace
        INNER JOIN pg_sequence sequence_data
          ON sequence_data.seqrelid = sequence_object.oid
        LEFT JOIN pg_depend ownership_dependency
          ON ownership_dependency.classid = 'pg_class'::regclass
          AND ownership_dependency.objid = sequence_object.oid
          AND ownership_dependency.refclassid = 'pg_class'::regclass
          AND ownership_dependency.deptype IN ('a', 'i')
        LEFT JOIN pg_depend extension_dependency
          ON extension_dependency.classid = 'pg_class'::regclass
          AND extension_dependency.objid = sequence_object.oid
          AND extension_dependency.refclassid = 'pg_extension'::regclass
          AND extension_dependency.deptype = 'e'
        WHERE sequence_object.relkind = 'S'
          AND sequence_namespace.nspname IN (#{quoted_schemas})
          AND ownership_dependency.objid IS NULL
          AND extension_dependency.objid IS NULL
        ORDER BY sequence_namespace.nspname, sequence_object.relname
      SQL
    end

    def sequence_definition(row)
      data_type = row.fetch("data_type")
      raise ArgumentError, "unsupported PostgreSQL sequence type" unless data_type.in?(%w[smallint integer bigint])

      name = @connection.quote_table_name(
        "#{row.fetch('sequence_schema')}.#{row.fetch('sequence_name')}"
      )
      cycle = row.fetch("cycles") ? "CYCLE" : "NO CYCLE"
      <<~SQL.squish
        CREATE SEQUENCE #{name}
        AS #{data_type}
        INCREMENT BY #{Integer(row.fetch('increment_by'))}
        MINVALUE #{Integer(row.fetch('minimum_value'))}
        MAXVALUE #{Integer(row.fetch('maximum_value'))}
        START WITH #{Integer(row.fetch('start_value'))}
        CACHE #{Integer(row.fetch('cache_size'))}
        #{cycle}
      SQL
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
      statement.each_line(chomp: true) do |line|
        normalized = line.rstrip
        normalized.empty? ? stream.puts : stream.puts("    #{normalized}")
      end
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
