<script setup lang="ts">
import { computed, watch } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type TopicFieldDefinition = {
  id?: number
  key: string
  label: string
  field_type: string
  description: string
  choices: string
  display_location: string
  sort_order: number
  required: boolean
  editable_by_user: boolean
  active: boolean
  section_ids: number[]
  editable_group_ids: number[]
  owner_plugin_id?: string
}

const props = defineProps<{
  topicField: TopicFieldDefinition
  sections: Array<{ id: number; name: string; category?: string | null }>
  groups?: Array<{ id: number; name: string }>
  userGroups?: Array<{ id: number; name: string }>
  fieldTypes?: string[]
  displayLocations?: string[]
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
  formErrors?: Record<string, string>
}>()

const { t } = useI18n()
const form = useForm({
  topic_field: {
    ...props.topicField,
    section_ids: [ ...(props.topicField.section_ids || []) ],
    editable_group_ids: [ ...(props.topicField.editable_group_ids || []) ],
    owner_plugin_id: props.topicField.owner_plugin_id || '',
  },
})

const title = computed(() =>
  props.method === 'patch'
    ? t('adminForum.topicFields.editTitle')
    : t('adminForum.topicFields.newTitle'),
)

const fieldTypeLabels: Record<string, string> = {
  text: 'typeText',
  textarea: 'typeTextarea',
  number: 'typeNumber',
  url: 'typeUrl',
  select: 'typeSelect',
  checkbox: 'typeCheckbox',
}

const fieldTypes = computed(() =>
  (props.fieldTypes?.length ? props.fieldTypes : Object.keys(fieldTypeLabels)).map((value) => ({
    value,
    label: t(`adminForum.topicFields.${fieldTypeLabels[value] || value}`),
  })),
)

const displayLocationLabels: Record<string, string> = {
  topic_status: 'locationStatus',
  before_message: 'locationBeforeMessage',
  after_message: 'locationAfterMessage',
}

const displayLocations = computed(() =>
  (props.displayLocations?.length ? props.displayLocations : Object.keys(displayLocationLabels)).map((value) => ({
    value,
    label: t(`adminForum.topicFields.${displayLocationLabels[value] || value}`),
  })),
)

const availableGroups = computed(() => props.groups || props.userGroups || [])
const keyRules = computed(() => [
  { required: true },
  {
    match: /^[a-z][a-z0-9_]*$/,
    message: t('adminForum.topicFields.keyHint'),
  },
])
const requiredRules = [ { required: true } ]

watch(
  () => props.formErrors,
  (errors) => {
    form.clearErrors()
    if (!errors) return
    Object.entries(errors).forEach(([key, message]) => {
      form.setError(`topic_field.${key}` as keyof typeof form.errors, message)
    })
  },
  { immediate: true },
)

function fieldError(key: string) {
  return form.errors[`topic_field.${key}` as keyof typeof form.errors] || ''
}

function fieldStatus(key: string) {
  return fieldError(key) ? 'error' as const : undefined
}

function submit() {
  if (form.processing) return
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}

function cancel() {
  router.visit(props.backUrl)
}
</script>

<template>
  <div class="topic-fields-form">
    <a-page-header
      :title="title"
      :subtitle="t('adminForum.topicFields.subtitle')"
      :show-back="false"
      class="mb-4 !px-0"
    />

    <a-card class="max-w-4xl" :bordered="true">
      <a-alert v-if="form.hasErrors" type="error" show-icon class="mb-5">
        <a-space direction="vertical" fill :size="2">
          <span v-for="(message, key) in form.errors" :key="key">{{ message }}</span>
        </a-space>
      </a-alert>

      <a-form
        :model="form.topic_field"
        layout="vertical"
        :disabled="form.processing"
        scroll-to-first-error
        @submit-success="submit"
      >
        <a-row :gutter="[16, 0]">
          <a-col :xs="24" :sm="12">
            <a-form-item
              field="key"
              :label="t('adminForum.topicFields.key')"
              :rules="keyRules"
              :validate-status="fieldStatus('key')"
              :help="fieldError('key') || undefined"
            >
              <div class="w-full">
                <a-input
                  v-model="form.topic_field.key"
                  :disabled="Boolean(topicField.id) || form.processing"
                  :error="Boolean(fieldError('key'))"
                  :input-attrs="{ required: true, pattern: '[a-z][a-z0-9_]*' }"
                  allow-clear
                />
                <p class="mt-1 text-xs text-[var(--color-text-3)]">
                  {{ t('adminForum.topicFields.keyHint') }}
                </p>
              </div>
            </a-form-item>
          </a-col>

          <a-col :xs="24" :sm="12">
            <a-form-item
              field="label"
              :label="t('adminForum.topicFields.label')"
              :rules="requiredRules"
              :validate-status="fieldStatus('label')"
              :help="fieldError('label') || undefined"
            >
              <a-input
                v-model="form.topic_field.label"
                :error="Boolean(fieldError('label'))"
                :input-attrs="{ required: true }"
                allow-clear
              />
            </a-form-item>
          </a-col>
        </a-row>

        <a-form-item
          field="description"
          :label="t('adminForum.topicFields.description')"
          :validate-status="fieldStatus('description')"
          :help="fieldError('description') || undefined"
        >
          <a-textarea
            v-model="form.topic_field.description"
            :error="Boolean(fieldError('description'))"
            :auto-size="{ minRows: 3, maxRows: 7 }"
            allow-clear
          />
        </a-form-item>

        <a-row :gutter="[16, 0]">
          <a-col :xs="24" :sm="12">
            <a-form-item
              field="field_type"
              :label="t('adminForum.topicFields.fieldType')"
              :validate-status="fieldStatus('field_type')"
              :help="fieldError('field_type') || undefined"
            >
              <a-select
                v-model="form.topic_field.field_type"
                :options="fieldTypes"
                :error="Boolean(fieldError('field_type'))"
              />
            </a-form-item>
          </a-col>

          <a-col :xs="24" :sm="12">
            <a-form-item
              field="display_location"
              :label="t('adminForum.topicFields.displayLocation')"
              :validate-status="fieldStatus('display_location')"
              :help="fieldError('display_location') || undefined"
            >
              <a-select
                v-model="form.topic_field.display_location"
                :options="displayLocations"
                :error="Boolean(fieldError('display_location'))"
              />
            </a-form-item>
          </a-col>
        </a-row>

        <a-form-item
          v-if="form.topic_field.field_type === 'select'"
          field="choices"
          :label="t('adminForum.topicFields.choices')"
          :validate-status="fieldStatus('choices')"
          :help="fieldError('choices') || undefined"
        >
          <div class="w-full">
            <a-textarea
              v-model="form.topic_field.choices"
              :placeholder="t('adminForum.topicFields.choicesPlaceholder')"
              :error="Boolean(fieldError('choices'))"
              :auto-size="{ minRows: 5, maxRows: 10 }"
            />
            <p class="mt-1 text-xs text-[var(--color-text-3)]">
              {{ t('adminForum.topicFields.choicesHint') }}
            </p>
          </div>
        </a-form-item>

        <a-row :gutter="[16, 0]">
          <a-col :xs="24" :sm="12">
            <a-form-item
              field="sort_order"
              :label="t('adminForum.topicFields.sortOrder')"
              :validate-status="fieldStatus('sort_order')"
              :help="fieldError('sort_order') || undefined"
            >
              <a-input-number
                v-model="form.topic_field.sort_order"
                :min="0"
                :error="Boolean(fieldError('sort_order'))"
                class="w-full"
              />
            </a-form-item>
          </a-col>

          <a-col :xs="24" :sm="12">
            <a-form-item
              field="owner_plugin_id"
              :label="t('adminForum.topicFields.ownerPlugin')"
              :validate-status="fieldStatus('owner_plugin_id')"
              :help="fieldError('owner_plugin_id') || undefined"
            >
              <div class="w-full">
                <a-input
                  v-model="form.topic_field.owner_plugin_id"
                  :error="Boolean(fieldError('owner_plugin_id'))"
                  allow-clear
                />
                <p class="mt-1 text-xs text-[var(--color-text-3)]">
                  {{ t('adminForum.topicFields.ownerPluginHint') }}
                </p>
              </div>
            </a-form-item>
          </a-col>
        </a-row>

        <a-card class="mb-5" size="small" :bordered="true">
          <a-space wrap :size="[24, 12]">
            <a-checkbox v-model="form.topic_field.required">
              {{ t('adminForum.topicFields.required') }}
            </a-checkbox>
            <a-checkbox v-model="form.topic_field.editable_by_user">
              {{ t('adminForum.topicFields.editableByUser') }}
            </a-checkbox>
            <a-checkbox v-model="form.topic_field.active">
              {{ t('adminForum.topicFields.active') }}
            </a-checkbox>
          </a-space>
        </a-card>

        <a-row :gutter="[16, 16]" class="mb-5">
          <a-col :xs="24" :lg="12">
            <a-card
              :title="t('adminForum.topicFields.sections')"
              size="small"
              :bordered="true"
              class="h-full"
            >
              <p class="mb-3 text-xs text-[var(--color-text-3)]">
                {{ t('adminForum.topicFields.sectionsHint') }}
              </p>
              <a-checkbox-group
                v-model="form.topic_field.section_ids"
                class="topic-fields-form__choice-grid"
              >
                <a-checkbox
                  v-for="section in sections"
                  :key="section.id"
                  :value="section.id"
                >
                  <span class="break-words">
                    <span v-if="section.category" class="text-[var(--color-text-3)]">
                      {{ section.category }} /
                    </span>
                    {{ section.name }}
                  </span>
                </a-checkbox>
              </a-checkbox-group>
            </a-card>
          </a-col>

          <a-col :xs="24" :lg="12">
            <a-card
              :title="t('adminForum.topicFields.editableGroups')"
              size="small"
              :bordered="true"
              class="h-full"
            >
              <p class="mb-3 text-xs text-[var(--color-text-3)]">
                {{ t('adminForum.topicFields.editableGroupsHint') }}
              </p>
              <a-checkbox-group
                v-model="form.topic_field.editable_group_ids"
                class="topic-fields-form__choice-grid"
              >
                <a-checkbox
                  v-for="group in availableGroups"
                  :key="group.id"
                  :value="group.id"
                >
                  <span class="break-words">{{ group.name }}</span>
                </a-checkbox>
              </a-checkbox-group>
            </a-card>
          </a-col>
        </a-row>

        <a-space wrap :size="[8, 8]">
          <a-button
            html-type="submit"
            type="primary"
            :loading="form.processing"
          >
            {{ t('common.save') }}
          </a-button>
          <a-button
            html-type="button"
            type="outline"
            :disabled="form.processing"
            @click="cancel"
          >
            {{ t('common.cancel') }}
          </a-button>
        </a-space>
      </a-form>
    </a-card>
  </div>
</template>

<style scoped>
.topic-fields-form :deep(.arco-form-item-wrapper-col),
.topic-fields-form :deep(.arco-form-item-content-wrapper) {
  min-width: 0;
}

.topic-fields-form__choice-grid {
  display: grid;
  max-height: 14rem;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px 16px;
  overflow-y: auto;
  padding-right: 4px;
}

.topic-fields-form__choice-grid :deep(.arco-checkbox) {
  min-width: 0;
  align-items: flex-start;
  margin-right: 0;
}

@media (max-width: 639px) {
  .topic-fields-form__choice-grid {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>
