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
  help_article: { title: string; slug: string; category: string; body: string; position: number; published: boolean }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ help_article: { ...props.help_article } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.helpArticles.deleteTitle'),
    message: t('admin.helpArticles.deleteConfirm'),
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
      <Label for="title">{{ t('admin.helpArticles.titleLabel') }}</Label>
      <Input id="title" v-model="form.help_article.title" required maxlength="200" />
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="category">{{ t('admin.helpArticles.category') }}</Label>
        <Input id="category" v-model="form.help_article.category" />
      </div>
      <div class="space-y-2">
        <Label for="slug">{{ t('admin.helpArticles.slug') }}</Label>
        <Input id="slug" v-model="form.help_article.slug" :placeholder="t('admin.helpArticles.slugHint')" />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="body">{{ t('admin.helpArticles.body') }}</Label>
      <Textarea id="body" v-model="form.help_article.body" rows="10" />
    </div>
    <div class="space-y-2">
      <Label for="position">{{ t('admin.helpArticles.position') }}</Label>
      <Input id="position" v-model="form.help_article.position" type="number" min="0" />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.help_article.published" />
      {{ t('admin.helpArticles.published') }}
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
