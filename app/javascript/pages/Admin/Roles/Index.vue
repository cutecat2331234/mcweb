<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type RoleSummary = {
  id: number
  name: string
  key: string
  description: string | null
  permissionCount: number
  memberCount: number
  systemRole: boolean
  url: string
}

type Pagination = {
  page: number
  pages: number
  count: number
  from: number
  to: number
  prev: number | null
  next: number | null
}

const props = defineProps<{
  title: string
  subtitle?: string | null
  canManage: boolean
  newUrl?: string | null
  roles: RoleSummary[]
  pagination: Pagination
}>()

const { t } = useI18n()

function visit(url: string) {
  router.visit(url)
}

function changePage(page: number) {
  router.get(
    window.location.pathname,
    { page },
    {
      preserveScroll: true,
      preserveState: true,
      replace: true,
    },
  )
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header
      :title="title"
      :subtitle="subtitle || undefined"
      :show-back="false"
    >
      <template v-if="canManage && newUrl" #extra>
        <a-button type="primary" @click="visit(newUrl)">
          {{ t('admin.roles.actions.new') }}
        </a-button>
      </template>
    </a-page-header>

    <a-alert
      v-if="!canManage"
      type="info"
      show-icon
      :closable="false"
      :title="t('admin.roles.index.readOnlyNotice')"
    />

    <a-empty
      v-if="roles.length === 0"
      :description="t('admin.roles.index.empty')"
    />

    <a-grid v-else :cols="24" :col-gap="16" :row-gap="16">
      <a-grid-item
        v-for="role in roles"
        :key="`role-card-${role.id}`"
        :span="{ xs: 24, sm: 12, md: 0 }"
      >
        <a-card :title="role.name" :bordered="true">
          <template #extra>
            <a-tag :color="role.systemRole ? 'orange' : 'arcoblue'">
              {{ role.systemRole
                ? t('admin.roles.labels.systemRole')
                : t('admin.roles.labels.customRole') }}
            </a-tag>
          </template>

          <a-space direction="vertical" :size="12" fill>
            <a-typography-paragraph type="secondary">
              {{ role.description || t('admin.roles.labels.noDescription') }}
            </a-typography-paragraph>

            <a-descriptions :column="1" bordered size="small" table-layout="fixed">
              <a-descriptions-item :label="t('admin.roles.labels.key')">
                <a-typography-text code>{{ role.key }}</a-typography-text>
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.roles.labels.members')">
                {{ role.memberCount }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.roles.labels.permissions')">
                {{ role.permissionCount }}
              </a-descriptions-item>
            </a-descriptions>

            <a-button long @click="visit(role.url)">
              {{ t('admin.roles.actions.view') }}
            </a-button>
          </a-space>
        </a-card>
      </a-grid-item>

      <a-grid-item :span="{ xs: 0, md: 24 }">
        <a-card :bordered="true">
          <a-table
            :data="roles"
            row-key="id"
            :pagination="false"
            :bordered="{ cell: true }"
            :scroll="{ minWidth: 920 }"
            stripe
          >
            <template #columns>
              <a-table-column :title="t('admin.roles.labels.name')" :width="220">
                <template #cell="{ record }">
                  <a-link :href="record.url" @click.prevent="visit(record.url)">
                    {{ record.name }}
                  </a-link>
                </template>
              </a-table-column>
              <a-table-column :title="t('admin.roles.labels.key')" :width="220">
                <template #cell="{ record }">
                  <a-typography-text code>{{ record.key }}</a-typography-text>
                </template>
              </a-table-column>
              <a-table-column :title="t('admin.roles.labels.type')" :width="140">
                <template #cell="{ record }">
                  <a-tag :color="record.systemRole ? 'orange' : 'arcoblue'">
                    {{ record.systemRole
                      ? t('admin.roles.labels.systemRole')
                      : t('admin.roles.labels.customRole') }}
                  </a-tag>
                </template>
              </a-table-column>
              <a-table-column
                :title="t('admin.roles.labels.members')"
                data-index="memberCount"
                :width="120"
              />
              <a-table-column
                :title="t('admin.roles.labels.permissions')"
                data-index="permissionCount"
                :width="130"
              />
              <a-table-column :title="t('admin.roles.labels.description')" :width="300">
                <template #cell="{ record }">
                  <a-typography-text type="secondary" :ellipsis="{ rows: 2 }">
                    {{ record.description || t('admin.roles.labels.noDescription') }}
                  </a-typography-text>
                </template>
              </a-table-column>
              <a-table-column
                :title="t('admin.roles.labels.actions')"
                :width="120"
                fixed="right"
              >
                <template #cell="{ record }">
                  <a-button size="small" @click="visit(record.url)">
                    {{ t('admin.roles.actions.view') }}
                  </a-button>
                </template>
              </a-table-column>
            </template>
          </a-table>
        </a-card>
      </a-grid-item>
    </a-grid>

    <a-card v-if="pagination.count > 0" :bordered="true">
      <a-space direction="vertical" :size="12" fill>
        <a-typography-text type="secondary">
          {{ t('admin.roles.index.range', {
            from: pagination.from,
            to: pagination.to,
            count: pagination.count,
          }) }}
        </a-typography-text>
        <a-pagination
          :current="pagination.page"
          :page-size="25"
          :total="pagination.count"
          :hide-on-single-page="true"
          show-total
          @change="changePage"
        />
      </a-space>
    </a-card>
  </a-space>
</template>
