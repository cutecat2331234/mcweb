# frozen_string_literal: true

require "test_helper"
require Rails.root.join(
  "db/migrate/20260802110000_normalize_legacy_user_locales"
)

class NormalizeLegacyUserLocalesMigrationTest < ActiveSupport::TestCase
  test "upgrade canonicalizes aliases and safely falls back unsupported legacy values" do
    english_alias = create_user(locale: "en")
    chinese_alias = create_user(locale: "zh-CN")
    unsupported = create_user(locale: "en")
    english_alias.update_column(:locale, " EN_us ")
    chinese_alias.update_column(:locale, "ZH_hans")
    unsupported.update_column(:locale, "fr")

    migration = NormalizeLegacyUserLocales.new
    migration.up
    migration.up

    assert_equal "en", english_alias.reload.locale
    assert_equal "zh-CN", chinese_alias.reload.locale
    assert_equal NormalizeLegacyUserLocales::DEFAULT_LOCALE, unsupported.reload.locale

    assert unsupported.update!(display_name: "Legacy locale repaired")
  end

  test "rollback is explicit because discarded locale values are unrecoverable" do
    assert_raises(ActiveRecord::IrreversibleMigration) do
      NormalizeLegacyUserLocales.new.down
    end
  end
end
