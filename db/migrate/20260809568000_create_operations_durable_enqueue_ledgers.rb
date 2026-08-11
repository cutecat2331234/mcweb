# frozen_string_literal: true

class CreateOperationsDurableEnqueueLedgers < ActiveRecord::Migration[8.1]
  INTENT_HANDLER_PATTERN = "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$"
  SOURCE_KIND_PATTERN = "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$"
  QUEUE_PATTERN = "^[a-z][a-z0-9_]*$"
  DIGEST_PATTERN = "^[0-9a-f]{64}$"
  UUID_PATTERN = "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

  ATTEMPT_TRIGGERS = %w[after_commit maintenance manual].freeze
  EVENT_TYPES = %w[
    recorded
    enqueue_requested
    enqueue_succeeded
    enqueue_failed
    attempt_started
    lease_renewed
    attempt_succeeded
    attempt_skipped
    attempt_failed
    lease_expired
    retry_scheduled
    dead_lettered
    reopened
  ].freeze
  def up
    create_table :operations_durable_enqueue_intents do |t|
      t.string :public_id, null: false, limit: 36
      t.string :handler_key, null: false, limit: 120
      t.string :source_kind, null: false, limit: 120
      t.bigint :source_id, null: false
      t.string :dedupe_key, null: false, limit: 191
      t.string :queue_name, null: false, limit: 64
      t.jsonb :arguments, null: false, default: {}
      t.string :arguments_sha256, null: false, limit: 64
      t.datetime :requested_at, null: false
      t.timestamps
    end

    add_index :operations_durable_enqueue_intents, :public_id, unique: true
    add_index :operations_durable_enqueue_intents,
              [ :handler_key, :dedupe_key ],
              unique: true,
              name: "idx_operations_durable_intents_dedupe"
    add_index :operations_durable_enqueue_intents,
              [ :source_kind, :source_id ],
              name: "idx_operations_durable_intents_source"
    add_index :operations_durable_enqueue_intents,
              [ :handler_key, :requested_at, :id ],
              name: "idx_operations_durable_intents_handler"

    add_check_constraint :operations_durable_enqueue_intents,
                         "public_id ~ '#{UUID_PATTERN}'",
                         name: "operations_durable_intents_public_id"
    add_check_constraint :operations_durable_enqueue_intents,
                         "handler_key ~ '#{INTENT_HANDLER_PATTERN}'",
                         name: "operations_durable_intents_handler_key"
    add_check_constraint :operations_durable_enqueue_intents,
                         "source_kind ~ '#{SOURCE_KIND_PATTERN}'",
                         name: "operations_durable_intents_source_kind"
    add_check_constraint :operations_durable_enqueue_intents,
                         "source_id > 0",
                         name: "operations_durable_intents_source_id"
    add_check_constraint :operations_durable_enqueue_intents,
                         "dedupe_key ~ '^[a-zA-Z0-9][a-zA-Z0-9._:/-]*$'",
                         name: "operations_durable_intents_dedupe_key"
    add_check_constraint :operations_durable_enqueue_intents,
                         "queue_name ~ '#{QUEUE_PATTERN}'",
                         name: "operations_durable_intents_queue"
    add_check_constraint :operations_durable_enqueue_intents,
                         "jsonb_typeof(arguments) = 'object' AND octet_length(arguments::text) <= 8192",
                         name: "operations_durable_intents_arguments"
    add_check_constraint :operations_durable_enqueue_intents,
                         "arguments_sha256 ~ '#{DIGEST_PATTERN}'",
                         name: "operations_durable_intents_digest"

    create_table :operations_durable_enqueue_attempts do |t|
      t.references :intent,
                   null: false,
                   foreign_key: {
                     to_table: :operations_durable_enqueue_intents,
                     on_delete: :restrict
                   }
      t.integer :attempt_number, null: false
      t.integer :generation, null: false
      t.string :lease_token, null: false, limit: 36
      t.string :job_id, null: false, limit: 160
      t.string :trigger, null: false, limit: 32
      t.datetime :started_at, null: false
      t.datetime :lease_expires_at, null: false
      t.timestamps
    end

    add_index :operations_durable_enqueue_attempts,
              [ :intent_id, :attempt_number ],
              unique: true,
              name: "idx_operations_durable_attempts_sequence"
    add_index :operations_durable_enqueue_attempts,
              [ :intent_id, :generation, :attempt_number ],
              name: "idx_operations_durable_attempts_generation"
    add_index :operations_durable_enqueue_attempts, :lease_token, unique: true
    add_index :operations_durable_enqueue_attempts,
              [ :lease_expires_at, :intent_id ],
              name: "idx_operations_durable_attempts_lease"
    add_check_constraint :operations_durable_enqueue_attempts,
                         "attempt_number > 0",
                         name: "operations_durable_attempts_number"
    add_check_constraint :operations_durable_enqueue_attempts,
                         "generation > 0",
                         name: "operations_durable_attempts_generation"
    add_check_constraint :operations_durable_enqueue_attempts,
                         "lease_token ~ '#{UUID_PATTERN}'",
                         name: "operations_durable_attempts_lease_token"
    add_check_constraint :operations_durable_enqueue_attempts,
                         "trigger IN (#{quoted(ATTEMPT_TRIGGERS)})",
                         name: "operations_durable_attempts_trigger"
    add_check_constraint :operations_durable_enqueue_attempts,
                         "lease_expires_at > started_at",
                         name: "operations_durable_attempts_lease_window"

    create_table :operations_durable_enqueue_events do |t|
      t.references :intent,
                   null: false,
                   foreign_key: {
                     to_table: :operations_durable_enqueue_intents,
                     on_delete: :restrict
                   }
      t.references :attempt,
                   foreign_key: {
                     to_table: :operations_durable_enqueue_attempts,
                     on_delete: :restrict
                   }
      t.integer :sequence, null: false
      t.integer :generation, null: false
      t.string :event_type, null: false, limit: 64
      t.string :error_code, limit: 120
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :available_at
      t.datetime :lease_expires_at
      t.timestamps
    end

    add_index :operations_durable_enqueue_events,
              [ :intent_id, :sequence ],
              unique: true,
              name: "idx_operations_durable_events_sequence"
    add_index :operations_durable_enqueue_events,
              [ :intent_id, :generation, :sequence ],
              name: "idx_operations_durable_events_generation"
    add_index :operations_durable_enqueue_events,
              [ :event_type, :available_at, :intent_id ],
              name: "idx_operations_durable_events_recovery"
    add_index :operations_durable_enqueue_events,
              [ :attempt_id, :event_type ],
              name: "idx_operations_durable_events_attempt"
    add_index :operations_durable_enqueue_events,
              :attempt_id,
              unique: true,
              where: "event_type = 'attempt_started'",
              name: "idx_operations_durable_events_attempt_started"
    add_index :operations_durable_enqueue_events,
              :attempt_id,
              unique: true,
              where: "event_type IN ('attempt_succeeded', 'attempt_skipped', 'attempt_failed')",
              name: "idx_operations_durable_events_attempt_outcome"
    add_check_constraint :operations_durable_enqueue_events,
                         "sequence > 0",
                         name: "operations_durable_events_sequence"
    add_check_constraint :operations_durable_enqueue_events,
                         "generation > 0",
                         name: "operations_durable_events_generation"
    add_check_constraint :operations_durable_enqueue_events,
                         "event_type IN (#{quoted(EVENT_TYPES)})",
                         name: "operations_durable_events_type"
    add_check_constraint :operations_durable_enqueue_events,
                         "error_code IS NULL OR error_code ~ '^[a-z][a-z0-9_]*$'",
                         name: "operations_durable_events_error_code"
    add_check_constraint :operations_durable_enqueue_events,
                         "jsonb_typeof(metadata) = 'object' AND octet_length(metadata::text) <= 4096",
                         name: "operations_durable_events_metadata"
    add_check_constraint :operations_durable_enqueue_events,
                         "((event_type IN ('attempt_started', 'lease_renewed', 'attempt_succeeded', " \
                         "'attempt_skipped', 'attempt_failed', 'lease_expired') AND attempt_id IS NOT NULL) OR " \
                         "(event_type NOT IN ('attempt_started', 'lease_renewed', 'attempt_succeeded', " \
                         "'attempt_skipped', 'attempt_failed', 'lease_expired') AND attempt_id IS NULL))",
                         name: "operations_durable_events_attempt_shape"
    add_check_constraint :operations_durable_enqueue_events,
                         "((event_type IN ('enqueue_failed', 'attempt_failed', 'retry_scheduled', " \
                         "'dead_lettered', 'attempt_skipped') AND error_code IS NOT NULL) OR " \
                         "(event_type NOT IN ('enqueue_failed', 'attempt_failed', 'retry_scheduled', " \
                         "'dead_lettered', 'attempt_skipped') AND error_code IS NULL))",
                         name: "operations_durable_events_error_shape"
    add_check_constraint :operations_durable_enqueue_events,
                         "((event_type = 'retry_scheduled' AND available_at IS NOT NULL) OR " \
                         "(event_type <> 'retry_scheduled' AND available_at IS NULL))",
                         name: "operations_durable_events_available_shape"
    add_check_constraint :operations_durable_enqueue_events,
                         "((event_type = 'lease_renewed' AND lease_expires_at IS NOT NULL AND " \
                         "lease_expires_at > occurred_at) OR " \
                         "(event_type <> 'lease_renewed' AND lease_expires_at IS NULL))",
                         name: "operations_durable_events_lease_shape"
    add_check_constraint :operations_durable_enqueue_events,
                         "(event_type <> 'reopened' OR (" \
                         "metadata ? 'actor_id' AND metadata ? 'reason' AND " \
                         "COALESCE((metadata ->> 'actor_id') ~ '^[1-9][0-9]*$', FALSE) AND " \
                         "COALESCE(length(btrim(metadata ->> 'reason')) BETWEEN 1 AND 500, FALSE)))",
                         name: "operations_durable_events_reopened_shape"
    add_index :operations_durable_enqueue_events,
              :attempt_id,
              unique: true,
              where: "event_type = 'lease_expired'",
              name: "index_operations_durable_events_unique_lease_expired"

    create_insert_guards
    create_immutable_trigger(:operations_durable_enqueue_intents, "operations_durable_intents")
    create_immutable_trigger(:operations_durable_enqueue_attempts, "operations_durable_attempts")
    create_immutable_trigger(:operations_durable_enqueue_events, "operations_durable_events")
  end

  def down
    drop_immutable_trigger(:operations_durable_enqueue_events, "operations_durable_events")
    drop_immutable_trigger(:operations_durable_enqueue_attempts, "operations_durable_attempts")
    drop_immutable_trigger(:operations_durable_enqueue_intents, "operations_durable_intents")
    drop_insert_guards

    drop_table :operations_durable_enqueue_events
    drop_table :operations_durable_enqueue_attempts
    drop_table :operations_durable_enqueue_intents
  end

  private

  def quoted(values)
    values.map { |value| connection.quote(value) }.join(", ")
  end

  def create_immutable_trigger(table, prefix)
    execute <<~SQL
      CREATE FUNCTION #{prefix}_reject_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION '#{table} is append-only';
      END;
      $$;

      CREATE TRIGGER #{prefix}_immutable
      BEFORE UPDATE OR DELETE ON #{table}
      FOR EACH ROW
      EXECUTE FUNCTION #{prefix}_reject_change();
    SQL
  end

  def create_insert_guards
    execute <<~SQL
      CREATE FUNCTION operations_durable_attempts_validate_insert()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        current_generation integer;
        expected_attempt_number integer;
        previous_attempt_id bigint;
        previous_attempt_closed boolean;
      BEGIN
        SELECT generation
          INTO current_generation
          FROM operations_durable_enqueue_events
         WHERE intent_id = NEW.intent_id
         ORDER BY sequence DESC
         LIMIT 1;

        SELECT COALESCE(MAX(attempt_number), 0) + 1
          INTO expected_attempt_number
          FROM operations_durable_enqueue_attempts
         WHERE intent_id = NEW.intent_id;

        SELECT id
          INTO previous_attempt_id
          FROM operations_durable_enqueue_attempts
         WHERE intent_id = NEW.intent_id
         ORDER BY attempt_number DESC
         LIMIT 1;

        IF previous_attempt_id IS NOT NULL THEN
          SELECT EXISTS (
            SELECT 1
              FROM operations_durable_enqueue_events
             WHERE attempt_id = previous_attempt_id
               AND event_type IN (
                 'attempt_succeeded', 'attempt_skipped', 'attempt_failed', 'lease_expired'
               )
          ) INTO previous_attempt_closed;
          IF NOT previous_attempt_closed THEN
            RAISE EXCEPTION 'durable enqueue previous attempt is still active';
          END IF;
        END IF;

        IF current_generation IS NULL OR NEW.generation <> current_generation THEN
          RAISE EXCEPTION 'durable enqueue attempt generation is stale';
        END IF;
        IF NEW.attempt_number <> expected_attempt_number THEN
          RAISE EXCEPTION 'durable enqueue attempt number is not contiguous';
        END IF;
        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER operations_durable_attempts_validate
      BEFORE INSERT ON operations_durable_enqueue_attempts
      FOR EACH ROW
      EXECUTE FUNCTION operations_durable_attempts_validate_insert();

      CREATE FUNCTION operations_durable_events_validate_insert()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        previous_sequence integer;
        previous_generation integer;
        previous_event_type text;
        attempt_intent_id bigint;
        attempt_generation integer;
        attempt_lease_expires_at timestamp without time zone;
        effective_lease_expires_at timestamp without time zone;
        latest_attempt_id bigint;
      BEGIN
        SELECT sequence, generation, event_type
          INTO previous_sequence, previous_generation, previous_event_type
          FROM operations_durable_enqueue_events
         WHERE intent_id = NEW.intent_id
         ORDER BY sequence DESC
         LIMIT 1;

        IF previous_sequence IS NULL THEN
          IF NEW.sequence <> 1 OR NEW.generation <> 1 OR NEW.event_type <> 'recorded' THEN
            RAISE EXCEPTION 'durable enqueue ledger must begin with generation one recorded event';
          END IF;
        ELSE
          IF NEW.sequence <> previous_sequence + 1 THEN
            RAISE EXCEPTION 'durable enqueue event sequence is not contiguous';
          END IF;
          IF NEW.event_type = 'reopened' THEN
            IF previous_event_type <> 'dead_lettered' OR NEW.generation <> previous_generation + 1 THEN
              RAISE EXCEPTION 'durable enqueue generation cannot be reopened';
            END IF;
          ELSE
            IF previous_event_type IN (#{quoted(%w[attempt_succeeded attempt_skipped dead_lettered])}) THEN
              RAISE EXCEPTION 'durable enqueue terminal generation is closed';
            END IF;
            IF NEW.generation <> previous_generation THEN
              RAISE EXCEPTION 'durable enqueue event generation is stale';
            END IF;
          END IF;
        END IF;

        IF NEW.attempt_id IS NOT NULL THEN
          SELECT intent_id, generation, lease_expires_at
            INTO attempt_intent_id, attempt_generation, attempt_lease_expires_at
            FROM operations_durable_enqueue_attempts
           WHERE id = NEW.attempt_id;
          IF attempt_intent_id IS NULL OR
             attempt_intent_id <> NEW.intent_id OR
             attempt_generation <> NEW.generation THEN
            RAISE EXCEPTION 'durable enqueue event attempt is from another intent or generation';
          END IF;

          IF NEW.event_type = 'attempt_started' THEN
            IF EXISTS (
              SELECT 1
                FROM operations_durable_enqueue_events
               WHERE attempt_id = NEW.attempt_id
                 AND event_type IN (
                   'attempt_started', 'lease_renewed',
                   'attempt_succeeded', 'attempt_skipped', 'attempt_failed', 'lease_expired'
                 )
            ) THEN
              RAISE EXCEPTION 'durable enqueue attempt was already started';
            END IF;
          ELSIF NEW.event_type = 'lease_renewed' THEN
            IF NOT EXISTS (
              SELECT 1
                FROM operations_durable_enqueue_events
               WHERE attempt_id = NEW.attempt_id
                 AND event_type = 'attempt_started'
                 AND sequence < NEW.sequence
            ) OR EXISTS (
              SELECT 1
                 FROM operations_durable_enqueue_events
                WHERE attempt_id = NEW.attempt_id
                  AND event_type IN (
                    'attempt_succeeded', 'attempt_skipped', 'attempt_failed', 'lease_expired'
                  )
            ) THEN
              RAISE EXCEPTION 'durable enqueue lease cannot be renewed';
            END IF;
          ELSIF NEW.event_type = 'lease_expired' THEN
            SELECT id
              INTO latest_attempt_id
              FROM operations_durable_enqueue_attempts
             WHERE intent_id = NEW.intent_id
               AND generation = NEW.generation
             ORDER BY attempt_number DESC
             LIMIT 1;
            SELECT GREATEST(
                     attempt_lease_expires_at,
                     COALESCE(MAX(lease_expires_at), attempt_lease_expires_at)
                   )
              INTO effective_lease_expires_at
              FROM operations_durable_enqueue_events
             WHERE attempt_id = NEW.attempt_id
               AND event_type = 'lease_renewed'
               AND sequence < NEW.sequence;
            IF NEW.attempt_id <> latest_attempt_id OR NOT EXISTS (
              SELECT 1
                FROM operations_durable_enqueue_events
               WHERE attempt_id = NEW.attempt_id
                 AND event_type = 'attempt_started'
                 AND sequence < NEW.sequence
            ) OR EXISTS (
              SELECT 1
                FROM operations_durable_enqueue_events
               WHERE attempt_id = NEW.attempt_id
                 AND event_type IN (
                   'attempt_succeeded', 'attempt_skipped', 'attempt_failed', 'lease_expired'
                 )
            ) OR NEW.occurred_at < effective_lease_expires_at THEN
              RAISE EXCEPTION 'durable enqueue lease expiry is invalid, premature, or duplicated';
            END IF;
          ELSIF NEW.event_type IN ('attempt_succeeded', 'attempt_skipped', 'attempt_failed') THEN
            IF NOT EXISTS (
              SELECT 1
                FROM operations_durable_enqueue_events
               WHERE attempt_id = NEW.attempt_id
                 AND event_type = 'attempt_started'
                 AND sequence < NEW.sequence
            ) OR EXISTS (
              SELECT 1
                 FROM operations_durable_enqueue_events
                WHERE attempt_id = NEW.attempt_id
                  AND event_type IN (
                    'attempt_succeeded', 'attempt_skipped', 'attempt_failed', 'lease_expired'
                  )
            ) THEN
              RAISE EXCEPTION 'durable enqueue attempt outcome is invalid or duplicated';
            END IF;
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER operations_durable_events_validate
      BEFORE INSERT ON operations_durable_enqueue_events
      FOR EACH ROW
      EXECUTE FUNCTION operations_durable_events_validate_insert();
    SQL
  end

  def drop_insert_guards
    execute "DROP TRIGGER IF EXISTS operations_durable_events_validate ON operations_durable_enqueue_events"
    execute "DROP FUNCTION IF EXISTS operations_durable_events_validate_insert()"
    execute "DROP TRIGGER IF EXISTS operations_durable_attempts_validate ON operations_durable_enqueue_attempts"
    execute "DROP FUNCTION IF EXISTS operations_durable_attempts_validate_insert()"
  end

  def drop_immutable_trigger(table, prefix)
    execute "DROP TRIGGER IF EXISTS #{prefix}_immutable ON #{table}"
    execute "DROP FUNCTION IF EXISTS #{prefix}_reject_change()"
  end
end
