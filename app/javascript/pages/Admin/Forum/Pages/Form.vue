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
  forum_page: { title: string; slug: string; body: string; show_in_nav: boolean; nav_label: string; position: number; published: boolean }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ forum_page: { ...props.forum_page } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.forumPagesForm.deleteTitle'),
    message: t('admin.forumPagesForm.deleteConfirm'),
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
      <Label for="title">{{ t('admin.forumPagesForm.title') }}</Label>
      <Input id="title" v-model="form.forum_page.title" required maxlength="200" />
    </div>
    <div class="space-y-2">
      <Label for="slug">{{ t('admin.forumPagesForm.slug') }}</Label>
      <Input id="slug" v-model="form.forum_page.slug" :placeholder="t('admin.forumPagesForm.slugHint')" />
    </div>
    <div class="space-y-2">
      <Label for="body">{{ t('admin.forumPagesForm.body') }}</Label>
      <Textarea id="body" v-model="form.forum_page.body" rows="10" />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.forum_page.show_in_nav" />
      {{ t('admin.forumPagesForm.showInNav') }}
    </label>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="nav_label">{{ t('admin.forumPagesForm.navLabel') }}</Label>
        <Input id="nav_label" v-model="form.forum_page.nav_label" />
      </div>
      <div class="space-y-2">
        <Label for="position">{{ t('admin.forumPagesForm.position') }}</Label>
        <Input id="position" v-model="form.forum_page.position" type="number" min="0" />
      </div>
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.forum_page.published" />
      {{ t('admin.forumPagesForm.published') }}
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
