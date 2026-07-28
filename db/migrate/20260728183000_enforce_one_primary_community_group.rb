# frozen_string_literal: true

class EnforceOnePrimaryCommunityGroup < ActiveRecord::Migration[8.1]
  # PostgreSQL can enforce at most one primary row. Canonical writes through
  # Identity::ApplyGroupMutation also maintain at least one primary whenever
  # the user still has memberships.
  INDEX_NAME = "idx_community_group_memberships_one_primary"

  def up
    execute <<~SQL.squish
      WITH ranked_primaries AS (
        SELECT
          memberships.id,
          ROW_NUMBER() OVER (
            PARTITION BY memberships.user_id
            ORDER BY
              groups.priority DESC,
              groups.name ASC,
              groups.id ASC,
              memberships.id ASC
          ) AS primary_rank
        FROM community_group_memberships AS memberships
        INNER JOIN community_user_groups AS groups
          ON groups.id = memberships.community_user_group_id
        WHERE memberships.is_primary = TRUE
      )
      UPDATE community_group_memberships AS memberships
      SET is_primary = FALSE, updated_at = CURRENT_TIMESTAMP
      FROM ranked_primaries
      WHERE memberships.id = ranked_primaries.id
        AND ranked_primaries.primary_rank > 1
    SQL

    execute <<~SQL.squish
      WITH ranked_memberships AS (
        SELECT
          memberships.id,
          memberships.user_id,
          ROW_NUMBER() OVER (
            PARTITION BY memberships.user_id
            ORDER BY
              groups.priority DESC,
              groups.name ASC,
              groups.id ASC,
              memberships.id ASC
          ) AS membership_rank
        FROM community_group_memberships AS memberships
        INNER JOIN community_user_groups AS groups
          ON groups.id = memberships.community_user_group_id
      )
      UPDATE community_group_memberships AS memberships
      SET is_primary = TRUE, updated_at = CURRENT_TIMESTAMP
      FROM ranked_memberships
      WHERE memberships.id = ranked_memberships.id
        AND ranked_memberships.membership_rank = 1
        AND NOT EXISTS (
          SELECT 1
          FROM community_group_memberships AS existing_primary
          WHERE existing_primary.user_id = ranked_memberships.user_id
            AND existing_primary.is_primary = TRUE
        )
    SQL

    add_index(
      :community_group_memberships,
      :user_id,
      unique: true,
      where: "is_primary = TRUE",
      name: INDEX_NAME
    )
  end

  def down
    remove_index :community_group_memberships, name: INDEX_NAME
  end
end
