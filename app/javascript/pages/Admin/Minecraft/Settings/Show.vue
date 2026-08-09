<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  settings: {
    link_command: string
    skin_mode: string
    bridges_enabled: string
    bridge_placeholders: string
    profile_sections: string
    graceful_stop_enabled: string
    graceful_stop_countdown: string
    graceful_stop_message: string
    graceful_stop_commands: string
    exec_command_allowed_prefixes: string
    pause_fulfill_during_maintenance: string
    backup_enabled: string
    backup_schedule: string
    primary_account_switch_policy: 'immediate' | 'staff_approval' | 'administrator_only'
    primary_account_cooldown_seconds: string
    primary_account_request_expiry_hours: string
  }
  updateUrl: string
}>()

const { t } = useI18n()
const form = useForm({ ...props.settings })

const booleanOptions = [
  { value: 'true', label: t('adminMinecraft.yes') },
  { value: 'false', label: t('adminMinecraft.no') },
]
const skinOptions = [
  { value: '2d', label: t('adminMinecraft.skin2d') },
  { value: '3d', label: t('adminMinecraft.skin3d') },
  { value: 'both', label: t('adminMinecraft.skinBoth') },
]
const primaryAccountPolicyOptions = [
  { value: 'immediate', label: t('adminMinecraft.primaryAccountPolicyImmediate') },
  { value: 'staff_approval', label: t('adminMinecraft.primaryAccountPolicyStaffApproval') },
  { value: 'administrator_only', label: t('adminMinecraft.primaryAccountPolicyAdministratorOnly') },
]

function submit() {
  form.patch(props.updateUrl)
}
</script>

<template>
  <a-page-header :title="t('adminMinecraft.title')" :show-back="false" />
  <a-form :model="form" layout="vertical" class="admin-settings-form" @submit="submit">
    <a-space direction="vertical" fill>
      <a-card :bordered="true">
        <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16">
          <a-grid-item>
            <a-form-item field="link_command" :label="t('adminMinecraft.linkCommand')">
              <a-input v-model="form.link_command" allow-clear />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="skin_mode" :label="t('adminMinecraft.skinMode')">
              <a-select v-model="form.skin_mode" :options="skinOptions" />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="bridges_enabled" :label="t('adminMinecraft.bridgesEnabled')">
              <a-select v-model="form.bridges_enabled" :options="booleanOptions" />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item
              field="bridge_placeholders"
              :label="t('adminMinecraft.bridgePlaceholders')"
            >
              <a-input
                v-model="form.bridge_placeholders"
                placeholder="%player_level%,%vault_eco_balance%"
                allow-clear
              />
            </a-form-item>
          </a-grid-item>
        </a-grid>
        <a-form-item field="profile_sections" :label="t('adminMinecraft.profileSections')">
          <a-input v-model="form.profile_sections" allow-clear />
        </a-form-item>
      </a-card>

      <a-card :title="t('adminMinecraft.gracefulStopSection')" :bordered="true">
        <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16">
          <a-grid-item>
            <a-form-item
              field="graceful_stop_enabled"
              :label="t('adminMinecraft.gracefulStopEnabled')"
            >
              <a-select v-model="form.graceful_stop_enabled" :options="booleanOptions" />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item
              field="graceful_stop_countdown"
              :label="t('adminMinecraft.gracefulStopCountdown')"
            >
              <a-input v-model="form.graceful_stop_countdown" type="number" min="0" />
            </a-form-item>
          </a-grid-item>
        </a-grid>
        <a-form-item
          field="graceful_stop_message"
          :label="t('adminMinecraft.gracefulStopMessage')"
        >
          <a-input v-model="form.graceful_stop_message" allow-clear />
        </a-form-item>
        <a-form-item
          field="graceful_stop_commands"
          :label="t('adminMinecraft.gracefulStopCommands')"
        >
          <a-input v-model="form.graceful_stop_commands" placeholder="save-all,stop" allow-clear />
        </a-form-item>
      </a-card>

      <a-card :title="t('adminMinecraft.nodeOpsSection')" :bordered="true">
        <a-form-item
          field="exec_command_allowed_prefixes"
          :label="t('adminMinecraft.execAllowedPrefixes')"
        >
          <a-input
            v-model="form.exec_command_allowed_prefixes"
            placeholder="ls,tail,systemctl"
            allow-clear
          />
        </a-form-item>
        <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16">
          <a-grid-item>
            <a-form-item
              field="pause_fulfill_during_maintenance"
              :label="t('adminMinecraft.pauseFulfillMaintenance')"
            >
              <a-select
                v-model="form.pause_fulfill_during_maintenance"
                :options="booleanOptions"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="backup_enabled" :label="t('adminMinecraft.backupEnabled')">
              <a-select v-model="form.backup_enabled" :options="booleanOptions" />
            </a-form-item>
          </a-grid-item>
        </a-grid>
        <a-form-item field="backup_schedule" :label="t('adminMinecraft.backupSchedule')">
          <a-input v-model="form.backup_schedule" placeholder="0 3 * * *" allow-clear />
        </a-form-item>
      </a-card>

      <a-card :title="t('adminMinecraft.primaryAccountsSection')" :bordered="true">
        <a-alert type="info" show-icon>
          {{ t('adminMinecraft.primaryAccountsDescription') }}
        </a-alert>
        <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16">
          <a-grid-item :span="{ xs: 1, md: 2 }">
            <a-form-item
              field="primary_account_switch_policy"
              :label="t('adminMinecraft.primaryAccountSwitchPolicy')"
            >
              <a-select
                v-model="form.primary_account_switch_policy"
                :options="primaryAccountPolicyOptions"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item
              field="primary_account_cooldown_seconds"
              :label="t('adminMinecraft.primaryAccountCooldownSeconds')"
              :help="t('adminMinecraft.primaryAccountCooldownHelp')"
            >
              <a-input
                v-model="form.primary_account_cooldown_seconds"
                type="number"
                min="0"
                :max="2678400"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item
              field="primary_account_request_expiry_hours"
              :label="t('adminMinecraft.primaryAccountRequestExpiryHours')"
            >
              <a-input
                v-model="form.primary_account_request_expiry_hours"
                type="number"
                min="1"
                :max="720"
              />
            </a-form-item>
          </a-grid-item>
        </a-grid>
      </a-card>

      <a-button html-type="submit" type="primary" :loading="form.processing">
        {{ t('common.save') }}
      </a-button>
    </a-space>
  </a-form>
</template>

<style scoped>
.admin-settings-form {
  max-width: 880px;
}
</style>
