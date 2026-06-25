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
  email_ban: { pattern: string; reason: string; expires_at: string | null }
  errors?: Record<string, string>
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ email_ban: { ...props.email_ban } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.emailBansForm.deleteTitle'),
    message: t('admin.emailBansForm.deleteConfirm'),
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
      <Label for="pattern">{{ t('admin.emailBansForm.pattern') }}</Label>
      <Input id="pattern" v-model="form.email_ban.pattern" required placeholder="*@spam.com" />
      <p class="text-xs text-muted-foreground">{{ t('admin.emailBansForm.patternHint') }}</p>
      <p v-if="errors?.pattern" class="text-xs text-destructive">{{ errors.pattern }}</p>
    </div>
    <div class="space-y-2">
      <Label for="reason">{{ t('admin.emailBansForm.reason') }}</Label>
      <Textarea id="reason" v-model="form.email_ban.reason" rows="2" />
    </div>
    <div class="space-y-2">
      <Label for="expires_at">{{ t('admin.emailBansForm.expiresAt') }}</Label>
      <Input id="expires_at" v-model="form.email_ban.expires_at" type="datetime-local" />
      <p class="text-xs text-muted-foreground">{{ t('admin.emailBansForm.expiresHint') }}</p>
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
