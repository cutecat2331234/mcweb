<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  membership_type: {
    id?: number
    slug: string
    name: string
    description: string
    color: string
    icon: string
    duration_mode: string
    duration_days: number
    luckperms_group: string
    game_permission_enabled: boolean
    game_permission_mode: string
    grant_commands: string
    revoke_commands: string
    display_priority: number
    active: boolean
  }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ membership_type: { ...props.membership_type } })

const durationModeOptions = computed(() => [
  { value: 'fixed_days', label: t('admin.forms.membershipType.durationFixed') },
  { value: 'permanent', label: t('admin.forms.membershipType.durationPermanent') },
])

const gamePermissionModeOptions = computed(() => [
  { value: 'website_managed', label: t('admin.forms.membershipType.gameModeWebsite') },
  { value: 'lp_timed', label: t('admin.forms.membershipType.gameModeLpTimed') },
])

function fillDefaultGrant() {
  const group = form.membership_type.luckperms_group || form.membership_type.slug || 'vip'
  if (form.membership_type.game_permission_mode === 'lp_timed') {
    form.membership_type.grant_commands = JSON.stringify(
      [`lp user {player} parent addtemp ${group} {duration}`],
      null,
      2,
    )
  } else {
    form.membership_type.grant_commands = JSON.stringify(
      [`lp user {player} parent add ${group}`],
      null,
      2,
    )
  }
}

function fillDefaultRevoke() {
  const group = form.membership_type.luckperms_group || form.membership_type.slug || 'vip'
  form.membership_type.revoke_commands = JSON.stringify(
    [`lp user {player} parent remove ${group}`],
    null,
    2,
  )
}

function fieldError(field: string) {
  return form.errors[field] || form.errors[`membership_type.${field}`]
}

function normalizeEmptyNumbers(record: object, fields: string[]) {
  const values = record as Record<string, unknown>
  fields.forEach((field) => {
    if (values[field] === undefined) values[field] = null
  })
}

function submit(event?: { errors?: unknown }) {
  if (event?.errors) return
  normalizeEmptyNumbers(form.membership_type, ['duration_days', 'display_priority'])
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}
</script>

<template>
  <section class="admin-store-membership-type-form">
    <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />

    <a-form
      :model="form.membership_type"
      layout="vertical"
      class="max-w-4xl"
      @submit="submit"
    >
      <a-space direction="vertical" fill :size="16">
        <a-card :bordered="true">
          <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="name"
                :label="t('admin.common.name')"
                :rules="[{ required: true, message: t('admin.common.name') }]"
                :validate-status="fieldError('name') ? 'error' : undefined"
                :help="fieldError('name')"
              >
                <a-input v-model="form.membership_type.name" allow-clear />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="slug"
                :label="t('admin.common.slugFull')"
                :rules="[{ required: true, message: t('admin.common.slugFull') }]"
                :validate-status="fieldError('slug') ? 'error' : undefined"
                :help="fieldError('slug')"
              >
                <a-input v-model="form.membership_type.slug" allow-clear />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-form-item
            field="description"
            :label="t('admin.common.description')"
            :validate-status="fieldError('description') ? 'error' : undefined"
            :help="fieldError('description')"
          >
            <a-textarea
              v-model="form.membership_type.description"
              :auto-size="{ minRows: 2, maxRows: 6 }"
              allow-clear
            />
          </a-form-item>

          <a-grid :cols="{ xs: 1, sm: 3 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="color"
                :label="t('admin.forms.membershipType.color')"
                :validate-status="fieldError('color') ? 'error' : undefined"
                :help="fieldError('color')"
              >
                <a-color-picker v-model="form.membership_type.color" show-text />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="icon"
                :label="t('admin.forms.membershipType.icon')"
                :validate-status="fieldError('icon') ? 'error' : undefined"
                :help="fieldError('icon')"
              >
                <a-input
                  v-model="form.membership_type.icon"
                  :max-length="8"
                  :placeholder="t('admin.forms.membershipType.icon')"
                  show-word-limit
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="display_priority"
                :label="t('admin.forms.membershipType.displayPriority')"
                :validate-status="fieldError('display_priority') ? 'error' : undefined"
                :help="fieldError('display_priority')"
              >
                <a-input-number
                  v-model="form.membership_type.display_priority"
                  class="w-full"
                />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="duration_mode"
                :label="t('admin.forms.membershipType.durationMode')"
                :validate-status="fieldError('duration_mode') ? 'error' : undefined"
                :help="fieldError('duration_mode')"
              >
                <a-select
                  v-model="form.membership_type.duration_mode"
                  :options="durationModeOptions"
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item v-if="form.membership_type.duration_mode === 'fixed_days'">
              <a-form-item
                field="duration_days"
                :label="t('admin.forms.membershipType.durationDays')"
                :validate-status="fieldError('duration_days') ? 'error' : undefined"
                :help="fieldError('duration_days')"
              >
                <a-input-number
                  v-model="form.membership_type.duration_days"
                  :min="1"
                  class="w-full"
                />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-space>
            <a-switch v-model="form.membership_type.active" />
            <a-typography-text>{{ t('admin.common.enable') }}</a-typography-text>
          </a-space>
        </a-card>

        <a-card :bordered="true">
          <a-space direction="vertical" fill :size="16">
            <a-space>
              <a-switch v-model="form.membership_type.game_permission_enabled" />
              <a-typography-text>
                {{ t('admin.forms.membershipType.gamePermissionEnabled') }}
              </a-typography-text>
            </a-space>

            <template v-if="form.membership_type.game_permission_enabled">
              <a-form-item
                field="game_permission_mode"
                :label="t('admin.forms.membershipType.gamePermissionMode')"
                :validate-status="fieldError('game_permission_mode') ? 'error' : undefined"
                :help="fieldError('game_permission_mode')"
              >
                <a-select
                  v-model="form.membership_type.game_permission_mode"
                  :options="gamePermissionModeOptions"
                />
              </a-form-item>

              <a-form-item
                field="luckperms_group"
                :label="t('admin.forms.membershipType.luckpermsGroup')"
                :validate-status="fieldError('luckperms_group') ? 'error' : undefined"
                :help="fieldError('luckperms_group')"
              >
                <a-input v-model="form.membership_type.luckperms_group" allow-clear />
              </a-form-item>

              <a-form-item
                field="grant_commands"
                :label="t('admin.forms.membershipType.grantCommands')"
                :validate-status="fieldError('grant_commands') ? 'error' : undefined"
                :help="fieldError('grant_commands') || t('admin.forms.membershipType.commandsHint')"
              >
                <template #extra>
                  <a-button size="small" @click="fillDefaultGrant">
                    {{ t('admin.forms.membershipType.fillDefault') }}
                  </a-button>
                </template>
                <a-textarea
                  v-model="form.membership_type.grant_commands"
                  :auto-size="{ minRows: 4, maxRows: 10 }"
                  class="font-mono text-xs"
                />
              </a-form-item>

              <a-form-item
                field="revoke_commands"
                :label="t('admin.forms.membershipType.revokeCommands')"
                :validate-status="fieldError('revoke_commands') ? 'error' : undefined"
                :help="fieldError('revoke_commands') || t('admin.forms.membershipType.commandsHint')"
              >
                <template #extra>
                  <a-button size="small" @click="fillDefaultRevoke">
                    {{ t('admin.forms.membershipType.fillDefault') }}
                  </a-button>
                </template>
                <a-textarea
                  v-model="form.membership_type.revoke_commands"
                  :auto-size="{ minRows: 3, maxRows: 10 }"
                  class="font-mono text-xs"
                />
              </a-form-item>
            </template>
          </a-space>
        </a-card>

        <a-space wrap>
          <a-button type="primary" html-type="submit" :loading="form.processing">
            {{ t('admin.ui.save') }}
          </a-button>
          <Link
            :href="backUrl"
            class="arco-btn arco-btn-outline arco-btn-size-medium no-underline"
          >
            {{ t('admin.ui.cancel') }}
          </Link>
        </a-space>
      </a-space>
    </a-form>
  </section>
</template>
