<script setup lang="ts">
import { computed, ref } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Modal } from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  mappings: Array<{ game_group: string; role_key?: string | null; badge_slug?: string | null }>
  roles: Array<{ key: string; name: string }>
  badges: Array<{ slug: string; name: string }>
  createUrl: string
  backUrl: string
}>()

const { t } = useI18n()
const gameGroup = ref('')
const roleKey = ref('')
const badgeSlug = ref('')

const roleOptions = computed(() => [
  { value: '', label: '—' },
  ...props.roles.map((role) => ({ value: role.key, label: role.name })),
])
const badgeOptions = computed(() => [
  { value: '', label: '—' },
  ...props.badges.map((badge) => ({ value: badge.slug, label: badge.name })),
])
const columns = computed(() => [
  { title: t('adminMinecraft.gameGroup'), dataIndex: 'game_group' },
  { title: t('adminMinecraft.websiteRole'), dataIndex: 'role_key', slotName: 'role' },
  { title: t('adminMinecraft.badge'), dataIndex: 'badge_slug', slotName: 'badge' },
  { title: '', slotName: 'actions', width: 120 },
])

function addMapping() {
  if (!gameGroup.value.trim()) return
  router.post(props.createUrl, {
    game_group: gameGroup.value.trim(),
    role_key: roleKey.value || null,
    badge_slug: badgeSlug.value || null,
  })
}

function deleteMapping(index: number, gameGroupName: string) {
  Modal.warning({
    title: t('preferences.delete'),
    content: t('adminMinecraft.deleteMappingConfirm', `Delete mapping for ${gameGroupName}?`),
    okText: t('preferences.delete'),
    cancelText: t('common.cancel'),
    hideCancel: false,
    okButtonProps: { status: 'danger' },
    onOk: () => router.delete(`${props.createUrl}/${index}`),
  })
}
</script>

<template>
  <a-page-header :title="t('adminMinecraft.permissionMappings')" :show-back="false">
    <template #extra>
      <a-button @click="router.visit(backUrl)">{{ t('adminMinecraft.backToServers') }}</a-button>
    </template>
  </a-page-header>

  <a-card :title="t('adminMinecraft.addMapping')" :bordered="true" class="mb-4">
    <a-form layout="vertical" @submit="addMapping">
      <a-grid :cols="{ xs: 1, sm: 3 }" :col-gap="16">
        <a-grid-item>
          <a-form-item field="game_group" :label="t('adminMinecraft.gameGroup')" required>
            <a-input v-model="gameGroup" placeholder="vip" allow-clear />
          </a-form-item>
        </a-grid-item>
        <a-grid-item>
          <a-form-item field="role_key" :label="t('adminMinecraft.websiteRole')">
            <a-select v-model="roleKey" :options="roleOptions" allow-search />
          </a-form-item>
        </a-grid-item>
        <a-grid-item>
          <a-form-item field="badge_slug" :label="t('adminMinecraft.badge')">
            <a-select v-model="badgeSlug" :options="badgeOptions" allow-search />
          </a-form-item>
        </a-grid-item>
      </a-grid>
      <a-button html-type="submit" type="primary" :disabled="!gameGroup.trim()">
        {{ t('adminMinecraft.addMapping') }}
      </a-button>
    </a-form>
  </a-card>

  <a-card :bordered="true">
    <a-table
      :columns="columns"
      :data="mappings.map((mapping, index) => ({ ...mapping, index }))"
      row-key="index"
      :pagination="false"
      :scroll="{ x: 620 }"
    >
      <template #role="{ record }">{{ record.role_key || '—' }}</template>
      <template #badge="{ record }">{{ record.badge_slug || '—' }}</template>
      <template #actions="{ record }">
        <a-button
          type="text"
          status="danger"
          size="small"
          @click="deleteMapping(record.index, record.game_group)"
        >
          {{ t('preferences.delete') }}
        </a-button>
      </template>
      <template #empty>
        <a-empty :description="t('adminMinecraft.noMappings')" />
      </template>
    </a-table>
  </a-card>
</template>
