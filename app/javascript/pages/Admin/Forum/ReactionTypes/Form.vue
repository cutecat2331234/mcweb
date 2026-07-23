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
  reactionType: { emoji: string; name: string; score: number; position: number; active: boolean }
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ reaction_type: { ...props.reactionType } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.reactionTypes.deleteTitle'),
    message: t('admin.reactionTypes.deleteConfirm'),
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
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="emoji">{{ t('admin.reactionTypes.emoji') }}</Label>
        <Input id="emoji" v-model="form.reaction_type.emoji" required maxlength="40" placeholder="👍" />
      </div>
      <div class="space-y-2">
        <Label for="name">{{ t('admin.reactionTypes.name') }}</Label>
        <Input id="name" v-model="form.reaction_type.name" required maxlength="40" placeholder="Like" />
      </div>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="score">{{ t('admin.reactionTypes.score') }}</Label>
        <Input id="score" v-model="form.reaction_type.score" type="number" />
      </div>
      <div class="space-y-2">
        <Label for="position">{{ t('admin.reactionTypes.position') }}</Label>
        <Input id="position" v-model="form.reaction_type.position" type="number" min="0" />
      </div>
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.reaction_type.active" />
      {{ t('admin.reactionTypes.active') }}
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
