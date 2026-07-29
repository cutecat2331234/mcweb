# frozen_string_literal: true

module Operations
  class DeveloperScenarioSeeder < ApplicationService
    SCENARIOS = %w[personas forum store all].freeze
    PERSONA_ATTRIBUTES = {
      "owner" => {
        username: "mcweb_dev_owner",
        email: "mcweb-dev-owner@example.test",
        account_type: "owner"
      },
      "moderator" => {
        username: "mcweb_dev_moderator",
        email: "mcweb-dev-moderator@example.test",
        account_type: "staff"
      },
      "member" => {
        username: "mcweb_dev_member",
        email: "mcweb-dev-member@example.test",
        account_type: "member"
      }
    }.freeze

    def initialize(scenario:, actor: nil)
      @scenario = scenario.to_s
      @actor = actor
    end

    def call
      return unavailable unless Mcweb::DeveloperMode.enabled?
      return invalid_scenario unless SCENARIOS.include?(@scenario)

      result = {}
      User.transaction do
        personas = seed_personas
        result[:personas] = personas.transform_values(&:public_id)
        result[:forum] = seed_forum(personas) if %w[forum all].include?(@scenario)
        result[:store] = seed_store if %w[store all].include?(@scenario)
      end

      Administration::AuditLogger.call(
        actor: @actor,
        action: "developer_mode.scenario_seeded",
        metadata: {
          scenario: @scenario,
          resources: result.transform_values do |value|
            value.is_a?(Hash) ? value.keys.map(&:to_s).sort : "created"
          end
        }
      )

      ServiceResult.success(result)
    rescue ActiveRecord::RecordInvalid,
      ActiveRecord::RecordNotUnique,
      ActiveRecord::StatementInvalid => error
      ServiceResult.failure(
        error: "developer_scenario_seed_failed",
        code: error.class.name
      )
    end

    private

    def seed_personas
      PERSONA_ATTRIBUTES.to_h do |persona, attributes|
        user = User.find_or_initialize_by(developer_mode_persona: persona)
        if user.new_record?
          password = SecureRandom.base64(48)
          user.assign_attributes(
            attributes.merge(
              password: password,
              password_confirmation: password,
              status: "active",
              display_name: "Developer #{persona.titleize}",
              email_verified: true,
              email_verified_at: Time.current,
              developer_mode_email_verified: true,
              require_totp: false
            )
          )
        else
          user.assign_attributes(
            status: "active",
            account_type: attributes.fetch(:account_type),
            email_verified: true,
            email_verified_at: user.email_verified_at || Time.current,
            developer_mode_email_verified: true,
            require_totp: false
          )
        end
        user.save!
        reset_persona_access(user, persona)
        [ persona, user ]
      end
    end

    def reset_persona_access(user, persona)
      user.user_roles.destroy_all
      user.group_memberships.destroy_all
      user.admin_module_grants.destroy_all
      return unless persona == "moderator"

      role = Role.find_by(key: "moderator")
      UserRole.find_or_create_by!(user: user, role: role) if role
      user.admin_module_grants.find_or_create_by!(module_key: "forum") do |grant|
        grant.granted_by = @actor
        grant.granted_at = Time.current
      end
    end

    def seed_forum(personas)
      category = Community::Category.find_or_create_by!(
        slug: "developer-mode"
      ) do |record|
        record.name = "Developer Mode"
        record.description = "Disposable local development scenarios"
        record.position = 9_900
      end
      section = Community::Section.find_or_create_by!(
        category: category,
        slug: "playground"
      ) do |record|
        record.name = "Scenario Playground"
        record.description = "Local test content"
        record.position = 9_900
      end
      moderator = personas.fetch("moderator")
      Community::SectionModerator.find_or_create_by!(
        section: section,
        user: moderator
      )

      member = personas.fetch("member")
      topic = Community::Topic.find_or_create_by!(
        section: section,
        user: member,
        title: "Developer Mode baseline scenario"
      ) do |record|
        record.status = "published"
        record.last_posted_at = Time.current
      end
      topic.posts.find_or_create_by!(floor_number: 1) do |post|
        post.user = member
        post.status = "published"
        post.body = "Disposable baseline content for local development."
      end

      {
        category: category.slug,
        section: section.slug,
        topic: topic.public_id
      }
    end

    def seed_store
      product = Commerce::Product.find_or_create_by!(
        slug: "developer-mode-test-product"
      ) do |record|
        record.name = "Developer Mode Test Product"
        record.description = "Disposable local product for fake payment scenarios."
        record.product_type = "digital"
        record.price_cents = 990
        record.currency = "CNY"
        record.stock = 100
        record.status = "active"
        record.minimum_quantity = 1
        record.maximum_quantity = 10
      end

      {
        product: product.public_id,
        slug: product.slug
      }
    end

    def unavailable
      ServiceResult.failure(
        error: "developer_mode_not_enabled",
        code: "developer_mode_not_enabled"
      )
    end

    def invalid_scenario
      ServiceResult.failure(
        error: "developer_scenario_invalid",
        code: "developer_scenario_invalid"
      )
    end
  end
end
