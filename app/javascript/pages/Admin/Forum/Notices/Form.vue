<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  notice: {
    title: string
    message: string
    style: string
    audience: string
    active: boolean
    dismissible: boolean
    min_trust_level: number | null
    max_trust_level: number | null
    position: number
    starts_at: string | null
    ends_at: string | null
  }
  styleOptions: Array<{ value: string; label: string }>
  audienceOptions: Array<{ value: string; label: string }>
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ notice: { ...props.notice } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.notices.deleteTitle'),
    message: t('admin.notices.deleteConfirm'),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!props.deleteUrl || !ok) return
  form.delete(props.deleteUrl)
}
</script>

<template>
  <PageHeader :title="title" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="title">{{ t('admin.notices.titleLabel') }}</Label>
      <Input id="title" v-model="form.notice.title" required maxlength="120" />
    </div>
    <div class="space-y-2">
      <Label for="message">{{ t('admin.notices.message') }}</Label>
      <Textarea id="message" v-model="form.notice.message" rows="4" required />
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label>{{ t('admin.notices.style') }}</Label>
        <Select :model-value="form.notice.style" :options="styleOptions" @update:model-value="form.notice.style = $event" />
      </div>
      <div class="space-y-2">
        <Label>{{ t('admin.notices.audience') }}</Label>
        <Select :model-value="form.notice.audience" :options="audienceOptions" @update:model-value="form.notice.audience = $event" />
      </div>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="min_trust_level">{{ t('admin.notices.minTrust') }}</Label>
        <Input id="min_trust_level" v-model="form.notice.min_trust_level" type="number" min="0" max="4" />
      </div>
      <div class="space-y-2">
        <Label for="max_trust_level">{{ t('admin.notices.maxTrust') }}</Label>
        <Input id="max_trust_level" v-model="form.notice.max_trust_level" type="number" min="0" max="4" />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="position">{{ t('admin.notices.position') }}</Label>
      <Input id="position" v-model="form.notice.position" type="number" min="0" />
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="starts_at">{{ t('admin.notices.startsAt') }}</Label>
        <Input id="starts_at" v-model="form.notice.starts_at" type="datetime-local" />
      </div>
      <div class="space-y-2">
        <Label for="ends_at">{{ t('admin.notices.endsAt') }}</Label>
        <Input id="ends_at" v-model="form.notice.ends_at" type="datetime-local" />
      </div>
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.notice.active" />
      {{ t('admin.notices.active') }}
    </label>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.notice.dismissible" />
      {{ t('admin.notices.dismissible') }}
    </label>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button v-if="deleteUrl" type="button" variant="destructive" @click="destroy">{{ t('admin.ui.delete') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.back') }}</Link>
      </Button>
    </div>
  </form>
</template>
