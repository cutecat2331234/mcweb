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
      definitions = requested_kinds.to_h { |kind| [ kind, RELATIONSHIPS.fetch(kind) ] }
      result = target_ids.index_with do
        requested_kinds.index_with { { active: false, revision: "0" } }.transform_keys(&:to_sym)
      end
      return result if target_ids.empty? || requested_kinds.empty?

      connection = self.connection
      target_values = target_ids.map { |target_id| "(#{connection.quote(target_id)})" }.join(", ")
      state_table = connection.quote_table_name(table_name)
      statements = definitions.map do |kind, definition|
        relationship_model = definition.fetch(:model_name).constantize
        relationship_table = connection.quote_table_name(relationship_model.table_name)
        relationship_key = connection.quote_column_name(relationship_model.primary_key)
        actor_column = connection.quote_column_name(definition.fetch(:actor_column))
        target_column = connection.quote_column_name(definition.fetch(:target_column))

        <<~SQL.squish
          SELECT #{connection.quote(kind)} AS kind,
                 requested_targets.target_id,
                 (relationship.#{relationship_key} IS NOT NULL) AS active,
                 COALESCE(relationship_state.revision, 0) AS revision
          FROM requested_targets
          LEFT JOIN #{relationship_table} relationship
            ON relationship.#{actor_column} = #{connection.quote(actor_id)}
           AND relationship.#{target_column} = requested_targets.target_id
          LEFT JOIN #{state_table} relationship_state
            ON relationship_state.actor_id = #{connection.quote(actor_id)}
           AND relationship_state.target_id = requested_targets.target_id
           AND relationship_state.kind = #{connection.quote(kind)}
        SQL
      end

      sql = "WITH requested_targets(target_id) AS (VALUES #{target_values}) #{statements.join(' UNION ALL ')}"
      uncached do
        connection.select_all(sql, "Community relationship snapshots").each do |row|
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
