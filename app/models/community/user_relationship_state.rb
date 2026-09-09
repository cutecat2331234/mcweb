# frozen_string_literal: true

module Community
  class UserRelationshipState < ApplicationRecord
    # Relationship rows remain the source of truth. This ledger only remembers
    # write ordering, including removals, for optimistic concurrency control.
    RELATIONSHIPS = {
      "block" => { model_name: "Community::UserBlock", actor_column: :blocker_id, target_column: :blocked_id },
      "ignore" => { model_name: "Community::UserIgnore", actor_column: :ignorer_id, target_column: :ignored_id },
      "follow" => { model_name: "Community::UserFollow", actor_column: :follower_id, target_column: :followed_id }
    }.freeze
    RELATIONSHIPS_BY_MODEL = RELATIONSHIPS.index_by { |_kind, definition| definition.fetch(:model_name) }.freeze

    SNAPSHOTS_SQL = <<~SQL.squish.freeze
      WITH requested_targets(target_id) AS (
        SELECT requested_target.value::bigint
        FROM jsonb_array_elements_text($2::jsonb) AS requested_target(value)
      ),
      requested_kinds(kind) AS (
        SELECT requested_kind.value
        FROM jsonb_array_elements_text($3::jsonb) AS requested_kind(value)
      )
      SELECT requested_kinds.kind,
             requested_targets.target_id,
             CASE requested_kinds.kind
               WHEN 'block' THEN user_block.id IS NOT NULL
               WHEN 'ignore' THEN user_ignore.id IS NOT NULL
               WHEN 'follow' THEN user_follow.id IS NOT NULL
             END AS active,
             COALESCE(relationship_state.revision, 0) AS revision
      FROM requested_targets
      CROSS JOIN requested_kinds
      LEFT JOIN forum_user_blocks user_block
        ON requested_kinds.kind = 'block'
       AND user_block.blocker_id = $1
       AND user_block.blocked_id = requested_targets.target_id
      LEFT JOIN forum_user_ignores user_ignore
        ON requested_kinds.kind = 'ignore'
       AND user_ignore.ignorer_id = $1
       AND user_ignore.ignored_id = requested_targets.target_id
      LEFT JOIN forum_user_follows user_follow
        ON requested_kinds.kind = 'follow'
       AND user_follow.follower_id = $1
       AND user_follow.followed_id = requested_targets.target_id
      LEFT JOIN forum_user_relationship_states relationship_state
        ON relationship_state.actor_id = $1
       AND relationship_state.target_id = requested_targets.target_id
       AND relationship_state.kind = requested_kinds.kind
    SQL
    private_constant :SNAPSHOTS_SQL

    belongs_to :actor, class_name: "User"
    belongs_to :target, class_name: "User"

    def self.key_for(relation)
      kind, definition = RELATIONSHIPS_BY_MODEL.fetch(relation.klass.name)
      scoped_record = relation.new
      {
        kind: kind,
        actor_id: scoped_record.public_send(definition.fetch(:actor_column)),
        target_id: scoped_record.public_send(definition.fetch(:target_column))
      }
    end

    def self.snapshot(relation:)
      key = key_for(relation)
      snapshots(
        actor: key.fetch(:actor_id),
        targets: [ key.fetch(:target_id) ],
        kinds: [ key.fetch(:kind) ]
      ).fetch(key.fetch(:target_id)).fetch(key.fetch(:kind).to_sym)
    end

    # Read the relationship row and its revision ledger in one database
    # statement. PostgreSQL therefore returns both values from the same MVCC
    # snapshot without making GET requests contend on the writer's user locks.
    # Multiple targets and relationship kinds are folded into that same query.
    def self.snapshots(actor:, targets:, kinds: RELATIONSHIPS.keys)
      actor_id = normalize_user_id(actor)
      target_ids = Array(targets).filter_map { |target| normalize_user_id(target) }.uniq
      requested_kinds = Array(kinds).map(&:to_s).uniq
      requested_kinds.each { |kind| RELATIONSHIPS.fetch(kind) }
      result = target_ids.index_with do
        requested_kinds.index_with { { active: false, revision: "0" } }.transform_keys(&:to_sym)
      end
      return result if target_ids.empty? || requested_kinds.empty?

      connection = self.connection
      binds = [
        ActiveRecord::Relation::QueryAttribute.new(
          "relationship_actor_id",
          actor_id,
          ActiveRecord::Type::Integer.new(limit: 8)
        ),
        ActiveRecord::Relation::QueryAttribute.new(
          "relationship_target_ids",
          target_ids.to_json,
          ActiveRecord::Type::String.new
        ),
        ActiveRecord::Relation::QueryAttribute.new(
          "relationship_kinds",
          requested_kinds.to_json,
          ActiveRecord::Type::String.new
        )
      ]

      uncached do
        connection.exec_query(SNAPSHOTS_SQL, "Community relationship snapshots", binds).each do |row|
          target_id = row.fetch("target_id").to_i
          kind = row.fetch("kind").to_sym
          result.fetch(target_id).fetch(kind).merge!(
            active: ActiveModel::Type::Boolean.new.cast(row.fetch("active")),
            revision: row.fetch("revision").to_s
          )
        end
      end

      result
    end

    def self.normalize_user_id(user)
      raw_id = user.respond_to?(:id) ? user.id : user
      user_id = Integer(raw_id, exception: false)
      raise ArgumentError, "community_user_relationship_participant_invalid" unless user_id&.positive?

      user_id
    end
    private_class_method :normalize_user_id
  end
end
