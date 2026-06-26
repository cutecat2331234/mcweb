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
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  phrase: { locale: string; key: string; value: string }
  localeOptions: Array<{ value: string; label: string }>
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ phrase: { ...props.phrase } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.phrasesForm.deleteTitle'),
    message: t('admin.phrasesForm.deleteConfirm'),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!props.deleteUrl || !ok) return
  form.delete(props.deleteUrl)
}
</script>

<template>
  <PageHeader :title="title" />

  <form class="max-w-2xl space-y-4" @submit.prevent="submit">
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label>{{ t('admin.phrasesForm.locale') }}</Label>
        <Select :model-value="form.phrase.locale" :options="localeOptions" @update:model-value="form.phrase.locale = $event" />
      </div>
      <div class="space-y-2">
        <Label for="key">{{ t('admin.phrasesForm.key') }}</Label>
        <Input id="key" v-model="form.phrase.key" required placeholder="mcweb.flash.report_resolved" />
      </div>
    </div>
    <p class="text-xs text-muted-foreground">{{ t('admin.phrasesForm.keyHint') }}</p>
    <div class="space-y-2">
      <Label for="value">{{ t('admin.phrasesForm.value') }}</Label>
      <Textarea id="value" v-model="form.phrase.value" rows="3" required />
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
