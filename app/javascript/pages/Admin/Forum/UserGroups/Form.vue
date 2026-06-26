<script setup lang="ts">
import { ref } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
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
  user_group: {
    name: string
    color_hex: string
    priority: number
    banner_text: string
    is_primary_default: boolean
    permissions: string
  }
  availablePermissions: string[]
  members?: Array<{ user_id: number; username: string; is_primary: boolean; remove_url: string; set_primary_url: string }>
  addMemberUrl?: string | null
  submitUrl: string
  method?: 'post' | 'patch'
  backUrl: string
  deleteUrl?: string | null
}>()

const form = useForm({ user_group: { ...props.user_group } })
const newMember = ref('')

function addMember() {
  if (!props.addMemberUrl || !newMember.value.trim()) return
  router.post(props.addMemberUrl, { username: newMember.value.trim() }, {
    onSuccess: () => { newMember.value = '' },
    preserveScroll: true,
  })
}

function removeMember(url: string) {
  router.delete(url, { preserveScroll: true })
}

function setPrimary(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

function addPermission(key: string) {
  const lines = form.user_group.permissions.split(/\s+/).filter(Boolean)
  if (!lines.includes(key)) {
    form.user_group.permissions = [ ...lines, key ].join('\n')
  }
}

async function destroy() {
  const ok = await confirm({
    title: t('admin.userGroupsForm.deleteTitle'),
    message: t('admin.userGroupsForm.deleteConfirm'),
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
        <Label for="name">{{ t('admin.userGroupsForm.name') }}</Label>
        <Input id="name" v-model="form.user_group.name" required maxlength="100" />
      </div>
      <div class="space-y-2">
        <Label for="priority">{{ t('admin.userGroupsForm.priority') }}</Label>
        <Input id="priority" v-model="form.user_group.priority" type="number" />
        <p class="text-xs text-muted-foreground">{{ t('admin.userGroupsForm.priorityHint') }}</p>
      </div>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="color_hex">{{ t('admin.userGroupsForm.color') }}</Label>
        <Input id="color_hex" v-model="form.user_group.color_hex" placeholder="#6366f1" />
      </div>
      <div class="space-y-2">
        <Label for="banner_text">{{ t('admin.userGroupsForm.banner') }}</Label>
        <Input id="banner_text" v-model="form.user_group.banner_text" />
      </div>
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.user_group.is_primary_default" />
      {{ t('admin.userGroupsForm.primaryDefault') }}
    </label>
    <div class="space-y-2">
      <Label for="permissions">{{ t('admin.userGroupsForm.permissions') }}</Label>
      <Textarea id="permissions" v-model="form.user_group.permissions" rows="6" :placeholder="t('admin.userGroupsForm.permissionsHint')" />
      <div class="flex flex-wrap gap-1">
        <button
          v-for="key in availablePermissions"
          :key="key"
          type="button"
          class="rounded border px-1.5 py-0.5 text-[10px] text-muted-foreground hover:bg-muted"
          @click="addPermission(key)"
        >
          + {{ key }}
        </button>
      </div>
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button v-if="deleteUrl" type="button" variant="destructive" @click="destroy">{{ t('admin.ui.delete') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.back') }}</Link>
      </Button>
    </div>
  </form>

  <div v-if="addMemberUrl" class="mt-8 max-w-2xl space-y-3 border-t pt-6">
    <h2 class="text-sm font-semibold">{{ t('admin.userGroupsForm.members') }}</h2>
    <div class="flex gap-2">
      <Input v-model="newMember" :placeholder="t('admin.userGroupsForm.addMemberPlaceholder')" @keyup.enter="addMember" />
      <Button type="button" variant="outline" @click="addMember">{{ t('admin.userGroupsForm.addMember') }}</Button>
    </div>
    <ul v-if="members?.length" class="divide-y rounded-lg border">
      <li v-for="m in members" :key="m.user_id" class="flex items-center justify-between px-3 py-2 text-sm">
        <span>@{{ m.username }}<span v-if="m.is_primary" class="ml-2 text-xs text-muted-foreground">({{ t('admin.userGroupsForm.primary') }})</span></span>
        <div class="flex items-center gap-3">
          <button v-if="!m.is_primary" type="button" class="text-xs text-muted-foreground hover:underline" @click="setPrimary(m.set_primary_url)">{{ t('admin.userGroupsForm.makePrimary') }}</button>
          <button type="button" class="text-xs text-destructive hover:underline" @click="removeMember(m.remove_url)">{{ t('admin.ui.remove') }}</button>
        </div>
      </li>
    </ul>
    <p v-else class="text-sm text-muted-foreground">{{ t('admin.userGroupsForm.noMembers') }}</p>
  </div>
</template>
