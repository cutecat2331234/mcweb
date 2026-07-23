<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  submitUrl: string
  backUrl: string
}>()

const form = useForm({
  api_key: { name: '', scopes: ['read'] as string[], username: '' },
})

function toggleScope(scope: string, checked: boolean) {
  const set = new Set(form.api_key.scopes)
  if (checked) set.add(scope)
  else set.delete(scope)
  form.api_key.scopes = Array.from(set)
}

function submit() {
  form.post(props.submitUrl)
}
</script>

<template>
  <PageHeader :title="title" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="name">{{ t('admin.apiKeys.name') }}</Label>
      <Input id="name" v-model="form.api_key.name" required maxlength="80" />
    </div>

    <div class="space-y-2">
      <Label>{{ t('admin.apiKeys.scopes') }}</Label>
      <label class="flex items-center gap-2 text-sm">
        <Checkbox
          :model-value="form.api_key.scopes.includes('read')"
          @update:model-value="(v: boolean) => toggleScope('read', v)"
        />
        {{ t('admin.apiKeys.scopeRead') }}
      </label>
      <label class="flex items-center gap-2 text-sm">
        <Checkbox
          :model-value="form.api_key.scopes.includes('write')"
          @update:model-value="(v: boolean) => toggleScope('write', v)"
        />
        {{ t('admin.apiKeys.scopeWrite') }}
      </label>
    </div>

    <div class="space-y-2">
      <Label for="username">{{ t('admin.apiKeys.actAsUser') }}</Label>
      <Input id="username" v-model="form.api_key.username" :placeholder="t('admin.apiKeys.actAsUserHint')" />
    </div>

    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.apiKeys.create') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.back') }}</Link>
      </Button>
    </div>
  </form>
</template>
