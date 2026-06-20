<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  userField: {
    key: string
    label: string
    field_type: string
    description: string
    choices: string
    sort_order: number
    visibility: string
    required: boolean
    show_on_registration: boolean
    show_on_profile: boolean
    editable_by_user: boolean
    active: boolean
  }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const { t } = useI18n()
const form = useForm({ user_field: { ...props.userField } })

const fieldTypes = [
  { value: 'text', label: 'text' },
  { value: 'textarea', label: 'textarea' },
  { value: 'number', label: 'number' },
  { value: 'url', label: 'url' },
  { value: 'select', label: 'select' },
  { value: 'checkbox', label: 'checkbox' },
]

const visibilities = [
  { value: 'public', label: 'public' },
  { value: 'owner', label: 'owner' },
  { value: 'staff', label: 'staff' },
]

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}
</script>

<template>
  <PageHeader :title="title" />
  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="key">{{ t('adminMinecraft.colKey') }}</Label>
      <Input id="key" v-model="form.user_field.key" required pattern="[a-z][a-z0-9_]*" />
    </div>
    <div class="space-y-2">
      <Label for="label">{{ t('adminMinecraft.colLabel') }}</Label>
      <Input id="label" v-model="form.user_field.label" required />
    </div>
    <div class="space-y-2">
      <Label for="field_type">{{ t('adminMinecraft.colType') }}</Label>
      <Select id="field_type" v-model="form.user_field.field_type" :options="fieldTypes" />
    </div>
    <div class="space-y-2">
      <Label for="visibility">{{ t('adminMinecraft.colVisibility') }}</Label>
      <Select id="visibility" v-model="form.user_field.visibility" :options="visibilities" />
    </div>
    <div class="space-y-2">
      <Label for="description">{{ t('adminForum.fieldDescription') }}</Label>
      <Textarea id="description" v-model="form.user_field.description" rows="2" />
    </div>
    <div v-if="form.user_field.field_type === 'select'" class="space-y-2">
      <Label for="choices">{{ t('adminForum.fieldChoices') }}</Label>
      <Textarea id="choices" v-model="form.user_field.choices" rows="4" :placeholder="t('adminForum.fieldChoicesPlaceholder')" />
    </div>
    <div class="space-y-2">
      <Label for="sort_order">{{ t('adminMinecraft.sortOrder') }}</Label>
      <Input id="sort_order" v-model.number="form.user_field.sort_order" type="number" />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.user_field.required" />
      {{ t('adminForum.fieldRequired') }}
    </label>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.user_field.show_on_registration" />
      {{ t('adminForum.fieldShowOnRegistration') }}
    </label>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.user_field.show_on_profile" />
      {{ t('adminForum.fieldShowOnProfile') }}
    </label>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.user_field.editable_by_user" />
      {{ t('adminForum.fieldEditableByUser') }}
    </label>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.user_field.active" />
      {{ t('adminMinecraft.active') }}
    </label>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('common.save') }}</Button>
      <Button type="button" variant="outline" as-child>
        <a :href="backUrl">{{ t('common.cancel') }}</a>
      </Button>
    </div>
  </form>
</template>
