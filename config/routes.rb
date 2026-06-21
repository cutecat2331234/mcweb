Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  constraints SidekiqWebConstraint do
    mount Sidekiq::Web => "/jobs"
  end

  root "website/home#index"

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
    resources :users, only: %i[index show edit update] do
      member do
        post :ban
        post :unban
        post :grant_badge
        post :warn
        post :staff_note
        post :silence
        post :unsilence
        post :set_trust_level
        post :adjust_store_credit
      end
    end
    resources :roles, only: %i[index show create update destroy]
    resources :audit_logs, only: %i[index show]
    namespace :forum do
      resource :settings, only: %i[show update] do
        post :test_webhook
        post :test_all_webhooks
        post :test_event_webhook
        post :test_all_event_webhooks
        get :webhook_test_status
      end
      resources :categories
      resources :sections, only: %i[index show new create edit update]
      resources :topics, only: %i[index show]
      resources :reports, only: %i[index show update]
      resources :mutes, only: %i[create destroy]
      resources :censored_words, only: %i[index create destroy]
      resources :badges, only: %i[index new create edit update destroy]
      resources :tags
      resources :tag_groups
      resources :warnings, only: %i[index]
      resources :approvals, only: %i[index show] do
        member do
          post :approve
          post :reject
        end
      end
      resources :user_fields, path: "user-fields"
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
      resources :user_memberships, only: %i[index show new create destroy]
      resources :gift_cards, only: %i[index show new create edit update]
      resources :orders, only: %i[index show update] do
        collection do
          get :export
          patch :bulk_update
        end
        member do
          post :staff_note
        end
      end
      resources :reviews, only: %i[index show update]
      resources :fulfillments, only: %i[index show update]
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
        end
      end
      post :uploads, to: "uploads#create"
    end
    namespace :website do
      resources :pages
      resources :articles
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
        member do
          post :rotate_secret
          post :start
          post :stop
          post :restart
          post :exec_command
          post :console_command
          post :tail_logs
          post :backup_world
          post :restore_world
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
      resource :settings, only: %i[show update]
      resources :profile_fields, only: %i[index new create edit update destroy], path: "profile-fields"
      resources :integration_actions, only: %i[index new create edit update destroy], path: "integration-actions"
      resources :permission_group_mappings, only: %i[index create update destroy], path: "permission-group-mappings"
    end
    namespace :system do
      resource :feature_toggles, only: %i[show update], path: "feature-toggles"
      resource :settings, only: %i[show update]
      resources :jobs, only: %i[index]
      resources :ip_bans, only: %i[index create destroy]
      resources :applications, only: %i[index]
    end
  end

  scope path: "app" do
    namespace :identity do
      get "sign-in", to: "sessions#new", as: :sign_in
      resource :session, only: %i[show create destroy]
      resources :registrations, only: %i[new create], path: "register"
      resources :password_resets, only: %i[new create edit update], param: :token
      resource :email_verification, only: %i[show], path: "verify-email"
      resource :email_verification_resend, only: %i[new create], path: "resend-verification"
      get "security", to: "security#show"
      post "security/totp/setup", to: "security#setup_totp"
      post "security/totp/confirm", to: "security#confirm_totp"
      post "security/totp/disable", to: "security#disable_totp"
      resources :sessions_management, only: %i[index destroy], path: "sessions"
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
    post "users/:username/block", to: "blocks#create", as: :block_user
    post "users/:username/ignore", to: "ignores#create", as: :ignore_user
    post "users/:username/follow", to: "follows#create", as: :user_follow
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
    get "sections/:id.rss", to: "rss#section", as: :section_rss, defaults: { format: :rss }
    get "topics/:id.rss", to: "rss#topic", as: :topic_rss, defaults: { format: :rss }
    get "categories/:slug.rss", to: "rss#category", as: :category_rss, defaults: { format: :rss }
    get "categories/:slug", to: "categories#show", as: :category
    resources :topics, only: %i[show new create update] do
      collection do
        get :similar_titles
        patch :bulk_moderate
      end
      resource :reply_draft, only: %i[update destroy], controller: "reply_drafts"
      member do
        post :moderate
        post :move
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
    resources :reports, only: %i[new create]
    resources :notifications, only: %i[index] do
      member do
        patch :mark_read
        get :visit
      end
      collection do
        patch :mark_all_read
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
    get "activity", to: "activity#index"
    get "following", to: "follows#index"
    post "announcements/dismiss", to: "announcements#dismiss", as: :dismiss_announcement
    get "unread", to: "unread#index"
    get "assigned", to: "assigned#index"
    patch "unread/mark_all_read", to: "unread#mark_all_read", as: :unread_mark_all_read
    patch "unread/mark_selected_read", to: "unread#mark_selected_read", as: :unread_mark_selected_read
    resources :unread_filter_presets, only: %i[create destroy], path: "unread/filter_presets"
    post "preview", to: "previews#create"
    post "uploads", to: "uploads#create"
    resources :attachments, only: %i[create show]
    get "bookmarks", to: "bookmarks#index"
    patch "bookmarks/:id", to: "bookmarks#update", as: :bookmark
    get "preferences", to: "preferences#show"
    patch "preferences", to: "preferences#update"
    get "watching.opml", to: "rss#watching_opml", as: :watching_opml, defaults: { format: :xml }
    get "watching", to: "watched#index"
    get "watching/tags", to: "watched#tags", as: :watched_tags
    get "watching/tag-topics", to: "watched#tag_topics", as: :watched_tag_topics
    get "tags", to: "tags#index", as: :tags
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
        post :archive
        post :unarchive
        post :mute
        post :unmute
      end
      resources :messages, only: %i[create], controller: "conversation_messages"
      resources :participants, only: %i[create destroy], controller: "conversation_participants", param: :username
    end
    get "members", to: "members#index", as: :members
    resources :users, only: %i[show update], param: :id do
      member do
        get :card
      end
    end
  end

    get "payments/fake/:id", to: "payments/fake#show", as: :fake_payment
    post "payments/fake/:id", to: "payments/fake#create"

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
        post :wishlist, to: "wishlist#toggle"
        post :reorder
        post :discussion, action: :create_discussion
        post :price_alert, to: "price_alerts#create"
        post :stock_alert, to: "stock_alerts#create"
        post :availability_alert, to: "availability_alerts#create"
        get :preview
        resources :reviews, only: %i[create destroy], controller: "reviews" do
          member do
            post :helpful, action: :toggle_helpful
            post :share_to_forum
          end
        end
        resources :questions, only: %i[create], controller: "product_questions"
        post "questions/:question_id/answer", to: "product_questions#answer", as: :answer_question
        post "questions/:question_id/answers/:answer_id/helpful", to: "product_questions#toggle_answer_helpful", as: :helpful_answer
      end
    end
    get "compare", to: "compare#show"
    post "compare/toggle", to: "compare#toggle", as: :toggle_compare
    post "compare/import_wishlist", to: "compare#import_wishlist", as: :import_wishlist_compare
    delete "compare", to: "compare#clear"
    get "compare/share", to: "compare#share"
    get "compare/:token", to: "compare#public_show", as: :public_compare
    get "wishlist", to: "wishlist#index"
    post "wishlist/add_all_to_cart", to: "wishlist#add_all_to_cart", as: :add_all_to_cart_wishlist
    patch "wishlist/:product_id/note", to: "wishlist#update_note", as: :note_wishlist
    post "wishlist/:product_id/add_to_cart", to: "wishlist#add_to_cart", as: :add_wishlist_item_to_cart
    get "wishlist/share", to: "wishlist#share"
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
    resources :orders, only: %i[index show create] do
      collection do
        get :export
      end
      member do
        post :cancel
        post :refund
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
    end
  end

  scope module: :website, as: :website do
    resources :articles, only: %i[index show], path: "blog"
  end

  get "website/blog", to: redirect("/blog")
  get "website/blog/:slug", to: redirect("/blog/%{slug}")
  get "website/pages/:slug", to: redirect("/%{slug}")

  get "/forum(/*path)", to: redirect { |params, _| params[:path].present? ? "/app/forum/#{params[:path]}" : "/app/forum" }
  get "/store(/*path)", to: redirect { |params, _| params[:path].present? ? "/app/store/#{params[:path]}" : "/app/store" }
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
        get "tasks", to: "api#tasks"
        get "events", to: "events#show"
        post "tasks/:id/complete", to: "api#complete"
        post "instances/:server_id/report", to: "api#report"
      end
    end
  end

  get ":slug", to: "website/pages#show", as: :website_page, constraints: WebsiteSlugConstraint
end
