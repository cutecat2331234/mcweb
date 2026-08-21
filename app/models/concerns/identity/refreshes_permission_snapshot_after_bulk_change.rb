# frozen_string_literal: true

module Identity
  # PostgreSQL owns persistent permission-version invalidation. Association
  # bulk APIs still need to refresh their already-loaded User owner so callers
  # do not keep using the old in-memory authorization snapshot after clear or
  # delete_all returns.
  module RefreshesPermissionSnapshotAfterBulkChange
    def clear
      super.tap { refresh_owner_permission_snapshot! }
    end

    def delete_all(...)
      super.tap { refresh_owner_permission_snapshot! }
    end

    def destroy_all
      super.tap { refresh_owner_permission_snapshot! }
    end

    private

    def refresh_owner_permission_snapshot!
      proxy_association.owner.send(:refresh_permission_snapshot_from_database!)
    end
  end
end
