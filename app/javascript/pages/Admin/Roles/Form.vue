<script setup lang="ts">
import { computed, ref } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type RoleFormData = {
  id: number | null
  name: string
  key: string
  description: string
  permissionIds: number[]
  memberCount: number
  systemRole: boolean
}

type PermissionOption = {
  id: number
  key: string
  name: string
  description: string | null
  grantable: boolean
  selected: boolean
}

type PermissionDomain = {
  key: string
  name: string
  permissions: PermissionOption[]
}

type ReplacementRole = {
  id: number
  name: string
  key: string
}

const props = defineProps<{
  title: string
  role: RoleFormData
  permissionCatalog: PermissionDomain[]
  replacementRoles: ReplacementRole[]
  canManage: boolean
  submitUrl: string
  method: 'post' | 'patch'
  deleteUrl?: string | null
  backUrl: string
  formErrors: Record<string, string>
}>()

const { t } = useI18n()
const retirementVisible = ref(false)

const form = useForm({
  role: {
    name: props.role.name,
    key: props.role.key,
    description: props.role.description,
    permission_ids: [...props.role.permissionIds],
  },
})

const retirementForm = useForm({
  role: {
    replacement_role_id: null as number | null,
  },
})

const selectedPermissionCount = computed(() => form.role.permission_ids.length)
const requiresReplacement = computed(() => props.role.memberCount > 0)
const retirementBlocked = computed(() =>
  requiresReplacement.value && retirementForm.role.replacement_role_id == null,
)
const defaultPermissionGroups = computed(() =>
  props.permissionCatalog.length > 0 ? [props.permissionCatalog[0].key] : [],
)

function fieldError(field: 'name' | 'key' | 'description') {
  const clientErrors = form.errors as Record<string, string>
  return clientErrors[`role.${field}`]
    || clientErrors[field]
    || props.formErrors[`role.${field}`]
    || props.formErrors[field]
}

function permissionSelected(permission: PermissionOption) {
  return form.role.permission_ids.includes(permission.id)
}

function togglePermission(permission: PermissionOption, checked: boolean) {
  if (
    !props.canManage
    || (!permission.grantable && !permissionSelected(permission))
  ) return

  const selected = new Set(form.role.permission_ids)
  if (checked) selected.add(permission.id)
  else selected.delete(permission.id)
  form.role.permission_ids = Array.from(selected)
}

function submit(event?: { errors?: unknown }) {
  if (!props.canManage || event?.errors) return

  if (props.method === 'patch') {
    form.patch(props.submitUrl, { preserveScroll: true })
  } else {
    form.post(props.submitUrl, { preserveScroll: true })
  }
}

function visitBack() {
  router.visit(props.backUrl)
}

function openRetirement() {
  retirementForm.clearErrors()
  retirementVisible.value = true
}

function closeRetirement() {
  if (retirementForm.processing) return
  retirementVisible.value = false
  retirementForm.reset()
}

function retireRole() {
  if (!props.deleteUrl || retirementBlocked.value) return

  retirementForm.delete(props.deleteUrl, {
    preserveScroll: true,
    onSuccess: () => {
      retirementVisible.value = false
    },
  })
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header :title="title" show-back @back="visitBack" />

    <a-alert
      v-if="role.systemRole"
      type="warning"
      show-icon
      :closable="false"
      :title="t('admin.roles.form.systemNotice')"
    />
    <a-alert
      v-else-if="!canManage"
      type="info"
      show-icon
      :closable="false"
      :title="t('admin.roles.form.readOnlyNotice')"
    />
    <a-alert
      v-if="formErrors.base"
      type="error"
      show-icon
      :closable="false"
      :title="formErrors.base"
    />

    <a-form :model="form.role" layout="vertical" @submit="submit">
      <a-space direction="vertical" :size="16" fill>
        <a-card :title="t('admin.roles.form.details')" :bordered="true">
          <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16" :row-gap="0">
            <a-grid-item>
              <a-form-item
                field="name"
                :label="t('admin.roles.labels.name')"
                :rules="[{ required: true, message: t('admin.roles.form.nameRequired') }]"
                :validate-status="fieldError('name') ? 'error' : undefined"
                :help="fieldError('name')"
              >
                <a-input
                  v-model="form.role.name"
                  :disabled="!canManage"
                  :max-length="100"
                  :placeholder="t('admin.roles.form.namePlaceholder')"
                  show-word-limit
                  allow-clear
                />
              </a-form-item>
            </a-grid-item>

            <a-grid-item>
              <a-form-item
                field="key"
                :label="t('admin.roles.labels.key')"
                :rules="[{ required: true, message: t('admin.roles.form.keyRequired') }]"
                :validate-status="fieldError('key') ? 'error' : undefined"
                :help="fieldError('key')"
                :extra="role.id
                  ? t('admin.roles.form.keyLockedHint')
                  : t('admin.roles.form.keyHint')"
              >
                <a-input
                  v-model="form.role.key"
                  :disabled="!canManage || role.id !== null"
                  :max-length="100"
                  :placeholder="t('admin.roles.form.keyPlaceholder')"
                  allow-clear
                />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-form-item
            field="description"
            :label="t('admin.roles.labels.description')"
            :validate-status="fieldError('description') ? 'error' : undefined"
            :help="fieldError('description')"
          >
            <a-textarea
              v-model="form.role.description"
              :disabled="!canManage"
              :max-length="500"
              :placeholder="t('admin.roles.form.descriptionPlaceholder')"
              :auto-size="{ minRows: 3, maxRows: 8 }"
              show-word-limit
              allow-clear
            />
          </a-form-item>
        </a-card>

        <a-card :title="t('admin.roles.form.permissions')" :bordered="true">
          <template #extra>
            <a-tag color="arcoblue">
              {{ t('admin.roles.form.selectedCount', { count: selectedPermissionCount }) }}
            </a-tag>
          </template>

          <a-empty
            v-if="permissionCatalog.length === 0"
            :description="t('admin.roles.form.emptyCatalog')"
          />
          <a-collapse v-else :default-active-key="defaultPermissionGroups">
            <a-collapse-item
              v-for="domain in permissionCatalog"
              :key="domain.key"
              :header="t('admin.roles.form.permissionGroupCount', {
                name: domain.name,
                count: domain.permissions.length,
              })"
            >
              <a-list :bordered="true" :split="true">
                <a-list-item
                  v-for="permission in domain.permissions"
                  :key="permission.key"
                >
                  <a-list-item-meta
                    :title="permission.name"
                    :description="permission.description || t('admin.roles.labels.noDescription')"
                  >
                    <template #avatar>
                      <a-checkbox
                        :model-value="permissionSelected(permission)"
                        :disabled="!canManage
                          || (!permission.grantable && !permissionSelected(permission))"
                        :aria-label="t('admin.roles.form.permissionToggle', { name: permission.name })"
                        @change="togglePermission(permission, $event)"
                      />
                    </template>
                  </a-list-item-meta>
                  <template #actions>
                    <a-space wrap>
                      <a-tag v-if="!permission.grantable" color="orange">
                        {{ permissionSelected(permission)
                          ? t('admin.roles.form.permissionRemovalOnly')
                          : t('admin.roles.form.permissionReadOnly') }}
                      </a-tag>
                      <a-tag bordered>{{ permission.key }}</a-tag>
                    </a-space>
                  </template>
                </a-list-item>
              </a-list>
            </a-collapse-item>
          </a-collapse>
        </a-card>

        <a-card :bordered="true">
          <a-space wrap>
            <a-button
              v-if="canManage"
              type="primary"
              html-type="submit"
              :loading="form.processing"
            >
              {{ t('admin.roles.actions.save') }}
            </a-button>
            <a-button @click="visitBack">
              {{ t('admin.roles.actions.back') }}
            </a-button>
            <a-button
              v-if="deleteUrl"
              status="danger"
              @click="openRetirement"
            >
              {{ t('admin.roles.actions.retire') }}
            </a-button>
          </a-space>
        </a-card>
      </a-space>
    </a-form>

    <a-modal
      v-model:visible="retirementVisible"
      :title="t('admin.roles.retirement.title')"
      :mask-closable="!retirementForm.processing"
      :esc-to-close="!retirementForm.processing"
      :footer="false"
      @cancel="closeRetirement"
    >
      <a-space direction="vertical" :size="16" fill>
        <a-alert
          type="warning"
          show-icon
          :closable="false"
          :title="t('admin.roles.retirement.warning')"
        >
          {{ requiresReplacement
            ? t('admin.roles.retirement.assignedDescription', { count: role.memberCount })
            : t('admin.roles.retirement.description') }}
        </a-alert>

        <a-form v-if="requiresReplacement" :model="retirementForm.role" layout="vertical">
          <a-form-item
            field="replacement_role_id"
            :label="t('admin.roles.retirement.replacement')"
            required
            :validate-status="retirementBlocked ? 'error' : undefined"
            :help="retirementBlocked ? t('admin.roles.retirement.replacementRequired') : undefined"
          >
            <a-select
              v-model="retirementForm.role.replacement_role_id"
              :placeholder="t('admin.roles.retirement.replacementPlaceholder')"
              :disabled="retirementForm.processing || replacementRoles.length === 0"
              allow-search
            >
              <a-option
                v-for="replacement in replacementRoles"
                :key="replacement.id"
                :value="replacement.id"
                :label="replacement.name"
              >
                <a-space>
                  <a-typography-text>{{ replacement.name }}</a-typography-text>
                  <a-tag bordered>{{ replacement.key }}</a-tag>
                </a-space>
              </a-option>
            </a-select>
          </a-form-item>
        </a-form>

        <a-alert
          v-if="requiresReplacement && replacementRoles.length === 0"
          type="error"
          show-icon
          :closable="false"
          :title="t('admin.roles.retirement.noReplacement')"
        />

        <a-space wrap>
          <a-button
            type="primary"
            status="danger"
            :disabled="retirementBlocked || (requiresReplacement && replacementRoles.length === 0)"
            :loading="retirementForm.processing"
            @click="retireRole"
          >
            {{ t('admin.roles.retirement.confirm') }}
          </a-button>
          <a-button :disabled="retirementForm.processing" @click="closeRetirement">
            {{ t('admin.roles.actions.cancel') }}
          </a-button>
        </a-space>
      </a-space>
    </a-modal>
  </a-space>
</template>
