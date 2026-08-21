# frozen_string_literal: true

class EnforceAuthorizationMutationBarrier < ActiveRecord::Migration[8.1]
  LOCK_KEY = 0x4D43_5745_4249_4447
  LOCK_TIMEOUT = "5s"

  TRIGGERS = {
    users: %w[
      identity_auth_users_lock_delete
      identity_auth_users_lock_update
      identity_auth_users_bump_update
    ],
    user_roles: %w[
      identity_auth_user_roles_lock
      identity_auth_user_roles_bump_insert
      identity_auth_user_roles_bump_update
      identity_auth_user_roles_bump_delete
    ],
    role_permissions: %w[
      identity_auth_role_permissions_lock
      identity_auth_role_permissions_bump_insert
      identity_auth_role_permissions_bump_update
      identity_auth_role_permissions_bump_delete
    ],
    community_group_memberships: %w[
      identity_auth_group_memberships_lock
      identity_auth_group_memberships_bump_insert
      identity_auth_group_memberships_bump_update
      identity_auth_group_memberships_bump_delete
    ],
    community_user_groups: %w[
      identity_auth_group_permissions_lock_update
      identity_auth_group_permissions_bump_update
    ]
  }.freeze

  REMOVED_TRIGGER_NAMES = {
    users: %w[identity_auth_users_lock_insert_delete],
    community_user_groups: %w[identity_auth_group_permissions_lock_insert_delete]
  }.freeze

  FUNCTIONS = %w[
    identity_auth_bump_group_permissions
    identity_auth_bump_group_memberships
    identity_auth_bump_role_permissions
    identity_auth_bump_user_roles
    identity_auth_bump_user_access
    identity_auth_acquire_exclusive_lock
  ].freeze

  def up
    execute "SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'"
    acquire_barrier!
    barrier_already_installed = authorization_trigger_installed?
    drop_triggers
    create_functions
    create_triggers
    bump_existing_permission_epochs! unless barrier_already_installed
  end

  def down
    execute "SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'"
    acquire_barrier!
    drop_triggers
    FUNCTIONS.each { |function| execute "DROP FUNCTION IF EXISTS #{function}()" }
  end

  private

  def acquire_barrier!
    execute "SELECT pg_advisory_xact_lock(#{LOCK_KEY}::bigint)"
  end

  def authorization_trigger_installed?
    connection.select_value(<<~SQL.squish) == true
      SELECT EXISTS (
        SELECT 1
          FROM pg_trigger
         WHERE tgname = 'identity_auth_user_roles_lock'
           AND tgrelid = 'user_roles'::regclass
           AND tgisinternal = FALSE
      )
    SQL
  end

  def bump_existing_permission_epochs!
    execute <<~SQL.squish
      UPDATE users
         SET permission_version = permission_version + 1,
             updated_at = CURRENT_TIMESTAMP
    SQL
  end

  def create_functions
    execute <<~SQL
      CREATE OR REPLACE FUNCTION identity_auth_acquire_exclusive_lock()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $function$
      BEGIN
        PERFORM pg_advisory_xact_lock(#{LOCK_KEY}::bigint);
        RETURN NULL;
      END;
      $function$;

      CREATE OR REPLACE FUNCTION identity_auth_bump_user_access()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $function$
      BEGIN
        IF OLD.status IS DISTINCT FROM NEW.status
            OR OLD.account_type IS DISTINCT FROM NEW.account_type THEN
          NEW.permission_version := OLD.permission_version + 1;
          NEW.updated_at := CURRENT_TIMESTAMP;
        END IF;
        RETURN NEW;
      END;
      $function$;

      CREATE OR REPLACE FUNCTION identity_auth_bump_user_roles()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $function$
      BEGIN
        IF TG_OP = 'INSERT' THEN
          UPDATE users AS affected
             SET permission_version = affected.permission_version + 1,
                 updated_at = CURRENT_TIMESTAMP
           WHERE affected.id IN (SELECT DISTINCT user_id FROM new_rows);
        ELSIF TG_OP = 'UPDATE' THEN
          WITH changed_rows AS (
            SELECT old_rows.user_id AS old_user_id,
                   new_rows.user_id AS new_user_id
              FROM old_rows
              INNER JOIN new_rows ON new_rows.id = old_rows.id
             WHERE old_rows.user_id IS DISTINCT FROM new_rows.user_id
                OR old_rows.role_id IS DISTINCT FROM new_rows.role_id
          ), affected_users AS (
            SELECT old_user_id AS user_id FROM changed_rows
            UNION
            SELECT new_user_id AS user_id FROM changed_rows
          )
          UPDATE users AS affected
             SET permission_version = affected.permission_version + 1,
                 updated_at = CURRENT_TIMESTAMP
           WHERE affected.id IN (SELECT user_id FROM affected_users);
        ELSE
          UPDATE users AS affected
             SET permission_version = affected.permission_version + 1,
                 updated_at = CURRENT_TIMESTAMP
           WHERE affected.id IN (SELECT DISTINCT user_id FROM old_rows);
        END IF;
        RETURN NULL;
      END;
      $function$;

      CREATE OR REPLACE FUNCTION identity_auth_bump_role_permissions()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $function$
      BEGIN
        IF TG_OP = 'INSERT' THEN
          UPDATE users AS affected
             SET permission_version = affected.permission_version + 1,
                 updated_at = CURRENT_TIMESTAMP
           WHERE EXISTS (
             SELECT 1
               FROM user_roles
              WHERE user_roles.user_id = affected.id
                AND user_roles.role_id IN (SELECT DISTINCT role_id FROM new_rows)
           );
        ELSIF TG_OP = 'UPDATE' THEN
          WITH changed_rows AS (
            SELECT old_rows.role_id AS old_role_id,
                   new_rows.role_id AS new_role_id
              FROM old_rows
              INNER JOIN new_rows ON new_rows.id = old_rows.id
             WHERE old_rows.role_id IS DISTINCT FROM new_rows.role_id
                OR old_rows.permission_id IS DISTINCT FROM new_rows.permission_id
          ), affected_roles AS (
            SELECT old_role_id AS role_id FROM changed_rows
            UNION
            SELECT new_role_id AS role_id FROM changed_rows
          )
          UPDATE users AS affected
             SET permission_version = affected.permission_version + 1,
                 updated_at = CURRENT_TIMESTAMP
           WHERE EXISTS (
             SELECT 1
               FROM user_roles
              WHERE user_roles.user_id = affected.id
                AND user_roles.role_id IN (SELECT role_id FROM affected_roles)
           );
        ELSE
          UPDATE users AS affected
             SET permission_version = affected.permission_version + 1,
                 updated_at = CURRENT_TIMESTAMP
           WHERE EXISTS (
             SELECT 1
               FROM user_roles
              WHERE user_roles.user_id = affected.id
                AND user_roles.role_id IN (SELECT DISTINCT role_id FROM old_rows)
           );
        END IF;
        RETURN NULL;
      END;
      $function$;

      CREATE OR REPLACE FUNCTION identity_auth_bump_group_memberships()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $function$
      BEGIN
        IF TG_OP = 'INSERT' THEN
          UPDATE users AS affected
             SET permission_version = affected.permission_version + 1,
                 updated_at = CURRENT_TIMESTAMP
           WHERE affected.id IN (SELECT DISTINCT user_id FROM new_rows);
        ELSIF TG_OP = 'UPDATE' THEN
          WITH changed_rows AS (
            SELECT old_rows.user_id AS old_user_id,
                   new_rows.user_id AS new_user_id
              FROM old_rows
              INNER JOIN new_rows ON new_rows.id = old_rows.id
             WHERE old_rows.user_id IS DISTINCT FROM new_rows.user_id
                OR old_rows.community_user_group_id IS DISTINCT FROM new_rows.community_user_group_id
          ), affected_users AS (
            SELECT old_user_id AS user_id FROM changed_rows
            UNION
            SELECT new_user_id AS user_id FROM changed_rows
          )
          UPDATE users AS affected
             SET permission_version = affected.permission_version + 1,
                 updated_at = CURRENT_TIMESTAMP
           WHERE affected.id IN (SELECT user_id FROM affected_users);
        ELSE
          UPDATE users AS affected
             SET permission_version = affected.permission_version + 1,
                 updated_at = CURRENT_TIMESTAMP
           WHERE affected.id IN (SELECT DISTINCT user_id FROM old_rows);
        END IF;
        RETURN NULL;
      END;
      $function$;

      CREATE OR REPLACE FUNCTION identity_auth_bump_group_permissions()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $function$
      BEGIN
        WITH changed_groups AS (
          SELECT old_rows.id
            FROM old_rows
            INNER JOIN new_rows ON new_rows.id = old_rows.id
           WHERE old_rows.permissions IS DISTINCT FROM new_rows.permissions
        )
        UPDATE users AS affected
           SET permission_version = affected.permission_version + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE EXISTS (
           SELECT 1
             FROM community_group_memberships
             INNER JOIN changed_groups
               ON changed_groups.id = community_group_memberships.community_user_group_id
            WHERE community_group_memberships.user_id = affected.id
         );
        RETURN NULL;
      END;
      $function$;
    SQL
  end

  def create_triggers
    execute <<~SQL
      CREATE TRIGGER identity_auth_users_lock_delete
      BEFORE DELETE ON users
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_acquire_exclusive_lock();

      CREATE TRIGGER identity_auth_users_lock_update
      BEFORE UPDATE OF status, account_type ON users
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_acquire_exclusive_lock();

      CREATE TRIGGER identity_auth_users_bump_update
      BEFORE UPDATE OF status, account_type ON users
      FOR EACH ROW
      EXECUTE FUNCTION identity_auth_bump_user_access();

      CREATE TRIGGER identity_auth_user_roles_lock
      BEFORE INSERT OR DELETE OR UPDATE OF user_id, role_id ON user_roles
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_acquire_exclusive_lock();

      CREATE TRIGGER identity_auth_user_roles_bump_insert
      AFTER INSERT ON user_roles
      REFERENCING NEW TABLE AS new_rows
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_bump_user_roles();

      CREATE TRIGGER identity_auth_user_roles_bump_update
      AFTER UPDATE ON user_roles
      REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_bump_user_roles();

      CREATE TRIGGER identity_auth_user_roles_bump_delete
      AFTER DELETE ON user_roles
      REFERENCING OLD TABLE AS old_rows
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_bump_user_roles();

      CREATE TRIGGER identity_auth_role_permissions_lock
      BEFORE INSERT OR DELETE OR UPDATE OF role_id, permission_id ON role_permissions
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_acquire_exclusive_lock();

      CREATE TRIGGER identity_auth_role_permissions_bump_insert
      AFTER INSERT ON role_permissions
      REFERENCING NEW TABLE AS new_rows
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_bump_role_permissions();

      CREATE TRIGGER identity_auth_role_permissions_bump_update
      AFTER UPDATE ON role_permissions
      REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_bump_role_permissions();

      CREATE TRIGGER identity_auth_role_permissions_bump_delete
      AFTER DELETE ON role_permissions
      REFERENCING OLD TABLE AS old_rows
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_bump_role_permissions();

      CREATE TRIGGER identity_auth_group_memberships_lock
      BEFORE INSERT OR DELETE OR UPDATE OF user_id, community_user_group_id
      ON community_group_memberships
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_acquire_exclusive_lock();

      CREATE TRIGGER identity_auth_group_memberships_bump_insert
      AFTER INSERT ON community_group_memberships
      REFERENCING NEW TABLE AS new_rows
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_bump_group_memberships();

      CREATE TRIGGER identity_auth_group_memberships_bump_update
      AFTER UPDATE ON community_group_memberships
      REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_bump_group_memberships();

      CREATE TRIGGER identity_auth_group_memberships_bump_delete
      AFTER DELETE ON community_group_memberships
      REFERENCING OLD TABLE AS old_rows
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_bump_group_memberships();

      CREATE TRIGGER identity_auth_group_permissions_lock_update
      BEFORE UPDATE OF permissions ON community_user_groups
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_acquire_exclusive_lock();

      CREATE TRIGGER identity_auth_group_permissions_bump_update
      AFTER UPDATE ON community_user_groups
      REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
      FOR EACH STATEMENT
      EXECUTE FUNCTION identity_auth_bump_group_permissions();
    SQL
  end

  def drop_triggers
    all_triggers = TRIGGERS.merge(REMOVED_TRIGGER_NAMES) do |_table, current, removed|
      current + removed
    end
    all_triggers.each do |table, triggers|
      next unless table_exists?(table)

      triggers.each do |trigger|
        execute "DROP TRIGGER IF EXISTS #{trigger} ON #{table}"
      end
    end
  end
end
