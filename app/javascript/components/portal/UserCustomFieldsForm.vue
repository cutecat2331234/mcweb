<script setup lang="ts">
import { computed } from 'vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

export type UserCustomField = {
  key: string
  label: string
  field_type: string
  description?: string | null
  choices?: string[]
  value?: string | null
  raw_value?: string
  required?: boolean
  editable?: boolean
}

const props = defineProps<{
  fields: UserCustomField[]
  modelValue: Record<string, string | boolean>
  errors?: Record<string, string>
  idPrefix?: string
}>()

const emit = defineEmits<{
  'update:modelValue': [value: Record<string, string | boolean>]
}>()

const editableFields = computed(() => props.fields.filter((field) => field.editable !== false))

const fieldId = (key: string) => `${props.idPrefix || 'ucf'}-${key}`

function updateField(key: string, value: string | boolean) {
  emit('update:modelValue', { ...props.modelValue, [key]: value })
}

function fieldError(key: string) {
  return props.errors?.[key] || props.errors?.[`user_fields.${key}`] || ''
}
</script>

<template>
  <div v-if="editableFields.length" class="space-y-4">
    <div v-for="field in editableFields" :key="field.key" class="space-y-2">
      <Label :for="fieldId(field.key)">
        {{ field.label }}
        <span v-if="field.required" class="text-destructive">*</span>
      </Label>
      <p v-if="field.description" class="text-xs text-muted-foreground">{{ field.description }}</p>

      <Textarea
        v-if="field.field_type === 'textarea'"
        :id="fieldId(field.key)"
        :model-value="String(modelValue[field.key] ?? field.raw_value ?? '')"
        rows="3"
        :required="field.required"
        @update:model-value="updateField(field.key, $event)"
      />
      <Select
        v-else-if="field.field_type === 'select'"
        :id="fieldId(field.key)"
        :model-value="String(modelValue[field.key] ?? field.raw_value ?? '')"
        :options="(field.choices || []).map((choice) => ({ value: choice, label: choice }))"
        :required="field.required"
        @update:model-value="updateField(field.key, $event)"
      />
      <label v-else-if="field.field_type === 'checkbox'" class="flex items-center gap-2 text-sm">
        <Checkbox
          :id="fieldId(field.key)"
          :model-value="Boolean(modelValue[field.key] ?? field.raw_value === '1')"
          @update:model-value="updateField(field.key, $event)"
        />
        {{ field.label }}
      </label>
      <Input
        v-else
        :id="fieldId(field.key)"
        :model-value="String(modelValue[field.key] ?? field.raw_value ?? '')"
        :type="field.field_type === 'number' ? 'number' : field.field_type === 'url' ? 'url' : 'text'"
        :required="field.required"
        @update:model-value="updateField(field.key, $event)"
      />
      <p v-if="fieldError(field.key)" class="text-sm text-destructive">{{ fieldError(field.key) }}</p>
    </div>
  </div>
</template>
