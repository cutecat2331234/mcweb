# frozen_string_literal: true

module Website
  class BlockMutation < ApplicationService
    include LifecycleContract

    ACTION_EVENTS = {
      create: "block_create",
      update: "block_update",
      destroy: "block_delete",
      reorder: "block_reorder"
    }.freeze

    def initialize(page:, actor:, action:, block: nil, attributes: {}, block_ids: [], request_id: nil,
                   expected_lock_version: nil)
      @page = page
      @actor = actor
      @action = action.to_sym
      @block = block
      @attributes = attributes.to_h
      @block_ids = Array(block_ids).map { |id| Integer(id, exception: false) }
      @request_id = request_id.to_s.presence
      @expected_lock_version = Integer(expected_lock_version, exception: false)
    end

    def call
      raise LifecycleError, "website_block_action_invalid" unless ACTION_EVENTS.key?(@action)
      raise LifecycleError, "website_content_version_required" if @expected_lock_version.nil?
      normalize_idempotency_key!(@request_id)
      request_operation_digest = operation_digest(
        event: ACTION_EVENTS.fetch(@action),
        block_id: @block&.id,
        attributes: @attributes,
        block_ids: @block_ids
      )
      result = nil
      Website::Page.transaction do
        page = lock_content(@page)
        raise LifecycleError, "website_content_unavailable" unless page.active_content?
        event_type = ACTION_EVENTS.fetch(@action)
        if revision_replayed?(
          page, @request_id, event_type, operation_digest: request_operation_digest
        )
          result = ServiceResult.success(page: page, block: nil, replayed: true)
          next
        end
        assert_version!(page, @expected_lock_version)
        before = ContentSnapshot.call(content: page)
        RevisionRecorder.call(
          content: page,
          actor: @actor,
          event_type: event_type,
          request_id: @request_id,
          operation_digest: request_operation_digest
        )
        value = mutate!(page)
        page.touch
        audit!(
          actor: @actor,
          action: "website.page.#{event_type}",
          resource: page,
          request_id: @request_id,
          before_state: { blocks: before.fetch("blocks") },
          after_state: { blocks: ContentSnapshot.call(content: page).fetch("blocks") }
        )
        result = ServiceResult.success(page: page, block: value)
      end
      result
    rescue LifecycleError => error
      failure(error)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
      ServiceResult.failure(
        error: "website_block_mutation_failed",
        code: "website_block_mutation_failed",
        errors: error.respond_to?(:record) ? error.record.errors.to_hash : nil
      )
    end

    private

    def mutate!(page)
      case @action
      when :create
        page.blocks.create!(@attributes.merge(position: next_position(page)))
      when :update
        block = page.blocks.lock.find(@block.id)
        block.update!(@attributes)
        block
      when :destroy
        block = page.blocks.lock.find(@block.id)
        block.destroy!
        block
      when :reorder
        reorder!(page)
      end
    end

    def next_position(page)
      (page.blocks.unscope(:order).maximum(:position) || -1) + 1
    end

    def reorder!(page)
      current_ids = page.blocks.unscope(:order).lock.order(:position, :id).pluck(:id)
      if @block_ids.any?(&:nil?) || @block_ids.uniq != @block_ids || @block_ids.sort != current_ids.sort
        raise LifecycleError, "website_block_reorder_conflict"
      end

      @block_ids.each_with_index do |id, index|
        page.blocks.unscope(:order).where(id: id).update_all(position: index, updated_at: Time.current)
      end
      page.blocks.unscope(:order).order(:position, :id).to_a
    end
  end
end
