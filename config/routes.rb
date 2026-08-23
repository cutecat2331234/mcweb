Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  constraints SidekiqWebConstraint do
    mount Sidekiq::Web => "/jobs"
  end

  root "website/home#index"
  get "signed-out", to: "website/home#index", as: :signed_out_landing

  get "minecraft/cached-skins/:id/:variant",
    to: "minecraft/cached_skins#show",
    as: :minecraft_cached_skin,
    constraints: { id: /\d+/, variant: /avatar|bust|full|skin|cape/ }

  # Public REST API (v1). Key-authenticated, JSON only. See docs/API.md.
  namespace :api do
    namespace :v1 do
      root "root#index"
      get "me", to: "me#show"
      resources :notifications, only: %i[index destroy] do
        member { post :read }
        collection { post :read_all }
      end
      resources :conversations, only: %i[index show] do
        member do
          post :reply
          post :read
        end
      end
      resources :categories, only: :index
      resources :tags, only: :index do
        member { post :subscription }
      end
      resources :bookmarks, only: :index
      resources :topics, only: %i[index show create] do
        member do
          post :bookmark
          post :subscription
          post :solve
          post :unsolve
        end
      end
      resources :posts, only: %i[show create] do
        member do
          get :reactions
          post :react
        end
      end
      resources :users, only: %i[index show] do
        member { match :follow, via: %i[put delete] }
        resources :profile_posts, only: %i[index create], path: "profile-posts"
      end
      namespace :staff do
        root "root#index"
        resources :moderation_cases,
          path: "moderation-cases",
          only: %i[index show] do
          collection do
            post :authorize_action, path: "authorize-action"
            post :execute_action, path: "execute-action"
          end
          member do
            post :claim
            post :assign
            post :notes
          end
        end
      end
    end
  end

  patch "locale", to: "locale#update", as: :locale

  get "theme-assets/:template_key/*path", to: "frontend/template_assets#show", as: :frontend_theme_asset, format: false

  namespace :setup, path: "setup" do
    root "wizard#index"
    get "complete", to: "wizard#complete", as: :complete
    get ":step", to: "wizard#show", as: :step
    patch ":step", to: "wizard#update"
  end

  namespace :admin do
    root "dashboard#index"
    get "plugins/:vendor/:name/*plugin_path",
      to: "plugin_pages#show",
      as: :plugin_page,
      constraints: {
        vendor: /[a-z][a-z0-9._-]*/,
        name: /[a-z][a-z0-9._-]*/
      }
    unless Rails.env.production?
      # Static design references are intentionally unavailable in production.
      get "dashboard_pro_demo", to: "dashboard_pro_demo#index"
      get "arco-demo", to: "arco_demo#index"
    end
    resources :users, only: %i[index show edit update] do
      member do
        post :ban
        post :unban
        post :grant_badge
        post :revoke_badge
        post :warn
        post :staff_note
        post :silence
        post :unsilence
        post :set_trust_level
        post :authorize_store_credit_adjustment
        post :adjust_store_credit
        post :clean_spam
        get :permissions, action: :permission_explanation
      end
    end
    get "store/store-credits",
      to: "users#store_credit_index",
      as: :store_credit_users
    get "store/store-credits/:id",
      to: "users#store_credit_show",
      as: :store_credit_user
    resources :roles
    resources :audit_logs, only: %i[index show] do
      collection { get :export }
    end
    namespace :forum do
      resource :settings, only: %i[show update] do
        post :test_webhook
        post :test_all_webhooks
        post :test_event_webhook
        post :test_all_event_webhooks
        get :webhook_test_status
      end
      resources :categories
      resources :sections, only: %i[index show new create edit update destroy] do
        member do
          get :lifecycle
          patch :archive
          patch :restore
          patch :migrate_topics
        end
      end
      resources :topics, only: %i[index show]
      resources :reports, only: %i[index show update], param: :public_id do
        member do
          patch :claim
          patch :resolve_target
          post :reveal_evidence
        end
      end
      resources :report_appeals,
        path: "report-appeals",
        only: %i[index show update],
        param: :public_id do
          member { post :evidence, action: :seal_evidence }
        end
      resources :mutes, only: %i[create destroy]
      resources :censored_words, only: %i[index create destroy]
      resources :badges, only: %i[index new create edit update destroy]
      resources :tags
      resources :tag_groups
      resources :warnings, only: %i[index]
      resources :warning_templates, path: "warning-templates"
      resources :user_titles, path: "user-titles"
      resources :user_groups, path: "user-groups" do
        member do
          post :add_member
          delete :remove_member
          post :set_primary
        end
      end
      resources :notices
      resources :help_articles, path: "help-articles"
      resources :smilies
      resources :reaction_types, path: "reaction-types"
      resources :themes
      resources :pages
      resources :phrases
      resources :custom_bbcodes, path: "custom-bbcodes"
      resources :attachments, only: %i[index destroy] do
        collection do
          delete :prune_orphans
        end
        member do
          post :retry_scan
          post :retry_cleanup
          post :release_quarantine
          post :revoke_release
        end
      end
      get "stats", to: "stats#index"
      get "points", to: "points#index", as: :points
      get "points/settings", to: "points#settings", as: :points_settings
      patch "points/settings", to: "points#update_settings"
      get "points/adjust", to: "points#new_adjustment", as: :adjust_points
      post "points/adjust", to: "points#create_adjustment"
      get "scheduled-tasks", to: "scheduled_tasks#index", as: :scheduled_tasks
      resources :approvals, only: %i[index show] do
        member do
          post :approve
          post :reject
        end
      end
      resources :moderation_workbench,
        path: "moderation-workbench",
        controller: "moderation_workbench",
        only: %i[index show] do
        collection do
          post :authorize_action, path: "authorize-action"
          post :execute_action, path: "execute-action"
        end
        member do
          post :claim
          post :assign
          post :notes
        end
      end
      resources :user_fields, path: "user-fields"
      resources :topic_fields, path: "topic-fields"
      resources :canned_responses
      resources :webhook_deliveries, only: %i[index show] do
        collection do
          post :bulk_retry
        end
        member do
          post :retry
        end
      end
      resources :event_webhook_deliveries, only: %i[index show], path: "event-webhook-deliveries" do
        collection do
          post :bulk_retry
        end
        member do
          post :retry
        end
      end
    end
    namespace :store do
      resource :settings, only: %i[show update] do
        post :test_webhook
        post :test_all_webhooks
        get :webhook_test_status
      end
      resources :categories
      resources :products do
        member do
          post :duplicate
        end
      end
      resources :coupons
      resources :membership_types
      resources :user_memberships, only: %i[index show new create destroy] do
        collection do
          post :authorize_grant
        end
        member do
          post :authorize_revoke
          post :revoke
        end
      end
      resources :user_entitlements, only: %i[index show new create] do
        collection do
          post :authorize_grant
        end
        member do
          post :authorize_revoke
          post :revoke
        end
      end
      resources :gift_cards, only: %i[index show new create edit update]
      get "inventory", to: "inventory#index", as: :inventory
      post "inventory/authorize-adjustment",
           to: "inventory#authorize_adjustment",
           as: :inventory_authorize_adjustment
      post "inventory/adjust",
           to: "inventory#adjust",
           as: :inventory_adjust
      get "finance", to: "finance#index", as: :finance
      get "finance/documents/:id",
          to: "finance#document",
          as: :finance_document
      post "finance/documents/:id/transition",
           to: "finance#transition_document",
           as: :finance_document_transition
      post "finance/exports",
           to: "finance#create_export",
           as: :finance_exports
      get "finance/exports/:id/download",
          to: "finance#download_export",
          as: :finance_export_download
      post "finance/exports/:id/revoke",
           to: "finance#revoke_export",
           as: :finance_export_revoke
      resources :orders, only: %i[index show update] do
        collection do
          get :export
          patch :bulk_update
          post :authorize_high_risk_action
        end
        member do
          post :staff_note
        end
      end
      get "payment-providers",
        to: "payment_providers#show",
        as: :payment_providers
      patch "payment-providers",
        to: "payment_providers#update"
      post "payment-providers/stripe/connection-test",
        to: "payment_providers#test_connection",
        as: :payment_provider_connection_test
      get "payment-operations", to: "payment_operations#index", as: :payment_operations
      post "payment-operations/webhooks/:id/replay",
        to: "payment_operations#replay",
        as: :payment_webhook_replay
      resources :late_payment_cases, path: "late-payment-cases", only: :index do
        member do
          patch :acknowledge
        end
      end
      resources :payment_reconciliations,
        path: "payment-reconciliations",
        only: :index do
        collection do
          post :trigger
          post :manual_authorization
        end
        member do
          patch :review
        end
      end
      resources :disputes, only: %i[index show] do
        member do
          post :authorize_action
          post :execute_action
          post "evidence/:evidence_id/download-token",
               to: "disputes#evidence_download_token",
               as: :evidence_download_token
          get "evidence/:evidence_id/download",
              to: "disputes#evidence_download",
              as: :evidence_download
        end
      end
      unless Rails.env.production?
        get   "orders_pro_demo",      to: "orders_pro_demo#index"
        patch "orders_pro_demo/bulk", to: "orders_pro_demo#bulk", as: "orders_pro_demo_bulk"
      end
      resources :reviews, only: %i[index show update]
      resources :fulfillments, only: %i[index show] do
        member do
          post :authorize_action
          post :execute_action
        end
      end
      resources :webhook_deliveries, only: %i[index show] do
        collection do
          post :bulk_retry
        end
        member do
          post :retry
        end
      end
      resources :product_questions, only: %i[index destroy] do
        member do
          patch :hide
          patch :unhide
          patch "answers/:answer_id/hide", action: :hide_answer, as: :hide_answer
          patch "answers/:answer_id/unhide", action: :unhide_answer, as: :unhide_answer
        end
      end
      post :uploads, to: "uploads#create"
    end
    namespace :website do
      resources :pages do
        member do
          post :publish
          post :schedule
          post :archive
          get :discard, action: :discard_form, as: :discard_form
          post :discard
          get :preview
        end
        resources :blocks, only: %i[create update destroy] do
          collection do
            patch :reorder
          end
        end
        resources :revisions, controller: "page_revisions", only: %i[index show] do
          member do
            post :restore_draft
          end
        end
      end
      resources :articles do
        member do
          post :publish
          post :schedule
          post :archive
          get :discard, action: :discard_form, as: :discard_form
          post :discard
          get :preview
        end
        resources :revisions, controller: "article_revisions", only: %i[index show] do
          member do
            post :restore_draft
          end
        end
      end
      get "recycle-bin", to: "recycle_bin#index", as: :recycle_bin
      get "recycle-bin/:content_type/:id", to: "recycle_bin#show", as: :recycle_bin_item
      post "recycle-bin/:content_type/:id/restore", to: "recycle_bin#restore", as: :restore_recycle_bin_item
      post "recycle-bin/:content_type/:id/authorize-purge", to: "recycle_bin#authorize_purge", as: :authorize_purge_recycle_bin_item
      delete "recycle-bin/:content_type/:id/purge", to: "recycle_bin#purge", as: :purge_recycle_bin_item
      resources :nav_items, only: %i[index create update destroy] do
        collection do
          patch :reorder
        end
      end
      resources :themes do
        member do
          post :activate
        end
      end
    end
    namespace :frontend do
      resources :templates, only: %i[index create update destroy] do
        member do
          get :preview
        end
      end
    end
    namespace :minecraft do
      resources :servers do
        resources :world_backups, only: :create
        resources :world_restores, only: :create, param: :public_id do
          member do
            post :authorize
            post :execute
            post :plan_recovery
            post :authorize_recovery
            post :execute_recovery
            post :cancel_recovery
            post :takeover_recovery
          end
        end
        member do
          post :rotate_secret
          post :start
          post :stop
          post :restart
          post :exec_command
          post :console_command
          post :tail_logs
          post :sync_files
        end
      end
      resources :nodes do
        member do
          post :rotate_secret
          post :generate_pairing_token
        end
      end
      resources :players, only: %i[index], path: "players" do
        collection do
          post :kick
        end
      end
      resources :player_access_rules,
        only: %i[index create destroy],
        param: :public_id,
        path: "player-access-rules"
      post "players/:user_id/primary-account",
        to: "primary_accounts#create",
        as: :primary_account
      resources :primary_account_change_requests,
        only: :update,
        path: "primary-account-change-requests"
      resource :settings, only: %i[show update]
      resources :profile_fields, only: %i[index new create edit update destroy], path: "profile-fields"
      resources :integration_actions, only: %i[index new create edit update destroy], path: "integration-actions"
      resources :permission_group_mappings, only: %i[index create update destroy], path: "permission-group-mappings"
    end
    namespace :system do
      resource :feature_toggles, only: %i[show update], path: "feature-toggles"
      resource :rate_limits, only: %i[show update], path: "rate-limits"
      get "data-governance", to: "data_governance#index", as: :data_governance
      patch "data-governance/policies/:id",
        to: "data_governance#update_policy",
        as: :data_governance_policy
      post "data-governance/holds",
        to: "data_governance#create_hold",
        as: :data_governance_holds
      patch "data-governance/holds/:id/release",
        to: "data_governance#release_hold",
        as: :data_governance_release_hold
      post "data-governance/content/soft-delete",
        to: "data_governance#soft_delete",
        as: :data_governance_soft_delete
      patch "data-governance/records/:id/restore",
        to: "data_governance#restore",
        as: :data_governance_restore
      delete "data-governance/records/:id/purge",
        to: "data_governance#purge",
        as: :data_governance_purge
      resource :plugin_settings, only: %i[show update], path: "plugin-settings" do
        post :migrate
        post :rollback
      end
      resource :settings, only: %i[show update]
      resource :developer_workbench,
        only: :show,
        path: "developer-workbench",
        controller: "developer_workbench" do
        get :diagnostic
        post "clear-captures", action: :clear_captures, as: :clear_captures
        post "seed-scenario", action: :seed_scenario, as: :seed_scenario
        post "inject-attachment-state",
          action: :inject_attachment_state,
          as: :inject_attachment_state
        post "run-task", action: :run_task, as: :run_task
      end
      resources :jobs, only: %i[index] do
        post :run, on: :collection
      end
      resources :ip_bans, only: %i[index create destroy]
      resources :email_bans, only: %i[index new create edit update destroy]
      resources :api_keys, only: %i[index new create], path: "api-keys" do
        member do
          post :revoke
        end
      end
      resources :webhook_subscriptions, path: "webhook-subscriptions"
      resources :applications, only: %i[index] do
        collection do
          post :install_plugin
          post :enable_plugin
          post :disable_plugin
          post :recover_plugin
          post :rollback_plugin
          post :health_plugin
          post :reconcile_plugin_catalog
          delete :uninstall_plugin
        end
      end
    end
  end

  scope path: "app" do
    get "account", to: "account#show", as: :account
    namespace :account do
      resources :notifications, only: %i[index destroy] do
        member do
          patch :mark_read
          get :visit
        end
        collection do
          patch :mark_all_read
          patch :dismiss_alerts
        end
      end
    end

    namespace :identity do
      get "sign-in", to: "sessions#new", as: :sign_in
      get "session/two-factor", to: "sessions#two_factor", as: :session_two_factor
      post "session/two-factor", to: "sessions#verify_two_factor"
      resource :session, only: %i[show create destroy]
      get "register", to: "registrations#new", as: :registration_landing
      resources :registrations, only: %i[new create], path: "register"
      get "password_resets", to: "password_resets#new", as: :password_resets_landing
      resources :password_resets, only: %i[new create edit update], param: :token
      resource :email_verification, only: %i[show], path: "verify-email"
      get "resend-verification", to: "email_verification_resends#new", as: :email_verification_resend_landing
      resource :email_verification_resend, only: %i[new create], path: "resend-verification"
      resource :profile, only: %i[show update]
      get "security", to: "security#show"
      get "security/password", to: "passwords#edit", as: :security_password
      patch "security/password", to: "passwords#update"
      post "security/totp/setup", to: "security#setup_totp"
      post "security/totp/confirm", to: "security#confirm_totp"
      post "security/totp/disable", to: "security#disable_totp"
      post "security/totp/recovery-codes", to: "security#regenerate_recovery_codes"
      patch "security/email", to: "security#change_email"
      get "security/email-change/confirm",
          to: "email_changes#confirm",
          as: :email_change_confirmation
      get "security/email-change/revoke",
          to: "email_changes#revoke",
          as: :email_change_revocation
      delete "security/account", to: "security#close_account"
      resources :data_exports, only: %i[index create], path: "data-exports" do
        member do
          get :download
          post :retry
          delete :revoke
        end
      end
      resources :totp_recoveries,
                only: %i[new create edit update],
                param: :token,
                path: "security/totp/recovery"
      resources :sessions_management, only: %i[index destroy], path: "sessions"
    end

    namespace :staff do
      root "dashboard#index"
      resources :moderation_cases,
        path: "moderation-cases",
        only: %i[index show] do
        collection do
          post :authorize_action, path: "authorize-action"
          post :execute_action, path: "execute-action"
        end
        member do
          post :claim
          post :assign
          post :notes
        end
      end
      resources :report_appeals,
        path: "report-appeals",
        only: %i[index show update],
        param: :public_id do
          member { post :evidence, action: :seal_evidence }
        end
    end

    namespace :secure_evidence, path: "evidence" do
      resources :attachments, only: %i[create show destroy] do
        member { get :scan_status }
      end
    end

  scope module: :community, path: "forum", as: :forum do
    resources :sections, only: %i[index show] do
      member do
        post :subscription, action: :toggle_subscription
        patch :subscription, action: :update_subscription
        post :mute, action: :toggle_mute
        patch :mark_all_read
      end
    end
    resources :drafts, only: %i[index create update destroy], param: :id do
      member do
        get :edit
        post :publish
      end
    end
    namespace :moderation, path: "moderation" do
      resources :approvals, only: %i[index]
    end
    get "blocks", to: "blocks#index", as: :blocks
    get "ignores", to: "ignores#index", as: :ignores
    get "muted", to: "mutes#index", as: :muted
    put "users/:username/block", to: "blocks#update", as: :block_user
    delete "users/:username/block", to: "blocks#destroy"
    put "users/:username/ignore", to: "ignores#update", as: :ignore_user
    delete "users/:username/ignore", to: "ignores#destroy"
    put "users/:username/follow", to: "follows#update", as: :user_follow
    delete "users/:username/follow", to: "follows#destroy"
    get "users/:username/followers", to: "followers#index", as: :user_followers
    resources :polls, only: [] do
      member do
        post :vote
        post :close
        post :revoke
        get :voters
        get :export
      end
    end
    get "latest.rss", to: "rss#latest", as: :latest_rss, defaults: { format: :rss }
    get "top.rss", to: "rss#top", as: :top_rss, defaults: { format: :rss }
    get "sections/:id.rss", to: "rss#section", as: :section_rss, defaults: { format: :rss }
    get "topics/:id.rss", to: "rss#topic", as: :topic_rss, defaults: { format: :rss }
    get "categories/:slug.rss", to: "rss#category", as: :category_rss, defaults: { format: :rss }
    get "categories/:slug", to: "categories#show", as: :category
    resources :topics, only: %i[show new create update destroy] do
      collection do
        get :similar_titles
        patch :bulk_moderate
      end
      resource :reply_draft, only: %i[update destroy], controller: "reply_drafts"
      member do
        post :visit_receipt
        post :moderate
        post :move
        post :copy
        post :merge
        post :split
        post :mark_solved
        post :unsolve
        patch :slow_mode, action: :update_slow_mode
        patch :auto_close, action: :update_auto_close
        patch :auto_open, action: :update_auto_open
        patch :auto_bump, action: :update_auto_bump
        patch :auto_archive, action: :update_auto_archive
        post :mark_unread
        post :subscription, action: :toggle_subscription
        patch :subscription, action: :update_subscription
        post :mute, action: :toggle_mute
        post :bookmark, action: :toggle_bookmark
        post :staff_note
        post :reply_ban
        post :reply_unban
        post :invite
        post :close_own
        post :reopen_own
        post :share_as_pm
        get :export
      end
    end
    resources :posts, only: %i[create update destroy] do
      member do
        post :reaction, action: :toggle_reaction
        post :bookmark, action: :toggle_bookmark
        post :moderate
        post :fork_topic
        get :edits
        get :raw
        post :restore_edit
        post :restore
        post :approve
        post :reject
      end
    end
    resources :reports, only: %i[index show new create], param: :public_id do
      member do
        post :supplements
        patch :withdraw
        post :appeal_draft
        post :evidence, action: :seal_evidence
      end
    end
    resources :report_appeals,
      path: "report-appeals",
      only: %i[index show],
      param: :public_id do
      member do
        patch :submit
        patch :cancel
      end
    end
    resources :notifications, only: %i[index destroy] do
      member do
        patch :mark_read
        get :visit
      end
      collection do
        patch :mark_all_read
        patch :dismiss_alerts
      end
    end
    get "search.rss", to: "rss#ad_hoc_search", as: :search_rss, defaults: { format: :rss }
    get "search.opml", to: "rss#ad_hoc_search_opml", as: :search_opml, defaults: { format: :xml }
    get "search/histories.opml", to: "rss#search_histories_opml", as: :search_histories_opml, defaults: { format: :xml }
    get "search/feeds.opml", to: "rss#search_feeds_opml", as: :search_feeds_opml, defaults: { format: :xml }
    delete "search/history", to: "search_histories#clear", as: :clear_search_histories
    resources :search_histories, only: %i[destroy], path: "search/history"
    get "search", to: "search#index"
    get "search/suggest", to: "search#suggest", as: :search_suggest
    get "mentions/search", to: "mentions#search", as: :mention_search
    get "latest", to: "latest#index"
    get "top", to: "top#index"
    get "staff", to: "staff#index"
    get "new", to: "new#index", as: :new_feed
    post "new/dismiss", to: "new#dismiss", as: :dismiss_new_feed
    get "activity", to: "activity#index"
    get "following", to: "follows#index"
    post "announcements/dismiss", to: "announcements#dismiss", as: :dismiss_announcement
    post "notices/:id/dismiss", to: "notices#dismiss", as: :dismiss_notice
    get "push/public_key", to: "push#public_key", as: :push_public_key
    post "push/subscribe", to: "push#subscribe", as: :push_subscribe
    delete "push/unsubscribe", to: "push#unsubscribe", as: :push_unsubscribe
    get "unread", to: "unread#index"
    get "assigned", to: "assigned#index"
    patch "unread/mark_all_read", to: "unread#mark_all_read", as: :unread_mark_all_read
    patch "unread/mark_selected_read", to: "unread#mark_selected_read", as: :unread_mark_selected_read
    resources :unread_filter_presets, only: %i[create destroy], path: "unread/filter_presets"
    post "preview", to: "previews#create"
    resources :uploads, only: %i[create show]
    resources :attachments, only: %i[create show] do
      member { get :scan_status }
    end
    get "bookmarks", to: "bookmarks#index"
    patch "bookmarks/:id", to: "bookmarks#update", as: :bookmark
    get "preferences", to: "preferences#show"
    patch "preferences", to: "preferences#update"
    get "watching.opml", to: "rss#watching_opml", as: :watching_opml, defaults: { format: :xml }
    get "watching", to: "watched#index"
    get "watching/tags", to: "watched#tags", as: :watched_tags
    get "watching/tag-topics", to: "watched#tag_topics", as: :watched_tag_topics
    get "tags", to: "tags#index", as: :tags
    get "tag-suggest", to: "tags#suggest", as: :tag_suggest
    get "badges", to: "badges#index", as: :badges
    get "badges/:id", to: "badges#show", as: :badge
    get "tags/:slug.rss", to: "rss#tag", as: :tag_rss, defaults: { format: :rss }
    get "sitemap.xml", to: "sitemaps#index", as: :sitemap, defaults: { format: :xml }
    get "digest/unsubscribe", to: "digest_unsubscribes#show", as: :unsubscribe_forum_digest
    get "notifications/email/unsubscribe", to: "notification_type_unsubscribes#show", as: :unsubscribe_notification_type
    get "saved_searches.opml", to: "rss#saved_searches_opml", as: :saved_searches_opml, defaults: { format: :xml }
    get "saved_searches/:id.rss", to: "rss#saved_search", as: :saved_search_rss, defaults: { format: :rss }
    post "webhook_deliveries/:id/retry", to: "saved_search_webhook_deliveries#retry", as: :retry_saved_search_webhook_delivery
    resources :saved_searches, only: %i[index create update destroy] do
      collection do
        get :unsubscribe
      end
    end
    get "tags/:slug", to: "tags#show", as: :tag
    post "tags/:slug/subscription", to: "tags#toggle_subscription", as: :tag_subscription
    patch "tags/:slug/subscription", to: "tags#update_subscription", as: :tag_subscription_level
    resources :conversations, only: %i[index show new create] do
      member do
        post :read_receipt
        post :archive
        post :unarchive
        post :mute
        post :unmute
        post :lock_invites
        post :unlock_invites
        post :mark_unread
        post :set_label
        post :toggle_star
      end
      resources :messages, only: %i[create update destroy], controller: "conversation_messages"
      resource :message_draft, only: %i[update destroy], controller: "conversation_message_drafts"
      resources :participants, only: %i[create destroy], controller: "conversation_participants", param: :username
    end
    get "members", to: "members#index", as: :members
    get "statistics", to: "forum_stats#index", as: :statistics
    get "help", to: "help#index", as: :help
    get "help/:slug", to: "help#show", as: :help_article
    get "pages/:slug", to: "pages#show", as: :page
    get "leaderboard", to: "leaderboard#index", as: :leaderboard
    post "check-in", to: "check_ins#create", as: :check_in
    resources :users, only: %i[show update], param: :id do
      member do
        get :card
      end
    end
    post "users/:username/profile_posts", to: "profile_posts#create", as: :user_profile_posts
    delete "profile_posts/:id", to: "profile_posts#destroy", as: :profile_post
    patch "profile_posts/:id", to: "profile_posts#update"
    post "profile_posts/:id/comments", to: "profile_post_comments#create", as: :profile_post_comments
    delete "profile_post_comments/:id", to: "profile_post_comments#destroy", as: :profile_post_comment
    patch "profile_post_comments/:id", to: "profile_post_comments#update"
  end

    get "payments/fake/:id", to: "payments/fake#show", as: :fake_payment
    post "payments/fake/:id", to: "payments/fake#create"
    post "developer-mode/persona",
      to: "developer_mode_tools#switch_persona",
      as: :developer_mode_switch_persona

    scope module: :commerce, path: "store", as: :store do
    get "image-packs/:pack_id/*texture_path", to: "image_pack_textures#show", as: :image_pack_texture, format: false
    get "sitemap.xml", to: "sitemaps#index", as: :sitemap, defaults: { format: :xml }
    get "latest.rss", to: "rss#latest", as: :latest_rss, defaults: { format: :rss }
    get "categories/:slug.rss", to: "rss#category", as: :category_rss, defaults: { format: :rss }
    get "categories/:slug", to: "categories#show", as: :category
    get "gift_cards", to: "gift_cards#index", as: :gift_cards
    resources :products, only: %i[index show] do
      collection do
        get :recently_viewed
        delete :clear_recently_viewed
      end
      member do
        post :view_receipt
        post :wishlist, to: "wishlist#toggle"
        post :reorder
        post :discussion, action: :create_discussion
        post :price_alert, to: "price_alerts#create"
        post :stock_alert, to: "stock_alerts#create"
        post :availability_alert, to: "availability_alerts#create"
        get :preview
      end
      resources :reviews, only: %i[create update destroy], controller: "reviews" do
        member do
          post :helpful, action: :toggle_helpful
          post :share_to_forum
        end
      end
      resources :questions, only: %i[create], controller: "product_questions"
      patch "questions/:question_id", to: "product_questions#update", as: :update_question
      delete "questions/:question_id", to: "product_questions#destroy", as: :delete_question
      post "questions/:question_id/answer", to: "product_questions#answer", as: :answer_question
      patch "questions/:question_id/answers/:answer_id", to: "product_questions#update_answer", as: :update_answer
      delete "questions/:question_id/answers/:answer_id", to: "product_questions#destroy_answer", as: :delete_answer
      post "questions/:question_id/answers/:answer_id/helpful", to: "product_questions#toggle_answer_helpful", as: :helpful_answer
    end
    get "compare", to: "compare#show"
    post "compare/toggle", to: "compare#toggle", as: :toggle_compare
    post "compare/import_wishlist", to: "compare#import_wishlist", as: :import_wishlist_compare
    delete "compare", to: "compare#clear"
    get "compare/:token", to: "compare#public_show", as: :public_compare
    get "wishlist", to: "wishlist#index"
    post "wishlist/add_all_to_cart", to: "wishlist#add_all_to_cart", as: :add_all_to_cart_wishlist
    patch "wishlist/:product_id/note", to: "wishlist#update_note", as: :note_wishlist
    post "wishlist/:product_id/add_to_cart", to: "wishlist#add_to_cart", as: :add_wishlist_item_to_cart
    post "wishlist/share", to: "wishlist#share"
    resources :wishlist_filter_presets, only: %i[index create destroy], path: "wishlist/filter_presets"
    get "wishlist/:token", to: "wishlist#public_show", as: :public_wishlist
    resources :stock_alerts, only: %i[index destroy] do
      member do
        post :add_to_cart
      end
    end
    resources :price_alerts, only: %i[index destroy]
    resources :availability_alerts, only: %i[index destroy]
    resource :cart, only: %i[show update] do
      post :preview_coupon, on: :member
      post :preview_gift_card, on: :member
      delete :clear_coupon, on: :member
      delete :clear_gift_card, on: :member
      post :move_to_wishlist, on: :member
      delete :clear, on: :member
    end
    resources :orders, only: %i[index show] do
      resources :disputes,
                controller: "order_disputes",
                only: %i[create destroy],
                param: :public_id
      collection do
        get :export
      end
      member do
        post :cancel
        post :refund
        delete "refunds/:refund_id", to: "refunds#destroy", as: :withdraw_refund
        get :receipt
        get :receipt_pdf
        get :packing_slip
        post :reorder
        post :refresh_download
      end
    end
    resource :checkout, only: %i[show create], controller: "checkout" do
      post :preview_coupon, on: :member
      post :preview_gift_card, on: :member
      post :preview_store_credit, on: :member
    end
    get "coupons/:code", to: "coupons#show", as: :coupon
    post "coupons/:code/apply", to: "coupons#apply", as: :apply_coupon
    get "gift_cards/:code", to: "gift_cards#show", as: :gift_card
    post "gift_cards/:code/apply", to: "gift_cards#apply", as: :apply_gift_card
    post "webhooks/:provider", to: "webhooks#create", as: :webhook
    get "downloads/:token", to: "downloads#show", as: :download
    get "wallet", to: "wallet#show"
    get "preferences", to: "preferences#show"
    patch "preferences", to: "preferences#update"
    resources :shipping_addresses, only: %i[index create update destroy] do
      member do
        post :make_default
      end
    end
    end

    namespace :minecraft, path: "minecraft" do
      resource :link, only: %i[show create], controller: "link"
      post "accounts/:id/primary",
        to: "primary_accounts#create",
        as: :primary_account
      delete "accounts/:id",
        to: "identity_links#destroy",
        as: :identity_link
      delete "primary-account-change-requests/:id",
        to: "primary_account_change_requests#destroy",
        as: :primary_account_change_request
    end
  end

  scope module: :website, as: :website do
    resources :articles, only: %i[index show], path: "blog"
  end

  get "website/blog", to: redirect("/blog")
  get "website/blog/:slug", to: redirect("/blog/%{slug}")
  get "website/pages/:slug", to: redirect("/%{slug}")

  get "plugins/:vendor/:name/*plugin_path",
    to: "plugin_pages#show",
    as: :plugin_page,
    constraints: {
      vendor: /[a-z][a-z0-9._-]*/,
      name: /[a-z][a-z0-9._-]*/
    }

  get "/forum(/*path)", to: redirect { |params, _| params[:path].present? ? "/app/forum/#{params[:path]}" : "/app/forum/latest" }
  get "/store(/*path)", to: redirect { |params, _| params[:path].present? ? "/app/store/#{params[:path]}" : "/app/store/products" }
  get "/identity(/*path)", to: redirect { |params, _|
    path = params[:path].presence
    if path == "session"
      "/app/identity/sign-in"
    elsif path.present?
      "/app/identity/#{path}"
    else
      "/app/identity/sign-in"
    end
  }
  get "/minecraft/link", to: redirect("/app/minecraft/link")
  get "/payments/fake/:id", to: redirect("/app/payments/fake/%{id}")

  get "health/live", to: "health#live"
  get "health/ready", to: "health#ready"
  get "minecraft/sync/:token", to: "minecraft/sync_files#show", as: :minecraft_sync_file

  namespace :minecraft do
    namespace :connector do
      scope ":server_id" do
        post "heartbeat", to: "api#heartbeat"
        post "link_codes", to: "api#link_codes"
        post "presence", to: "api#presence"
        post "profile_fields", to: "api#profile_fields"
        post "permission_groups", to: "api#permission_groups"
        post "server_stats", to: "api#server_stats"
        get "config", to: "api#fetch_config"
        post "whois", to: "api#whois"
        post "events", to: "api#events"
        get "tasks", to: "api#tasks"
        post "tasks/:id/complete", to: "api#complete"
      end
    end
    namespace :nodes do
      post "pair", to: "pairing#create"
      scope ":node_id" do
        post "heartbeat", to: "api#heartbeat"
        get "operations/next", to: "api#next_operation"
        post "operations/:id/lease", to: "api#renew_operation_lease"
        post "operations/:id/complete", to: "api#complete_operation"
        post "operations/:id/acknowledge", to: "api#acknowledge_operation"
        get "tasks", to: "api#tasks"
        get "events", to: "events#show"
        post "tasks/:id/complete", to: "api#complete"
        post "instances/:server_id/report", to: "api#report"
      end
    end
  end

  get ":slug", to: "website/pages#show", as: :website_page, constraints: WebsiteSlugConstraint
end
