<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type RoleDetail = {
  id: number
  name: string
  key: string
  description: string
  permissionIds: number[]
  memberCount: number
  systemRole: boolean
}

type Permission = {
  key: string
  name: string
  description: string | null
}

defineProps<{
  title: string
  subtitle?: string | null
  role: RoleDetail
  permissions: Permission[]
  editUrl?: string | null
  backUrl: string
}>()

const { t } = useI18n()

function visit(url: string) {
  router.visit(url)
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header
      :title="title"
      :subtitle="subtitle || undefined"
      show-back
      @back="visit(backUrl)"
    >
      <template v-if="editUrl" #extra>
        <a-button type="primary" @click="visit(editUrl)">
          {{ t('admin.roles.actions.edit') }}
        </a-button>
      </template>
    </a-page-header>

    <a-alert
      v-if="role.systemRole"
      type="warning"
      show-icon
      :closable="false"
      :title="t('admin.roles.show.systemNotice')"
    />
    <a-alert
      v-else-if="!editUrl"
      type="info"
      show-icon
      :closable="false"
      :title="t('admin.roles.show.readOnlyNotice')"
    />

    <a-card :title="t('admin.roles.show.details')" :bordered="true">
      <a-descriptions :column="{ xs: 1, md: 2 }" bordered table-layout="fixed">
        <a-descriptions-item :label="t('admin.roles.labels.name')">
          {{ role.name }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.roles.labels.key')">
          <a-typography-text code>{{ role.key }}</a-typography-text>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.roles.labels.type')">
          <a-tag :color="role.systemRole ? 'orange' : 'arcoblue'">
            {{ role.systemRole
              ? t('admin.roles.labels.systemRole')
              : t('admin.roles.labels.customRole') }}
          </a-tag>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.roles.labels.members')">
          {{ role.memberCount }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.roles.labels.description')" :span="2">
          {{ role.description || t('admin.roles.labels.noDescription') }}
        </a-descriptions-item>
      </a-descriptions>
    </a-card>

    <a-card :title="t('admin.roles.show.permissions')" :bordered="true">
      <a-empty
        v-if="permissions.length === 0"
        :description="t('admin.roles.show.emptyPermissions')"
      />
      <a-list v-else :bordered="true" :split="true">
        <a-list-item v-for="permission in permissions" :key="permission.key">
          <a-list-item-meta
            :title="permission.name"
            :description="permission.description || t('admin.roles.labels.noDescription')"
          />
          <template #actions>
            <a-tag bordered>{{ permission.key }}</a-tag>
          </template>
        </a-list-item>
      </a-list>
    </a-card>
  </a-space>
</template>
