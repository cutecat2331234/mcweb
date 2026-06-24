<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  warning_template: { name: string; reason: string; points: number; expire_days: number | null }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ warning_template: { ...props.warning_template } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.warningTemplates.deleteTitle'),
    message: t('admin.warningTemplates.deleteConfirm'),
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
      <Label for="name">{{ t('admin.warningTemplates.name') }}</Label>
      <Input id="name" v-model="form.warning_template.name" required />
    </div>
    <div class="space-y-2">
      <Label for="reason">{{ t('admin.warningTemplates.reason') }}</Label>
      <Textarea id="reason" v-model="form.warning_template.reason" rows="4" />
    </div>
    <div class="space-y-2">
      <Label for="points">{{ t('admin.warningTemplates.points') }}</Label>
      <Input id="points" v-model="form.warning_template.points" type="number" min="0" max="10" />
    </div>
    <div class="space-y-2">
      <Label for="expire_days">{{ t('admin.warningTemplates.expireDays') }}</Label>
      <Input id="expire_days" v-model="form.warning_template.expire_days" type="number" min="0" />
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button v-if="deleteUrl" type="button" variant="destructive" @click="destroy">{{ t('admin.ui.delete') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.back') }}</Link>
      </Button>
    </div>
  </form>
</template>
