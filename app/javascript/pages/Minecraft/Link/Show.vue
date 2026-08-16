<script setup lang="ts">
import { computed, ref } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import { createIdempotencyKey } from '@/lib/idempotency'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

type Account = {
  id: number
  playerId: string
  username: string
  uuid: string
  identityType: string
  primary: boolean
  linkedAt?: string | null
  skinCached: boolean
  skinCachedAt?: string | null
  avatarUrl: string
  setPrimaryUrl: string
  unlinkUrl: string
  unlinkConfirmation: string
  lockVersion: number
}

const props = defineProps<{
  form_error?: string | null
  accounts: Account[]
  primaryPolicy: {
    switchPolicy: 'immediate' | 'staff_approval' | 'administrator_only'
    cooldownSeconds: number
    cooldownRemainingSeconds: number
    nextAllowedAt?: string | null
    requestExpiryHours: number
  }
  pendingRequest?: {
    id: number
    status: string
    targetAccount?: string | null
    reason: string
    requestedAt: string
    expiresAt: string
    lockVersion: number
    cancelUrl: string
  } | null
}>()

const { t, locale } = useI18n()
const switchingAccountId = ref<number | null>(null)
const cancellingRequest = ref(false)
const switchReason = ref('')
const unlinkAccount = ref<Account | null>(null)
const unlinkConfirmation = ref('')
const unlinkIdempotencyKey = ref('')
const unlinkProcessing = ref(false)

const form = useForm({
  link: { code: '' },
})

const formError = computed(
  () => (form.errors as Record<string, string>).base || props.form_error || '',
)

const switchBlocked = computed(
  () => props.primaryPolicy.switchPolicy === 'administrator_only'
    || props.primaryPolicy.cooldownRemainingSeconds > 0
    || Boolean(props.pendingRequest),
)

const unlinkReady = computed(
  () => Boolean(unlinkAccount.value)
    && unlinkConfirmation.value === unlinkAccount.value?.unlinkConfirmation
    && !unlinkProcessing.value,
)

const policyMessageKey = computed(() => {
  if (props.primaryPolicy.switchPolicy === 'administrator_only') {
    return 'minecraft.link.primaryPolicyAdministratorOnly'
  }
  if (props.primaryPolicy.switchPolicy === 'staff_approval') {
    return 'minecraft.link.primaryPolicyStaffApproval'
  }
  return 'minecraft.link.primaryPolicyImmediate'
})

function submit() {
  form.post(routes.minecraftLink)
}

function requestPrimary(account: Account) {
  if (account.primary || switchBlocked.value || switchingAccountId.value !== null) return
  if (props.primaryPolicy.switchPolicy === 'staff_approval' && !switchReason.value.trim()) return

  router.post(account.setPrimaryUrl, {
    reason: switchReason.value.trim(),
    idempotency_key: crypto.randomUUID(),
  }, {
    preserveScroll: true,
    onStart: () => {
      switchingAccountId.value = account.id
    },
    onFinish: () => {
      switchingAccountId.value = null
    },
  })
}

function cancelPendingRequest() {
  if (!props.pendingRequest || cancellingRequest.value) return

  router.delete(props.pendingRequest.cancelUrl, {
    data: { lock_version: props.pendingRequest.lockVersion },
    preserveScroll: true,
    onStart: () => {
      cancellingRequest.value = true
    },
    onFinish: () => {
      cancellingRequest.value = false
    },
  })
}

function openUnlinkModal(account: Account) {
  if (unlinkProcessing.value) return

  unlinkAccount.value = account
  unlinkConfirmation.value = ''
  unlinkIdempotencyKey.value = createIdempotencyKey()
}

function closeUnlinkModal() {
  if (unlinkProcessing.value) return

  unlinkAccount.value = null
  unlinkConfirmation.value = ''
  unlinkIdempotencyKey.value = ''
}

function submitUnlink() {
  const account = unlinkAccount.value
  if (!account || !unlinkReady.value) return false

  unlinkProcessing.value = true
  router.delete(account.unlinkUrl, {
    data: {
      confirmation: unlinkConfirmation.value,
      lock_version: account.lockVersion,
      idempotency_key: unlinkIdempotencyKey.value,
    },
    preserveScroll: true,
    onSuccess: () => {
      unlinkAccount.value = null
      unlinkConfirmation.value = ''
      unlinkIdempotencyKey.value = ''
    },
    onFinish: () => {
      unlinkProcessing.value = false
    },
  })
  return false
}

function dateLabel(value?: string | null) {
  if (!value) return t('common.notAvailable')
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}
</script>

<template>
  <a-space direction="vertical" size="large" fill>
    <a-page-header
      :title="t('minecraft.link.title')"
      :subtitle="t('minecraft.link.subtitle')"
      :show-back="false"
    />

    <a-card v-if="accounts.length > 0" :title="t('minecraft.link.boundAccountsTitle')">
      <a-space direction="vertical" size="large" fill>
        <a-alert type="info" show-icon>
          {{ t(policyMessageKey, { hours: primaryPolicy.requestExpiryHours }) }}
        </a-alert>

        <a-alert
          v-if="primaryPolicy.cooldownRemainingSeconds > 0"
          type="warning"
          show-icon
        >
          {{
            t('minecraft.link.primaryCooldownActive', {
              time: dateLabel(primaryPolicy.nextAllowedAt),
            })
          }}
        </a-alert>

        <a-alert v-if="pendingRequest" type="warning" show-icon>
          <template #title>
            {{ t('minecraft.link.pendingPrimaryRequestTitle') }}
          </template>
          <a-space direction="vertical" fill>
            <span>
              {{
                t('minecraft.link.pendingPrimaryRequestBody', {
                  account: pendingRequest.targetAccount || t('common.notAvailable'),
                  time: dateLabel(pendingRequest.expiresAt),
                })
              }}
            </span>
            <a-button
              size="small"
              status="danger"
              :loading="cancellingRequest"
              @click="cancelPendingRequest"
            >
              {{ t('minecraft.link.cancelPrimaryRequest') }}
            </a-button>
          </a-space>
        </a-alert>

        <a-form-item
          v-if="primaryPolicy.switchPolicy === 'staff_approval' && !pendingRequest"
          :label="t('minecraft.link.primaryRequestReason')"
          :help="t('minecraft.link.primaryRequestReasonHelp')"
          required
        >
          <a-textarea
            v-model="switchReason"
            :max-length="2000"
            show-word-limit
            :placeholder="t('minecraft.link.primaryRequestReasonPlaceholder')"
          />
        </a-form-item>

        <a-grid :cols="{ xs: 1, md: 2, xl: 3 }" :col-gap="16" :row-gap="16">
          <a-grid-item v-for="account in accounts" :key="account.id">
            <a-card size="small" :bordered="true" class="account-card">
              <a-space direction="vertical" fill>
                <a-space align="center" class="account-identity">
                  <a-avatar :size="64" shape="square" :image-url="account.avatarUrl">
                    {{ account.username.slice(0, 1) }}
                  </a-avatar>
                  <a-space direction="vertical" :size="2" class="account-details">
                    <a-space wrap>
                      <a-typography-text strong>{{ account.username }}</a-typography-text>
                      <a-tag v-if="account.primary" color="green">
                        {{ t('minecraft.link.primaryAccount') }}
                      </a-tag>
                    </a-space>
                    <a-typography-text code copyable class="account-uuid">
                      {{ account.uuid }}
                    </a-typography-text>
                    <a-typography-text type="secondary">
                      {{ account.identityType }}
                    </a-typography-text>
                  </a-space>
                </a-space>

                <a-space wrap>
                  <a-tag :color="account.skinCached ? 'blue' : 'orange'">
                    {{
                      account.skinCached
                        ? t('minecraft.link.skinCached')
                        : t('minecraft.link.skinCachePending')
                    }}
                  </a-tag>
                  <a-typography-text type="secondary">
                    {{ t('minecraft.link.linkedAt', { time: dateLabel(account.linkedAt) }) }}
                  </a-typography-text>
                </a-space>

                <a-space direction="vertical" fill class="account-actions">
                  <a-button
                    v-if="!account.primary"
                    type="primary"
                    long
                    :disabled="switchBlocked
                      || (primaryPolicy.switchPolicy === 'staff_approval' && !switchReason.trim())
                      || unlinkProcessing"
                    :loading="switchingAccountId === account.id"
                    @click="requestPrimary(account)"
                  >
                    {{
                      primaryPolicy.switchPolicy === 'staff_approval'
                        ? t('minecraft.link.requestPrimaryAccount')
                        : t('minecraft.link.setPrimaryAccount')
                    }}
                  </a-button>
                  <a-button
                    status="danger"
                    long
                    :disabled="switchingAccountId !== null || cancellingRequest || unlinkProcessing"
                    :aria-label="t('minecraft.link.unlinkAccountLabel', { account: account.username })"
                    @click="openUnlinkModal(account)"
                  >
                    {{ t('minecraft.link.unlinkAccount') }}
                  </a-button>
                </a-space>
              </a-space>
            </a-card>
          </a-grid-item>
        </a-grid>
      </a-space>
    </a-card>

    <a-row justify="center">
      <a-col :xs="24" :sm="22" :md="18" :lg="12" :xl="10">
        <a-card :title="t('minecraft.link.addAccountTitle')">
          <a-space direction="vertical" size="large" fill>
            <a-alert v-if="formError" type="error" show-icon>
              {{ formError }}
            </a-alert>

            <a-form :model="form.link" layout="vertical" @submit="submit">
              <a-form-item
                field="code"
                :label="t('minecraft.link.code')"
                :validate-status="form.errors['link.code'] ? 'error' : undefined"
                :help="form.errors['link.code']"
                required
              >
                <a-input
                  v-model="form.link.code"
                  autocomplete="off"
                  allow-clear
                />
              </a-form-item>
              <a-form-item>
                <a-button
                  type="primary"
                  html-type="submit"
                  long
                  :loading="form.processing"
                >
                  {{ t('minecraft.link.submit') }}
                </a-button>
              </a-form-item>
            </a-form>
          </a-space>
        </a-card>
      </a-col>
    </a-row>

    <a-modal
      :visible="Boolean(unlinkAccount)"
      :title="t('minecraft.link.unlinkTitle')"
      :ok-text="t('minecraft.link.unlinkConfirmAction')"
      :cancel-text="t('common.cancel')"
      :ok-button-props="{ status: 'danger', disabled: !unlinkReady }"
      :ok-loading="unlinkProcessing"
      :mask-closable="!unlinkProcessing"
      :closable="!unlinkProcessing"
      :on-before-ok="submitUnlink"
      align-center
      unmount-on-close
      @cancel="closeUnlinkModal"
    >
      <a-space v-if="unlinkAccount" direction="vertical" size="large" fill>
        <a-alert type="error" show-icon :title="t('minecraft.link.unlinkWarningTitle')">
          {{ t('minecraft.link.unlinkWarningBody') }}
        </a-alert>

        <a-card size="small" :bordered="true" class="unlink-target-card">
          <a-space align="center" class="account-identity">
            <a-avatar :size="56" shape="square" :image-url="unlinkAccount.avatarUrl">
              {{ unlinkAccount.username.slice(0, 1) }}
            </a-avatar>
            <a-space direction="vertical" :size="2" class="account-details">
              <a-typography-text strong>{{ unlinkAccount.username }}</a-typography-text>
              <a-typography-text code copyable class="account-uuid">
                {{ unlinkAccount.uuid }}
              </a-typography-text>
              <a-tag v-if="unlinkAccount.primary" color="orange">
                {{ t('minecraft.link.primaryAccount') }}
              </a-tag>
            </a-space>
          </a-space>
        </a-card>

        <a-typography-paragraph class="unlink-consequences">
          <strong>{{ t('minecraft.link.unlinkConsequencesTitle') }}</strong>
        </a-typography-paragraph>
        <ul class="unlink-consequences-list">
          <li>{{ t('minecraft.link.unlinkConsequenceAccess') }}</li>
          <li>{{ t('minecraft.link.unlinkConsequencePrimary') }}</li>
          <li>{{ t('minecraft.link.unlinkConsequenceRequests') }}</li>
          <li>{{ t('minecraft.link.unlinkConsequenceRelink') }}</li>
        </ul>

        <a-form :model="{ confirmation: unlinkConfirmation }" layout="vertical">
          <a-form-item
            field="confirmation"
            :label="t('minecraft.link.unlinkConfirmationLabel')"
            required
          >
            <a-space direction="vertical" fill>
              <a-typography-text id="minecraft-unlink-confirmation-help" type="secondary">
                {{
                  t('minecraft.link.unlinkConfirmationHelp', {
                    account: unlinkAccount.unlinkConfirmation,
                  })
                }}
              </a-typography-text>
              <a-input
                v-model="unlinkConfirmation"
                autocomplete="off"
                allow-clear
                :disabled="unlinkProcessing"
                :placeholder="unlinkAccount.unlinkConfirmation"
                aria-describedby="minecraft-unlink-confirmation-help"
              />
            </a-space>
          </a-form-item>
        </a-form>
      </a-space>
    </a-modal>
  </a-space>
</template>

<style scoped>
.account-card,
.account-details {
  min-width: 0;
}

.account-identity {
  width: 100%;
  min-width: 0;
}

.account-details {
  flex: 1;
  overflow: hidden;
}

.account-uuid {
  max-width: 100%;
  overflow-wrap: anywhere;
  white-space: normal;
}

.account-actions {
  width: 100%;
}

.unlink-consequences {
  margin-bottom: 0;
}

.unlink-consequences-list {
  margin: -12px 0 0;
  padding-inline-start: 1.25rem;
  color: var(--color-text-2);
}

.unlink-consequences-list li + li {
  margin-top: 0.4rem;
}

@media (max-width: 575px) {
  .account-identity {
    align-items: flex-start;
  }

  .unlink-target-card :deep(.arco-card-body) {
    padding: 12px;
  }
}
</style>
