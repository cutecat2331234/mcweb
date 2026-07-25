<script setup lang="ts">
import { ref } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

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

async function removeMember(member: NonNullable<typeof props.members>[number]) {
  const ok = await confirm({
    title: t('admin.userGroupsForm.removeMemberTitle'),
    message: t('admin.userGroupsForm.removeMemberConfirm', { name: member.username }),
    confirmLabel: t('admin.ui.remove'),
    variant: 'destructive',
  })
  if (!ok) return
  router.delete(member.remove_url, { preserveScroll: true })
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
  <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />

  <a-card class="max-w-3xl" :bordered="true">
    <form class="space-y-4" @submit.prevent="submit">
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.userGroupsForm.name') }}</span>
            <a-input
              v-model="form.user_group.name"
              :input-attrs="{ required: true, maxlength: 100 }"
              allow-clear
            />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.userGroupsForm.priority') }}</span>
            <a-input-number v-model="form.user_group.priority" class="w-full" />
            <small>{{ t('admin.userGroupsForm.priorityHint') }}</small>
          </label>
        </a-col>
      </a-row>

      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.userGroupsForm.color') }}</span>
            <a-input v-model="form.user_group.color_hex" placeholder="#6366f1" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.userGroupsForm.banner') }}</span>
            <a-input v-model="form.user_group.banner_text" allow-clear />
          </label>
        </a-col>
      </a-row>

      <a-checkbox v-model="form.user_group.is_primary_default">
        {{ t('admin.userGroupsForm.primaryDefault') }}
      </a-checkbox>

      <label class="admin-forum-field">
        <span>{{ t('admin.userGroupsForm.permissions') }}</span>
        <a-textarea
          v-model="form.user_group.permissions"
          :auto-size="{ minRows: 6, maxRows: 12 }"
          :placeholder="t('admin.userGroupsForm.permissionsHint')"
        />
      </label>
      <a-space wrap :size="[4, 4]">
        <a-button
          v-for="key in availablePermissions"
          :key="key"
          size="mini"
          type="outline"
          @click="addPermission(key)"
        >
          + {{ key }}
        </a-button>
      </a-space>

      <a-space wrap>
        <a-button html-type="submit" type="primary" :loading="form.processing">
          {{ t('admin.ui.save') }}
        </a-button>
        <a-button v-if="deleteUrl" type="primary" status="danger" @click="destroy">
          {{ t('admin.ui.delete') }}
        </a-button>
        <Link :href="backUrl" class="arco-btn arco-btn-outline arco-btn-size-medium no-underline">
          {{ t('admin.ui.back') }}
        </Link>
      </a-space>
    </form>
  </a-card>

  <a-card
    v-if="addMemberUrl"
    class="mt-6 max-w-3xl"
    :title="t('admin.userGroupsForm.members')"
    :bordered="true"
  >
    <a-space class="mb-4 w-full" fill>
      <a-input
        v-model="newMember"
        :placeholder="t('admin.userGroupsForm.addMemberPlaceholder')"
        @press-enter="addMember"
      />
      <a-button type="outline" @click="addMember">
        {{ t('admin.userGroupsForm.addMember') }}
      </a-button>
    </a-space>
    <a-list v-if="members?.length" :bordered="true">
      <a-list-item v-for="member in members" :key="member.user_id">
        <div class="flex w-full flex-wrap items-center justify-between gap-3">
          <span>
            @{{ member.username }}
            <a-tag v-if="member.is_primary" class="ml-2" color="arcoblue">
              {{ t('admin.userGroupsForm.primary') }}
            </a-tag>
          </span>
          <a-space wrap>
            <a-button
              v-if="!member.is_primary"
              type="text"
              size="small"
              @click="setPrimary(member.set_primary_url)"
            >
              {{ t('admin.userGroupsForm.makePrimary') }}
            </a-button>
            <a-button
              type="text"
              status="danger"
              size="small"
              @click="removeMember(member)"
            >
              {{ t('admin.ui.remove') }}
            </a-button>
          </a-space>
        </div>
      </a-list-item>
    </a-list>
    <a-empty v-else :description="t('admin.userGroupsForm.noMembers')" />
  </a-card>
</template>

<style scoped>
.admin-forum-field {
  display: grid;
  gap: 6px;
  margin-bottom: 16px;
  color: var(--color-text-2);
  font-size: 14px;
}

.admin-forum-field small {
  color: var(--color-text-3);
}
</style>
