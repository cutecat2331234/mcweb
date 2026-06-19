<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  profileField: {
    key: string
    label: string
    field_type: string
    icon: string
    sort_order: number
    visibility: string
    source: string
    group_name: string
    active: boolean
  }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const { t } = useI18n()
const form = useForm({ profile_field: { ...props.profileField } })

const fieldTypes = [
  { value: 'text', label: 'text' },
  { value: 'number', label: 'number' },
  { value: 'url', label: 'url' },
  { value: 'markdown', label: 'markdown' },
  { value: 'badge', label: 'badge' },
  { value: 'link', label: 'link' },
  { value: 'json', label: 'json' },
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
      <Input id="key" v-model="form.profile_field.key" required />
    </div>
    <div class="space-y-2">
      <Label for="label">{{ t('adminMinecraft.colLabel') }}</Label>
      <Input id="label" v-model="form.profile_field.label" required />
    </div>
    <div class="space-y-2">
      <Label for="field_type">{{ t('adminMinecraft.colType') }}</Label>
      <Select id="field_type" v-model="form.profile_field.field_type" :options="fieldTypes" />
    </div>
    <div class="space-y-2">
      <Label for="visibility">{{ t('adminMinecraft.colVisibility') }}</Label>
      <Select id="visibility" v-model="form.profile_field.visibility" :options="visibilities" />
    </div>
    <div class="space-y-2">
      <Label for="source">{{ t('adminMinecraft.colSource') }}</Label>
      <Input id="source" v-model="form.profile_field.source" placeholder="bridge:papi:player_level" />
    </div>
    <div class="space-y-2">
      <Label for="group_name">{{ t('adminMinecraft.groupName') }}</Label>
      <Input id="group_name" v-model="form.profile_field.group_name" />
    </div>
    <div class="space-y-2">
      <Label for="sort_order">{{ t('adminMinecraft.sortOrder') }}</Label>
      <Input id="sort_order" v-model.number="form.profile_field.sort_order" type="number" />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.profile_field.active" />
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
