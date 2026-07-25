# frozen_string_literal: true

module Admin
  module Forum
    class TopicFieldsController < BaseController
      before_action -> { require_permission("forum.topics.lock") }
      before_action :set_definition, only: %i[edit update destroy]

      def index
        render inertia: "Admin/Generic/Index", props: {
          title: "主题自定义字段",
          columns: [
            admin_column(:key, t("mcweb.admin.minecraft.col_key"), link: true),
            admin_column(:label, t("mcweb.admin.minecraft.col_label")),
            admin_column(:field_type, t("mcweb.admin.minecraft.col_type")),
            admin_column(:display_location, "显示位置"),
            admin_column(:active, "启用")
          ],
          rows: Community::TopicFieldDefinition.ordered.map do |definition|
            admin_row(
              key: definition.key,
              label: definition.label,
              field_type: definition.field_type,
              display_location: definition.display_location,
              active: forum_yes_no(definition.active?),
              url: edit_admin_forum_topic_field_path(definition)
            )
          end,
          actions: [ { label: "新建主题字段", href: new_admin_forum_topic_field_path } ]
        }
      end

      def new
        definition = Community::TopicFieldDefinition.new(
          active: true,
          editable_by_user: true,
          field_type: "text",
          display_location: "before_message"
        )
        render inertia: "Admin/Forum/TopicFields/Form", props: form_props(definition)
      end

      def edit
        render inertia: "Admin/Forum/TopicFields/Form", props: form_props(@definition)
      end

      def create
        definition = Community::TopicFieldDefinition.new(definition_params)
        if definition.save
          redirect_to admin_forum_topic_fields_path, notice: t("mcweb.flash.field_created")
        else
          render inertia: "Admin/Forum/TopicFields/Form",
            props: form_props(definition),
            status: :unprocessable_entity
        end
      end

      def update
        if @definition.update(definition_params)
          redirect_to admin_forum_topic_fields_path, notice: t("mcweb.flash.field_updated")
        else
          render inertia: "Admin/Forum/TopicFields/Form",
            props: form_props(@definition),
            status: :unprocessable_entity
        end
      end

      def destroy
        @definition.destroy!
        redirect_to admin_forum_topic_fields_path, notice: t("mcweb.flash.field_deleted")
      end

      private

      def set_definition
        @definition = Community::TopicFieldDefinition.find(params[:id])
      end

      def definition_params
        permitted = params.require(:topic_field).permit(
          :key, :label, :field_type, :description, :choices, :sort_order,
          :display_location, :required, :editable_by_user, :active, :owner_plugin_id,
          section_ids: [], editable_group_ids: []
        ).to_h
        permitted.delete("key") if @definition&.persisted?
        permitted["section_ids"] = normalize_ids(params.dig(:topic_field, :section_ids))
        permitted["editable_group_ids"] = normalize_ids(params.dig(:topic_field, :editable_group_ids))
        permitted
      end

      def normalize_ids(value)
        Array(value)
          .flat_map { |item| item.to_s.split(/[\s,]+/) }
          .filter_map { |item| Integer(item, exception: false) }
          .select(&:positive?)
          .uniq
      end

      def form_props(definition)
        {
          title: definition.persisted? ? "编辑主题字段" : "新建主题字段",
          topicField: {
            id: definition.id,
            key: definition.key.to_s,
            label: definition.label.to_s,
            field_type: definition.field_type.to_s,
            description: definition.description.to_s,
            choices: definition.choices.to_s,
            sort_order: definition.sort_order || 0,
            display_location: definition.display_location.to_s,
            required: definition.required?,
            editable_by_user: definition.editable_by_user?,
            active: definition.active.nil? ? true : definition.active,
            section_ids: Array(definition.section_ids),
            editable_group_ids: Array(definition.editable_group_ids),
            owner_plugin_id: definition.owner_plugin_id.to_s
          },
          fieldTypes: Community::TopicFieldDefinition::FIELD_TYPES,
          displayLocations: Community::TopicFieldDefinition::DISPLAY_LOCATIONS,
          sections: Community::Section.order(:name).map { |section| { id: section.id, name: section.name } },
          userGroups: Community::UserGroup.ordered.map { |group| { id: group.id, name: group.name } },
          submitUrl: definition.persisted? ? admin_forum_topic_field_path(definition) : admin_forum_topic_fields_path,
          method: definition.persisted? ? "patch" : "post",
          backUrl: admin_forum_topic_fields_path,
          formErrors: definition.errors.to_hash(true).transform_values { |messages| Array(messages).join("；") }
        }
      end
    end
  end
end
