# frozen_string_literal: true

class NormalizeLegacyUserLocales < ActiveRecord::Migration[8.1]
  DEFAULT_LOCALE = "zh-CN"
  SUPPORTED_LOCALES = %w[en zh-CN].freeze
  ENGLISH_ALIASES = %w[en en-us en-gb].freeze
  CHINESE_ALIASES = %w[zh zh-cn zh-hans].freeze

  MigrationUser = Class.new(ActiveRecord::Base) do
    self.table_name = "users"
  end

  def up
    return unless table_exists?(:users) && column_exists?(:users, :locale)

    say_with_time "normalizing legacy user locales" do
      normalize_aliases(ENGLISH_ALIASES, "en")
      normalize_aliases(CHINESE_ALIASES, "zh-CN")

      unsupported = MigrationUser.where.not(locale: SUPPORTED_LOCALES)
        .or(MigrationUser.where(locale: nil))
      unsupported.update_all(locale: DEFAULT_LOCALE)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "original unsupported user locale values cannot be reconstructed"
  end

  private

  def normalize_aliases(aliases, canonical)
    MigrationUser
      .where("LOWER(REPLACE(TRIM(locale), '_', '-')) IN (?)", aliases)
      .update_all(locale: canonical)
  end
end
