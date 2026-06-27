<script setup lang="ts">
import { useForm, Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  save_url: string
  back_url: string
}>()

const form = useForm<{ username: string; amount: number | string; note: string }>({
  username: '',
  amount: '',
  note: '',
})

function submit() {
  form.post(props.save_url, { preserveScroll: true })
}
</script>

<template>
  <div class="mb-4 flex items-center justify-between">
    <PageHeader :title="t('admin.forum.points.adjustTitle')" :subtitle="t('admin.forum.points.adjustSubtitle')" />
    <Link :href="back_url" class="rounded-md border px-3 py-1.5 text-sm no-underline hover:bg-muted">
      {{ t('admin.forum.points.backToLog') }}
    </Link>
  </div>

  <form class="max-w-xl space-y-5" @submit.prevent="submit">
    <div class="space-y-1.5">
      <Label for="username">{{ t('admin.forum.points.fieldUser') }}</Label>
      <Input id="username" v-model="form.username" type="text" :placeholder="t('admin.forum.points.fieldUserHint')" />
      <p v-if="form.errors.username" class="text-xs text-destructive">{{ form.errors.username }}</p>
    </div>

    <div class="space-y-1.5">
      <Label for="amount">{{ t('admin.forum.points.fieldAmount') }}</Label>
      <Input id="amount" v-model="form.amount" type="number" step="1" class="w-40" :placeholder="t('admin.forum.points.fieldAmountHint')" />
      <p class="text-xs text-muted-foreground">{{ t('admin.forum.points.fieldAmountNote') }}</p>
    </div>

    <div class="space-y-1.5">
      <Label for="note">{{ t('admin.forum.points.fieldNote') }}</Label>
      <Input id="note" v-model="form.note" type="text" :placeholder="t('admin.forum.points.fieldNoteHint')" />
    </div>

    <div class="flex items-center gap-3 pt-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.forum.points.applyAdjustment') }}</Button>
    </div>
  </form>
</template>
