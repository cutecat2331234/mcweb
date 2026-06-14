# frozen_string_literal: true

module InertiaSerializable
  extend ActiveSupport::Concern

  private

  def pagy_props(pagy)
    {
      page: pagy.page,
      pages: pagy.pages,
      count: pagy.count,
      from: pagy.from,
      to: pagy.to,
      prev: pagy.prev,
      next: pagy.next
    }
  end

  def inertia_user
    return nil unless current_user

    {
      id: current_user.public_id,
      username: current_user.username,
      email: current_user.email
    }
  end

  def admin_column(key, label, link: false)
    { key: key.to_s, label: label, link: link }
  end

  def admin_row(**attrs)
    attrs.transform_values { |v| v.nil? ? "—" : v.to_s }
  end

  def serialize_section(section)
    {
      id: section.id,
      name: section.name,
      slug: section.slug,
      description: section.description&.truncate(80),
      category_name: section.category&.name,
      url: forum_section_path(section)
    }
  end

  def serialize_topic(topic)
    {
      id: topic.public_id,
      title: topic.title,
      url: forum_topic_path(topic),
      author: topic.user&.username,
      replies_count: topic.replies_count,
      last_posted_at: topic.last_posted_at ? l(topic.last_posted_at, format: :short) : nil,
      pinned: topic.pinned?,
      locked: topic.locked?
    }
  end

  def serialize_topic_detail(topic)
    {
      id: topic.public_id,
      title: topic.title,
      author: topic.user&.username,
      locked: topic.locked?,
      section: {
        name: topic.section.name,
        slug: topic.section.slug,
        url: forum_section_path(topic.section)
      }
    }
  end

  def serialize_post(post)
    {
      id: post.id,
      floor_number: post.floor_number,
      author: post.user.username,
      body: post.body,
      created_at: l(post.created_at, format: :short)
    }
  end

  def serialize_search_topic(topic)
    {
      id: topic.public_id,
      title: topic.title,
      url: forum_topic_path(topic),
      last_posted_at: topic.last_posted_at ? l(topic.last_posted_at, format: :short) : nil
    }
  end

  def serialize_search_post(post)
    {
      id: post.id,
      body: post.body.truncate(120),
      author: post.user.username,
      topic_title: post.topic.title,
      topic_url: forum_topic_path(post.topic),
      created_at: l(post.created_at, format: :short)
    }
  end

  def serialize_product_list_item(product)
    {
      id: product.public_id,
      name: product.name,
      slug: product.slug,
      category_name: product.category&.name,
      price_label: format_price(product),
      in_stock: product.in_stock?,
      url: store_product_path(product)
    }
  end

  def serialize_product_detail(product)
    {
      id: product.public_id,
      db_id: product.id,
      name: product.name,
      slug: product.slug,
      description: product.description,
      price_label: format_price(product),
      product_type: product.product_type,
      category_name: product.category&.name,
      in_stock: product.in_stock?
    }
  end

  def serialize_cart_item(item)
    unit = item.product.currency == "CNY" ? "¥" : "$"
    unit_cents = item.variant&.price_cents || item.product.price_cents
    {
      id: item.id,
      product_name: item.product.name,
      variant_name: item.variant&.name,
      quantity: item.quantity,
      unit_price_label: number_to_currency(unit_cents / 100.0, unit: unit),
      total_label: number_to_currency(item.total_cents / 100.0, unit: unit),
      update_url: store_cart_path
    }
  end

  def serialize_order_list_item(order)
    {
      id: order.public_id,
      order_number: order.order_number,
      status: order.status,
      total_label: format_money(order.total_cents, order.currency),
      created_at: l(order.created_at, format: :short),
      url: store_order_path(order)
    }
  end

  def serialize_order_detail(order)
    {
      id: order.public_id,
      order_number: order.order_number,
      status: order.status,
      total_label: format_money(order.total_cents, order.currency),
      can_pay: order.pending? || order.awaiting_payment?,
      items: order.items.map do |item|
        {
          product_name: item.product_name,
          variant_name: item.variant_name,
          quantity: item.quantity,
          total_label: format_money(item.total_cents, order.currency)
        }
      end
    }
  end

  def serialize_article(article)
    {
      id: article.public_id,
      title: article.title,
      slug: article.slug,
      excerpt: article.summary,
      article_type: article.article_type,
      published_at: article.published_at ? l(article.published_at, format: :short) : nil,
      url: "/website/blog/#{article.slug}"
    }
  end

  def serialize_article_detail(article)
    {
      title: article.title,
      summary: article.summary,
      published_at: article.published_at ? l(article.published_at, format: :long) : nil
    }
  end

  def serialize_page_block(block)
    {
      block_type: block.block_type,
      settings: block.settings
    }
  end

  def serialize_session_record(session)
    {
      id: session.id,
      ip_address: session.ip_address,
      user_agent: session.user_agent&.truncate(80),
      last_active_at: session.last_active_at ? l(session.last_active_at, format: :short) : nil,
      current: session.id == current_session&.id
    }
  end

  def serialize_checkout_provider(config)
    { value: config.provider, label: config.provider.humanize }
  end

  def format_price(product)
    format_money(product.price_cents, product.currency)
  end

  def format_money(cents, currency)
    unit = currency == "CNY" ? "¥" : "$"
    number_to_currency(cents / 100.0, unit: unit)
  end

  def number_to_currency(amount, unit:)
    ActionController::Base.helpers.number_to_currency(amount, unit: unit)
  end
end
