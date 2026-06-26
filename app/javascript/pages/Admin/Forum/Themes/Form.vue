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
  forum_theme: { name: string; primary_color: string; accent_color: string; is_default: boolean; active: boolean }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ forum_theme: { ...props.forum_theme } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.forumThemesForm.deleteTitle'),
    message: t('admin.forumThemesForm.deleteConfirm'),
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
      <Label for="name">{{ t('admin.forumThemesForm.name') }}</Label>
      <Input id="name" v-model="form.forum_theme.name" required maxlength="100" />
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="primary_color">{{ t('admin.forumThemesForm.primaryColor') }}</Label>
        <Input id="primary_color" v-model="form.forum_theme.primary_color" placeholder="#6366f1" />
      </div>
      <div class="space-y-2">
        <Label for="accent_color">{{ t('admin.forumThemesForm.accentColor') }}</Label>
        <Input id="accent_color" v-model="form.forum_theme.accent_color" placeholder="#a5b4fc" />
      </div>
    </div>
    <p class="text-xs text-muted-foreground">{{ t('admin.forumThemesForm.colorHint') }}</p>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.forum_theme.is_default" />
      {{ t('admin.forumThemesForm.isDefault') }}
    </label>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.forum_theme.active" />
      {{ t('admin.forumThemesForm.active') }}
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
