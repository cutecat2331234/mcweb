<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  user_title: { min_posts: number; title: string }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ user_title: { ...props.user_title } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.userTitles.deleteTitle'),
    message: t('admin.userTitles.deleteConfirm'),
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
      <Label for="title">{{ t('admin.userTitles.title') }}</Label>
      <Input id="title" v-model="form.user_title.title" required maxlength="100" />
    </div>
    <div class="space-y-2">
      <Label for="min_posts">{{ t('admin.userTitles.minPosts') }}</Label>
      <Input id="min_posts" v-model="form.user_title.min_posts" type="number" min="0" required />
      <p class="text-xs text-muted-foreground">{{ t('admin.userTitles.minPostsHint') }}</p>
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
