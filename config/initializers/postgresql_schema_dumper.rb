# frozen_string_literal: true

require "active_record/schema_dumper"
require "active_record/connection_adapters/abstract/schema_dumper"
require "active_record/connection_adapters/postgresql/schema_dumper"
require "mcweb/postgresql_schema_dumper"

postgresql_dumper = ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper
postgresql_dumper.prepend(Mcweb::PostgresqlSchemaDumper) unless postgresql_dumper < Mcweb::PostgresqlSchemaDumper
