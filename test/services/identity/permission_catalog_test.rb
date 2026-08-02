# frozen_string_literal: true

require "test_helper"

class Identity::PermissionCatalogTest < ActiveSupport::TestCase
  NEW_SHARED_KEYS = %w[
    store.products.read
    forum.conversations.create
    forum.sections.lifecycle
    forum.sections.delete
    identity.groups.read
    identity.groups.manage
    identity.groups.members.assign
    identity.groups.permissions.manage
    identity.roles.read
    identity.roles.manage
    system.bans.manage
    forum.users.trust.manage
    store.credit.read
    store.credit.adjust
    store.entitlements.read
    store.entitlements.grant
    store.entitlements.revoke
    store.orders.mark_paid
    store.orders.mark_fulfilled
    store.orders.cancel
    system.plugins.view
    system.plugins.install
    system.plugins.enable
    system.plugins.disable
    system.plugins.diagnostics
    system.plugins.recover
    system.plugins.rollback
    system.plugins.uninstall_preserve
    system.plugins.uninstall_purge
  ].freeze

  test "catalog entries are unique and expose their complete contract" do
    entries = Identity::PermissionCatalog.entries

    assert_equal entries.size, entries.map(&:key).uniq.size
    entries.each do |entry|
      assert_match(/\A[a-z][a-z0-9_.]*\z/, entry.key)
      assert_equal entry.key.split(".", 2).first, entry.category
      assert_equal(
        "mcweb.permissions.#{entry.key.tr('.', '_')}",
        entry.i18n_key
      )
      assert_includes Identity::PermissionCatalog::STATUSES, entry.status
      assert_kind_of Array, entry.execution_points
    end
  end

  test "every active permission points to an existing runtime source file" do
    Identity::PermissionCatalog.active_entries.each do |entry|
      assert_predicate entry.execution_points, :any?,
        "#{entry.key} must declare at least one execution point"

      entry.execution_points.each do |execution_point|
        relative_path = execution_point.split("#", 2).first
        assert Rails.root.join(relative_path).file?,
          "#{entry.key} points to missing runtime source #{relative_path}"
      end

      literal_sources = entry.execution_points.filter_map do |execution_point|
        relative_path = execution_point.split("#", 2).first
        path = Rails.root.join(relative_path)
        relative_path if path.file? && path.read.include?(entry.key)
      end
      assert_predicate literal_sources, :any?,
        "#{entry.key} must have a registered runtime source containing its literal key"
    end
  end

  test "every active permission and domain has complete English and Chinese translations" do
    locales = [ :en, :"zh-CN" ]

    locales.each do |locale|
      Identity::PermissionCatalog.active_entries.each do |entry|
        %w[name description].each do |attribute|
          key = "#{entry.i18n_key}.#{attribute}"
          assert I18n.exists?(key, locale), "#{key} is missing for #{locale}"
          assert_predicate I18n.t(key, locale:), :present?
        end
      end

      Identity::PermissionCatalog.active_entries.map(&:category).uniq.each do |domain|
        key = "mcweb.permission_domains.#{domain}"
        assert I18n.exists?(key, locale), "#{key} is missing for #{locale}"
        assert_predicate I18n.t(key, locale:), :present?
      end
    end
  end

  test "shared runtime and global identity group keys are active" do
    NEW_SHARED_KEYS.each do |key|
      assert Identity::PermissionCatalog.active_key?(key), "#{key} should be active"
      assert Identity::PermissionCatalog.fetch(key).execution_points.any?,
        "#{key} should identify at least one execution point"
    end
  end

  test "reserved permissions are not assignable, seeded, or serialized" do
    reserved = Identity::PermissionCatalog.fetch("system.jobs.retry")

    assert_predicate reserved, :reserved?
    assert_not Identity::PermissionCatalog.active_key?(reserved.key)
    assert_not_includes Identity::PermissionCatalog.assignable_keys, reserved.key
    assert_not_includes(
      Identity::PermissionCatalog.seed_attributes.pluck(:key),
      reserved.key
    )
    assert_not_includes(
      Identity::PermissionCatalog.grouped_json.flat_map { |group| group[:permissions].pluck(:key) },
      reserved.key
    )
  end

  test "grouped serialization exposes localized presentation fields for active permissions" do
    Mcweb::Plugins.stub(:permission_contributions, []) do
      groups = Identity::PermissionCatalog.grouped_json(locale: :en)
      serialized = groups.flat_map { |group| group.fetch(:permissions) }

      assert groups.all? { |group| group[:key].present? && group[:name].present? }
      assert_equal Identity::PermissionCatalog.active_keys.sort, serialized.pluck(:key).sort
      serialized.each do |permission|
        assert_equal %i[key name description], permission.keys
        assert_predicate permission[:name], :present?
        assert_predicate permission[:description], :present?
      end
    end
  end

  test "assignable serialization composes active plugin permission contributions" do
    contribution = {
      plugin_id: "acme/demo",
      id: "acme.demo.orders.view",
      group: "acme.demo.orders",
      title_phrase: "plugin.permissions.orders_view.title",
      description_phrase: "plugin.permissions.orders_view.description",
      scope: "global",
      default: "none"
    }

    Mcweb::Plugins.stub(:permission_contributions, [ contribution ]) do
      assert_includes Identity::PermissionCatalog.assignable_keys, contribution[:id]
      plugin_group = Identity::PermissionCatalog
        .grouped_json(locale: :en)
        .find { |group| group[:key] == "plugin:#{contribution[:group]}" }

      assert plugin_group
      assert_equal contribution[:title_phrase], plugin_group.dig(:permissions, 0, :name)
      assert_equal contribution[:description_phrase], plugin_group.dig(:permissions, 0, :description)
    end
  end

  test "plugin contributions cannot reactivate a reserved core permission" do
    contribution = {
      plugin_id: "system/jobs",
      id: "system.jobs.retry",
      group: "system.jobs",
      title_phrase: "plugin.permissions.jobs_retry.title",
      description_phrase: "plugin.permissions.jobs_retry.description",
      scope: "global",
      default: "none"
    }

    Mcweb::Plugins.stub(:permission_contributions, [ contribution ]) do
      assert_not_includes Identity::PermissionCatalog.assignable_keys, contribution[:id]
      serialized_keys = Identity::PermissionCatalog
        .grouped_json(locale: :en)
        .flat_map { |group| group[:permissions].pluck(:key) }
      assert_not_includes serialized_keys, contribution[:id]
    end
  end

  test "admin module permissions are an active subset and exclude public identity capabilities" do
    module_keys = Identity::AccountAccess::ADMIN_MODULES.values.flatten

    assert_empty module_keys - Identity::PermissionCatalog.active_keys
    assert_not_includes module_keys, "system.jobs.retry"
    assert_not_includes module_keys, "store.products.read"
    assert_not_includes module_keys, "forum.conversations.create"
    assert_equal(
      %w[
        identity.groups.manage
        identity.groups.members.assign
        identity.groups.permissions.manage
        identity.groups.read
      ],
      Identity::AccountAccess::ADMIN_MODULES.fetch("identity")
    )
  end
end
