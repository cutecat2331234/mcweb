<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

type PermissionOption = {
  key: string
  name: string
  description?: string | null
  grantable: boolean
  delegable: boolean
}

type PermissionDomain = {
  key: string
  name: string
  permissions: PermissionOption[]
}

const props = defineProps<{
  title: string
  user_group: {
    name: string
    color_hex: string
    priority: number
    banner_text: string
    is_primary_default: boolean
    permissions: string[] | string
  }
  permissionCatalog: PermissionDomain[]
  grantablePermissionKeys: string[]
  members?: Array<{
    user_id: number
    username: string
    is_primary: boolean
    remove_url?: string | null
    set_primary_url?: string | null
  }>
  showMembers?: boolean
  canManageMembers?: boolean
  canManagePermissions?: boolean
  canAddMembers?: boolean
  memberPage?: number
  memberPageSize?: number
  memberTotal?: number
  memberPageUrl?: string | null
  addMemberUrl?: string | null
  submitUrl?: string | null
  method?: 'post' | 'patch'
  backUrl: string
  canManageGroup?: boolean
  deleteUrl?: string | null
  deleteBlocked?: 'members' | 'permissions' | 'members_and_permissions' | null
}>()

const initialPrimaryDefault = props.user_group.is_primary_default
const initialPermissions = Array.isArray(props.user_group.permissions)
  ? [ ...props.user_group.permissions ]
  : props.user_group.permissions.split(/\s+/).filter(Boolean)
const form = useForm({
  user_group: {
    ...props.user_group,
    permissions: initialPermissions,
  },
})
const newMember = ref('')
const selectedCount = computed(() => form.user_group.permissions.length)
const grantablePermissionKeySet = computed(() => new Set(props.grantablePermissionKeys))
const selectedPermissionsGrantable = computed(() =>
  form.user_group.permissions.every((key) => grantablePermissionKeySet.value.has(key)),
)
const primaryDefaultBlockedMessage = computed(() => {
  if (!props.canManageGroup) {
    return t('admin.userGroupsForm.groupReadOnly')
  }
  if (!props.canManageMembers) {
    return t('admin.userGroupsForm.primaryDefaultRequiresMemberManage')
  }
  if (!initialPrimaryDefault && !selectedPermissionsGrantable.value) {
    return t('admin.userGroupsForm.primaryDefaultRequiresGrantable')
  }
  return ''
})
const deleteBlockedMessage = computed(() => {
  if (!props.deleteBlocked) return ''
  return t(`admin.userGroupsForm.deleteBlocked.${props.deleteBlocked}`)
})

function fieldError(field: string) {
  return form.errors[`user_group.${field}`] || form.errors[field]
}

function addMember() {
  if (!props.canAddMembers || !props.addMemberUrl || !newMember.value.trim()) return
  router.post(props.addMemberUrl, { username: newMember.value.trim() }, {
    onSuccess: () => { newMember.value = '' },
    preserveScroll: true,
  })
}

async function removeMember(member: NonNullable<typeof props.members>[number]) {
  if (!props.canManageMembers || !member.remove_url) return

  const ok = await confirm({
    title: t('admin.userGroupsForm.removeMemberTitle'),
    message: t('admin.userGroupsForm.removeMemberConfirm', { name: member.username }),
    confirmLabel: t('admin.ui.remove'),
    variant: 'destructive',
  })
  if (!ok) return
  router.delete(member.remove_url, { preserveScroll: true })
}

function setPrimary(url: string | null | undefined) {
  if (!props.canManageMembers || !url) return
  router.post(url, {}, { preserveScroll: true })
}

function submit() {
  if (!props.canManageGroup || !props.submitUrl) return

  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

function changeMemberPage(page: number) {
  if (!props.memberPageUrl) return
  router.get(
    props.memberPageUrl,
    { member_page: page },
    {
      only: [ 'members', 'memberPage', 'memberTotal' ],
      preserveScroll: true,
      preserveState: true,
      replace: true,
    },
  )
}

function selectDomain(domain: PermissionDomain) {
  if (!props.canManagePermissions) return

  form.user_group.permissions = [
    ...new Set([
      ...form.user_group.permissions,
      ...domain.permissions
        .filter((permission) => permission.grantable)
        .map((permission) => permission.key),
    ]),
  ]
}

function clearDomain(domain: PermissionDomain) {
  if (!props.canManagePermissions) return

  const domainKeys = new Set(domain.permissions.map((permission) => permission.key))
  form.user_group.permissions = form.user_group.permissions.filter((key) => !domainKeys.has(key))
}

async function destroy() {
  if (props.deleteBlocked) return

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

  <a-form :model="form.user_group" layout="vertical" @submit="submit">
    <a-row :gutter="[20, 20]" align="start">
      <a-col :xs="24" :lg="showMembers ? 16 : 24">
        <a-card :bordered="true">
          <a-alert
            v-if="!canManageGroup"
            class="mb-4"
            type="info"
            show-icon
            :title="t('admin.userGroupsForm.groupReadOnly')"
          />
          <a-tabs default-active-key="details">
            <a-tab-pane key="details" :title="t('admin.userGroupsForm.detailsTab')">
              <a-row :gutter="[16, 0]">
                <a-col :xs="24" :sm="12">
                  <a-form-item
                    field="name"
                    :label="t('admin.userGroupsForm.name')"
                    :validate-status="fieldError('name') ? 'error' : undefined"
                    :help="fieldError('name')"
                  >
                    <a-input
                      v-model="form.user_group.name"
                      :input-attrs="{ required: true, maxlength: 100 }"
                      :disabled="!canManageGroup"
                      allow-clear
                    />
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :sm="12">
                  <a-form-item
                    field="priority"
                    :label="t('admin.userGroupsForm.priority')"
                    :extra="t('admin.userGroupsForm.priorityHint')"
                    :validate-status="fieldError('priority') ? 'error' : undefined"
                    :help="fieldError('priority')"
                  >
                    <a-input-number
                      v-model="form.user_group.priority"
                      class="w-full"
                      :disabled="!canManageGroup"
                    />
                  </a-form-item>
                </a-col>
              </a-row>

              <a-row :gutter="[16, 0]">
                <a-col :xs="24" :sm="12">
                  <a-form-item
                    field="color_hex"
                    :label="t('admin.userGroupsForm.color')"
                    :validate-status="fieldError('color_hex') ? 'error' : undefined"
                    :help="fieldError('color_hex')"
                  >
                    <a-input
                      v-model="form.user_group.color_hex"
                      placeholder="#6366f1"
                      :disabled="!canManageGroup"
                      allow-clear
                    />
                  </a-form-item>
                </a-col>
                <a-col :xs="24" :sm="12">
                  <a-form-item
                    field="banner_text"
                    :label="t('admin.userGroupsForm.banner')"
                    :validate-status="fieldError('banner_text') ? 'error' : undefined"
                    :help="fieldError('banner_text')"
                  >
                    <a-input
                      v-model="form.user_group.banner_text"
                      :disabled="!canManageGroup"
                      allow-clear
                    />
                  </a-form-item>
                </a-col>
              </a-row>

              <a-form-item
                field="is_primary_default"
                hide-label
                :extra="primaryDefaultBlockedMessage || undefined"
              >
                <a-checkbox
                  v-model="form.user_group.is_primary_default"
                  :disabled="Boolean(primaryDefaultBlockedMessage)"
                >
                  {{ t('admin.userGroupsForm.primaryDefault') }}
                </a-checkbox>
              </a-form-item>
            </a-tab-pane>

            <a-tab-pane key="permissions">
              <template #title>
                <a-space :size="6">
                  <span>{{ t('admin.userGroupsForm.permissionsTab') }}</span>
                  <a-badge :count="selectedCount" :max-count="99" />
                </a-space>
              </template>

              <a-alert
                class="mb-4"
                type="info"
                :title="t('admin.userGroupsForm.permissionScope')"
              >
                {{ t('admin.userGroupsForm.permissionScopeHint') }}
              </a-alert>
              <a-alert
                v-if="!canManagePermissions"
                class="mb-4"
                type="warning"
                :title="t('admin.userGroupsForm.permissionsReadOnly')"
              />

              <a-empty
                v-if="permissionCatalog.length === 0"
                :description="t('admin.userGroupsForm.noPermissions')"
              />
              <a-collapse v-else accordion>
                <a-collapse-item
                  v-for="domain in permissionCatalog"
                  :key="domain.key"
                  :header="domain.name"
                >
                  <template #extra>
                    <a-tag size="small">
                      {{ t('admin.userGroupsForm.permissionCount', { count: domain.permissions.length }) }}
                    </a-tag>
                  </template>

                  <a-space direction="vertical" fill :size="12">
                    <a-space wrap>
                      <a-button
                        size="mini"
                        type="outline"
                        :disabled="!canManagePermissions"
                        @click.stop="selectDomain(domain)"
                      >
                        {{ t('admin.userGroupsForm.selectDomain') }}
                      </a-button>
                      <a-button
                        size="mini"
                        type="text"
                        :disabled="!canManagePermissions"
                        @click.stop="clearDomain(domain)"
                      >
                        {{ t('admin.userGroupsForm.clearDomain') }}
                      </a-button>
                    </a-space>

                    <a-checkbox-group
                      v-model="form.user_group.permissions"
                      :disabled="!canManagePermissions"
                    >
                      <a-row :gutter="[12, 12]">
                        <a-col
                          v-for="permission in domain.permissions"
                          :key="permission.key"
                          :xs="24"
                          :md="12"
                        >
                          <a-card size="small" :bordered="true">
                            <a-checkbox
                              :value="permission.key"
                              :disabled="!canManagePermissions || !permission.delegable"
                            >
                              {{ permission.name }}
                            </a-checkbox>
                            <a-tag
                              v-if="!permission.grantable && permission.delegable"
                              class="ml-2"
                              size="small"
                              color="orange"
                            >
                              {{ t('admin.userGroupsForm.permissionRemovalOnly') }}
                            </a-tag>
                            <a-tag
                              v-else-if="!permission.delegable"
                              class="ml-2"
                              size="small"
                              color="gray"
                            >
                              {{ t('admin.userGroupsForm.permissionNotDelegable') }}
                            </a-tag>
                            <a-typography-paragraph
                              v-if="permission.description"
                              class="mb-0 mt-2"
                              type="secondary"
                            >
                              {{ permission.description }}
                            </a-typography-paragraph>
                            <a-typography-text code>
                              {{ permission.key }}
                            </a-typography-text>
                          </a-card>
                        </a-col>
                      </a-row>
                    </a-checkbox-group>
                  </a-space>
                </a-collapse-item>
              </a-collapse>
            </a-tab-pane>
          </a-tabs>

          <a-alert
            v-if="deleteBlockedMessage"
            class="mt-4"
            type="warning"
            :title="t('admin.userGroupsForm.deleteBlockedTitle')"
          >
            {{ deleteBlockedMessage }}
          </a-alert>

          <template #actions>
            <a-button
              v-if="canManageGroup"
              html-type="submit"
              type="primary"
              :loading="form.processing"
            >
              {{ t('admin.ui.save') }}
            </a-button>
            <Link :href="backUrl" class="arco-btn arco-btn-outline arco-btn-size-medium no-underline">
              {{ t('admin.ui.back') }}
            </Link>
            <a-button
              v-if="deleteUrl"
              type="text"
              status="danger"
              @click="destroy"
            >
              {{ t('admin.ui.delete') }}
            </a-button>
          </template>
        </a-card>
      </a-col>

      <a-col v-if="showMembers" :xs="24" :lg="8">
        <a-card :title="t('admin.userGroupsForm.members')" :bordered="true">
          <a-space direction="vertical" fill :size="16">
            <a-input
              v-if="canAddMembers"
              v-model="newMember"
              :placeholder="t('admin.userGroupsForm.addMemberPlaceholder')"
              @press-enter="addMember"
            />
            <a-button v-if="canAddMembers" type="outline" long @click="addMember">
              {{ t('admin.userGroupsForm.addMember') }}
            </a-button>
            <a-alert
              v-if="canManageMembers && !canAddMembers"
              type="warning"
              :title="t('admin.userGroupsForm.memberGrantBlocked')"
            />
            <a-list v-if="members?.length" :bordered="true" size="small">
              <a-list-item v-for="member in members" :key="member.user_id">
                <a-space direction="vertical" fill :size="8">
                  <a-space wrap>
                    <a-typography-text strong>
                      @{{ member.username }}
                    </a-typography-text>
                    <a-tag v-if="member.is_primary" color="arcoblue">
                      {{ t('admin.userGroupsForm.primary') }}
                    </a-tag>
                  </a-space>
                  <a-space wrap>
                    <a-button
                      v-if="canManageMembers && !member.is_primary && member.set_primary_url"
                      type="text"
                      size="small"
                      @click="setPrimary(member.set_primary_url)"
                    >
                      {{ t('admin.userGroupsForm.makePrimary') }}
                    </a-button>
                    <a-button
                      v-if="canManageMembers && member.remove_url"
                      type="text"
                      status="danger"
                      size="small"
                      @click="removeMember(member)"
                    >
                      {{ t('admin.ui.remove') }}
                    </a-button>
                  </a-space>
                </a-space>
              </a-list-item>
            </a-list>
            <a-empty v-else :description="t('admin.userGroupsForm.noMembers')" />
            <a-pagination
              v-if="(memberTotal || 0) > (memberPageSize || 20)"
              :current="memberPage || 1"
              :page-size="memberPageSize || 20"
              :total="memberTotal || 0"
              simple
              @change="changeMemberPage"
            />
            <a-alert
              v-if="!canManageMembers"
              type="info"
              :title="t('admin.userGroupsForm.membersReadOnly')"
            />
          </a-space>
        </a-card>
      </a-col>
    </a-row>
  </a-form>
</template>
