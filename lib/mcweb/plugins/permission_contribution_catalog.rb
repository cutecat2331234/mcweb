# frozen_string_literal: true

module Mcweb
  module Plugins
    class PermissionContributionCatalog
      Conflict = Data.define(:type, :value, :existing_plugin_id, :plugin_id)
      EMPTY = [].freeze

      def initialize
        @entries = {}
        @group_owners = {}
        @mutex = Mutex.new
      end

      def activate(contributions)
        return EMPTY if contributions.empty?

        plugin_ids = contributions.map(&:plugin_id).uniq
        unless plugin_ids.one?
          raise ArgumentError, "permission contributions must belong to one plugin"
        end

        @mutex.synchronize do
          conflicts = conflicts_for(contributions)
          return conflicts.freeze if conflicts.any?

          contributions.each do |contribution|
            @entries[contribution.id] = contribution
            @group_owners[contribution.group] = contribution.plugin_id
          end
          EMPTY
        end
      end

      def deactivate(plugin_id)
        plugin_id = plugin_id.to_s
        @mutex.synchronize do
          @entries.delete_if { |_id, contribution| contribution.plugin_id == plugin_id }
          rebuild_group_owners!
        end
        true
      end

      def all
        @mutex.synchronize { @entries.values.sort_by(&:id).freeze }
      end

      def find(id)
        @mutex.synchronize { @entries[id.to_s] }
      end

      def clear
        @mutex.synchronize do
          @entries.clear
          @group_owners.clear
        end
        true
      end

      private

      def conflicts_for(contributions)
        contributions.flat_map do |contribution|
          conflicts = []
          entry_owner = @entries[contribution.id]&.plugin_id
          if entry_owner && entry_owner != contribution.plugin_id
            conflicts << Conflict.new(
              type: "permission",
              value: contribution.id,
              existing_plugin_id: entry_owner,
              plugin_id: contribution.plugin_id
            )
          end

          group_owner = @group_owners[contribution.group]
          if group_owner && group_owner != contribution.plugin_id
            conflicts << Conflict.new(
              type: "permission_group",
              value: contribution.group,
              existing_plugin_id: group_owner,
              plugin_id: contribution.plugin_id
            )
          end
          conflicts
        end.uniq.sort_by { |conflict| [ conflict.type, conflict.value ] }
      end

      def rebuild_group_owners!
        @group_owners = @entries.values.to_h do |contribution|
          [ contribution.group, contribution.plugin_id ]
        end
      end
    end
  end
end
