<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  subscription: { name: string; url: string; event: string; secret: string; active: boolean }
  events: string[]
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ webhook_subscription: { ...props.subscription } })

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.webhookSubscriptions.deleteTitle'),
    message: t('admin.webhookSubscriptions.deleteConfirm'),
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
      <Label for="name">{{ t('admin.webhookSubscriptions.name') }}</Label>
      <Input id="name" v-model="form.webhook_subscription.name" required maxlength="80" />
    </div>
    <div class="space-y-2">
      <Label for="url">{{ t('admin.webhookSubscriptions.url') }}</Label>
      <Input id="url" v-model="form.webhook_subscription.url" required placeholder="https://example.com/hook" />
    </div>
    <div class="space-y-2">
      <Label for="event">{{ t('admin.webhookSubscriptions.event') }}</Label>
      <select id="event" v-model="form.webhook_subscription.event" class="w-full rounded-md border px-3 py-2 text-sm">
        <option v-for="ev in events" :key="ev" :value="ev">{{ ev }}</option>
      </select>
    </div>
    <div class="space-y-2">
      <Label for="secret">{{ t('admin.webhookSubscriptions.secret') }}</Label>
      <Input id="secret" v-model="form.webhook_subscription.secret" :placeholder="t('admin.webhookSubscriptions.secretHint')" />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.webhook_subscription.active" />
      {{ t('admin.webhookSubscriptions.activeLabel') }}
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
