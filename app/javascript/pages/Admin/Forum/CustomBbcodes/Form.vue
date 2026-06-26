<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  custom_bbcode: { tag: string; replacement: string; sample: string; active: boolean }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ custom_bbcode: { ...props.custom_bbcode } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.customBbcodes.deleteTitle'),
    message: t('admin.customBbcodes.deleteConfirm'),
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
    <div class="space-y-2">
      <Label for="tag">{{ t('admin.customBbcodes.tag') }}</Label>
      <Input id="tag" v-model="form.custom_bbcode.tag" required maxlength="20" placeholder="note" />
      <p class="text-xs text-muted-foreground">{{ t('admin.customBbcodes.tagHint') }}</p>
    </div>
    <div class="space-y-2">
      <Label for="replacement">{{ t('admin.customBbcodes.replacement') }}</Label>
      <Textarea id="replacement" v-model="form.custom_bbcode.replacement" rows="4" required :placeholder="'> 📌 {content}'" />
      <p class="text-xs text-muted-foreground">{{ t('admin.customBbcodes.replacementHint') }}</p>
    </div>
    <div class="space-y-2">
      <Label for="sample">{{ t('admin.customBbcodes.sample') }}</Label>
      <Input id="sample" v-model="form.custom_bbcode.sample" />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.custom_bbcode.active" />
      {{ t('admin.customBbcodes.active') }}
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
