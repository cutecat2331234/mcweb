Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  mount MissionControl::Jobs::Engine, at: "/jobs"

  root "website/home#index"

  namespace :setup, path: "setup" do
    root "wizard#index"
    get "complete", to: "wizard#complete", as: :complete
    get ":step", to: "wizard#show", as: :step
    patch ":step", to: "wizard#update"
  end

  namespace :identity do
    get "sign-in", to: "sessions#new", as: :sign_in
    resource :session, only: %i[create destroy]
    resources :registrations, only: %i[new create], path: "register"
    resources :password_resets, only: %i[new create edit update], param: :token
    resource :email_verification, only: %i[show], path: "verify-email"
    resources :sessions_management, only: %i[index destroy], path: "sessions"
  end

  namespace :admin do
    root "dashboard#index"
    resources :users, only: %i[index show] do
      member do
        post :ban
        post :unban
        post :grant_badge
        post :warn
        post :staff_note
        post :silence
        post :unsilence
      end
    end
    resources :roles, only: %i[index show]
    resources :audit_logs, only: %i[index show]
    namespace :forum do
      resources :categories
      resources :sections, only: %i[index show new create edit update]
      resources :topics, only: %i[index show]
      resources :reports, only: %i[index show update]
      resources :mutes, only: %i[create destroy]
      resources :censored_words, only: %i[index create destroy]
      resources :badges, only: %i[index new create edit update destroy]
      resources :tags
      resources :canned_responses
    end
    namespace :store do
      resources :categories
      resources :products do
        member do
          post :duplicate
        end
      end
      resources :coupons
      resources :gift_cards, only: %i[index show new create edit update]
      resources :orders, only: %i[index show update] do
        collection do
          get :export
        end
        member do
          post :staff_note
        end
      end
      resources :reviews, only: %i[index show update]
      resources :fulfillments, only: %i[index show update]
      resources :product_questions, only: %i[index destroy] do
        member do
          patch :hide
          patch :unhide
        end
      end
      post :uploads, to: "uploads#create"
    end
    namespace :website do
      resources :pages, only: %i[index show]
      resources :articles, only: %i[index show]
    end
    namespace :minecraft do
      resources :servers, only: %i[index show]
    end
    namespace :system do
      resource :settings, only: %i[show update]
      resources :jobs, only: %i[index]
      resources :ip_bans, only: %i[index create destroy]
    end
  end

  scope module: :community, path: "forum", as: :forum do
    resources :sections, only: %i[index show] do
      member do
        post :subscription, action: :toggle_subscription
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
    resources :topics, only: %i[show new create update] do
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
        post :mark_unread
        post :subscription, action: :toggle_subscription
        post :mute, action: :toggle_mute
        post :bookmark, action: :toggle_bookmark
        post :staff_note
        post :reply_ban
        post :reply_unban
        post :invite
        post :close_own
        post :reopen_own
        post :share_as_pm
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
    get "search", to: "search#index"
    get "mentions/search", to: "mentions#search", as: :mention_search
    get "latest", to: "latest#index"
    get "activity", to: "activity#index"
    get "following", to: "follows#index"
    post "announcements/dismiss", to: "announcements#dismiss", as: :dismiss_announcement
    get "unread", to: "unread#index"
    patch "unread/mark_all_read", to: "unread#mark_all_read", as: :unread_mark_all_read
    post "preview", to: "previews#create"
    post "uploads", to: "uploads#create"
    get "bookmarks", to: "bookmarks#index"
    patch "bookmarks/:id", to: "bookmarks#update", as: :bookmark
    get "preferences", to: "preferences#show"
    patch "preferences", to: "preferences#update"
    get "watching", to: "watched#index"
    get "watching/tags", to: "watched#tags", as: :watched_tags
    get "watching/tag-topics", to: "watched#tag_topics", as: :watched_tag_topics
    get "tags", to: "tags#index", as: :tags
    get "tags/:slug.rss", to: "rss#tag", as: :tag_rss, defaults: { format: :rss }
    get "sitemap.xml", to: "sitemaps#index", as: :sitemap, defaults: { format: :xml }
    resources :saved_searches, only: %i[index create destroy]
    get "tags/:slug", to: "tags#show", as: :tag
    post "tags/:slug/subscription", to: "tags#toggle_subscription", as: :tag_subscription
    resources :conversations, only: %i[index show new create] do
      member do
        post :archive
        post :unarchive
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
    get "sitemap.xml", to: "sitemaps#index", as: :sitemap, defaults: { format: :xml }
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
    delete "compare", to: "compare#clear"
    get "compare/share", to: "compare#share"
    get "compare/:token", to: "compare#public_show", as: :public_compare
    get "wishlist", to: "wishlist#index"
    post "wishlist/add_all_to_cart", to: "wishlist#add_all_to_cart", as: :add_all_to_cart_wishlist
    patch "wishlist/:product_id/note", to: "wishlist#update_note", as: :note_wishlist
    post "wishlist/:product_id/add_to_cart", to: "wishlist#add_to_cart", as: :add_wishlist_item_to_cart
    get "wishlist/share", to: "wishlist#share"
    get "wishlist/:token", to: "wishlist#public_show", as: :public_wishlist
    resources :stock_alerts, only: %i[index destroy] do
      member do
        post :add_to_cart
      end
    end
    resources :price_alerts, only: %i[index destroy]
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
    end
    get "coupons/:code", to: "coupons#show", as: :coupon
    post "coupons/:code/apply", to: "coupons#apply", as: :apply_coupon
    get "gift_cards/:code", to: "gift_cards#show", as: :gift_card
    post "gift_cards/:code/apply", to: "gift_cards#apply", as: :apply_gift_card
    post "webhooks/:provider", to: "webhooks#create", as: :webhook
    get "downloads/:token", to: "downloads#show", as: :download
    get "preferences", to: "preferences#show"
    patch "preferences", to: "preferences#update"
  end

  scope module: :website, as: :website do
    resources :articles, only: %i[index show], path: "blog"
    get "pages/:slug", to: "pages#show", as: :page
  end

  get "health/live", to: "health#live"
  get "health/ready", to: "health#ready"

  namespace :minecraft do
    resource :link, only: %i[show create], controller: "link"
    namespace :connector do
      scope ":server_id" do
        post "heartbeat", to: "api#heartbeat"
        get "tasks", to: "api#tasks"
        post "tasks/:id/complete", to: "api#complete"
      end
    end
  end
end
