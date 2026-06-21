<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  theme: { name: string; key: string; active: boolean; tokens_json: string }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
  form_errors?: Record<string, string[]>
}>()

const form = useForm({ theme: { ...props.theme } })

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}
</script>

<template>
  <PageHeader :title="title" />
  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2"><Label>Name</Label><Input v-model="form.theme.name" required /></div>
    <div class="space-y-2"><Label>Key</Label><Input v-model="form.theme.key" required /></div>
    <div class="space-y-2"><Label>Tokens (JSON)</Label><Textarea v-model="form.theme.tokens_json" rows="10" class="font-mono text-sm" /></div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button as-child variant="outline"><Link :href="backUrl">{{ t('admin.ui.cancel') }}</Link></Button>
    </div>
  </form>
</template>
