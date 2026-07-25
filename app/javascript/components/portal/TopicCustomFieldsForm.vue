<script setup lang="ts">
import { computed } from 'vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

export type TopicCustomFieldValue = string | number | boolean | string[]

export type TopicCustomField = {
  key: string
  label: string
  field_type: string
  description?: string | null
  choices?: string[]
  raw_value?: TopicCustomFieldValue | null
  value?: TopicCustomFieldValue | null
  display_value?: TopicCustomFieldValue | null
  required?: boolean
  editable?: boolean
  display_location?: string
}

const props = defineProps<{
  fields: TopicCustomField[]
  modelValue: Record<string, TopicCustomFieldValue>
  errors?: Partial<Record<string, string>>
  idPrefix?: string
}>()

const emit = defineEmits<{
  'update:modelValue': [value: Record<string, TopicCustomFieldValue>]
}>()

const editableFields = computed(() => props.fields.filter((field) => field.editable !== false))

const fieldId = (key: string) => `${props.idPrefix || 'topic-field'}-${key}`

function updateField(key: string, value: TopicCustomFieldValue) {
  emit('update:modelValue', { ...props.modelValue, [key]: value })
}

function stringValue(field: TopicCustomField) {
  const value = props.modelValue[field.key] ?? field.raw_value ?? ''
  return Array.isArray(value) ? value.join(', ') : String(value)
}

function checkboxValue(field: TopicCustomField) {
  const value = props.modelValue[field.key] ?? field.raw_value
  return value === true || value === 1 || value === '1' || value === 'true'
}

function fieldError(key: string) {
  return props.errors?.[key]
    || props.errors?.[`custom_fields.${key}`]
    || props.errors?.[`topic.custom_fields.${key}`]
    || props.errors?.[`draft.custom_fields.${key}`]
    || ''
}
</script>

<template>
  <div v-if="editableFields.length" class="space-y-4">
    <div v-for="field in editableFields" :key="field.key" class="space-y-2">
      <Label v-if="field.field_type !== 'checkbox'" :for="fieldId(field.key)">
        {{ field.label }}
        <span v-if="field.required" class="text-destructive">*</span>
      </Label>
      <p v-if="field.description" class="text-xs text-muted-foreground">{{ field.description }}</p>

      <Textarea
        v-if="field.field_type === 'textarea'"
        :id="fieldId(field.key)"
        :model-value="stringValue(field)"
        rows="4"
        :required="field.required"
        @update:model-value="updateField(field.key, $event)"
      />
      <Select
        v-else-if="field.field_type === 'select' || field.field_type === 'radio'"
        :id="fieldId(field.key)"
        :model-value="stringValue(field)"
        :options="(field.choices || []).map((choice) => ({ value: choice, label: choice }))"
        block
        @update:model-value="updateField(field.key, $event)"
      />
      <label v-else-if="field.field_type === 'checkbox'" class="flex items-center gap-2 text-sm">
        <Checkbox
          :id="fieldId(field.key)"
          :model-value="checkboxValue(field)"
          @update:model-value="updateField(field.key, $event)"
        />
        <span>
          {{ field.label }}
          <span v-if="field.required" class="text-destructive">*</span>
        </span>
      </label>
      <Input
        v-else
        :id="fieldId(field.key)"
        :model-value="stringValue(field)"
        :type="field.field_type === 'number' ? 'number' : field.field_type === 'url' ? 'url' : 'text'"
        :required="field.required"
        @update:model-value="updateField(field.key, $event)"
      />
      <p v-if="fieldError(field.key)" class="text-sm text-destructive">{{ fieldError(field.key) }}</p>
    </div>
  </div>
</template>
