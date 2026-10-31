// Polar webhook payloads for the web purchase tests, one per event the licence follows, shaped
// by the SDK's 2026-10 types, plus one in the earlier shape with amount and user. Made-up buyer.
import type { webhooks } from 'npm:@polar-sh/sdk@1.0.2/2026-10'

export const ORGANIZATION_ID = '7aedf74e-4a00-4386-b64c-a320c761591d'
export const PRODUCT_ID = '857fb352-f0bd-43b5-97e7-9bdcb856cc68'
export const USER_ID = '4f3c2b1a-0000-4000-8000-00000000abcd'
export const ORDER_ID = 'b0a4b3f2-61c2-4d8e-9a57-0c1f3e2d9a10'
export const CUSTOMER_ID = 'c9e1d2a3-4b5c-4d6e-8f70-112233445566'
export const LICENSE_KEY_ID = 'd4c3b2a1-9f8e-4d7c-8b6a-5f4e3d2c1b0a'
export const PAID_AT = '2026-10-31T09:41:07.512Z'

const customer = {
  id: CUSTOMER_ID,
  created_at: '2026-10-31T09:38:55.120Z',
  modified_at: null,
  metadata: {},
  external_id: USER_ID,
  email: 'Alex.Morgan@example.com',
  email_verified: true,
  type: 'individual' as const,
  name: 'Alex Morgan',
  billing_name: 'Alex Morgan',
  billing_address: { country: 'IN' as const, city: 'Pune', postal_code: '411001', line1: null, line2: null, state: null },
  tax_id: null,
  organization_id: ORGANIZATION_ID,
  deleted_at: null,
  first_user_event_at: null,
  avatar_url: null,
}

const order = {
  id: ORDER_ID,
  created_at: '2026-10-31T09:40:58.004Z',
  modified_at: PAID_AT,
  status: 'paid' as const,
  paid: true,
  subtotal_amount: 3800,
  discount_amount: 0,
  net_amount: 3800,
  tax_amount: 0,
  total_amount: 3800,
  applied_balance_amount: 0,
  due_amount: 0,
  refunded_amount: 0,
  refunded_tax_amount: 0,
  currency: 'usd',
  billing_reason: 'purchase' as const,
  billing_name: 'Alex Morgan',
  billing_address: { country: 'IN' as const, city: 'Pune', postal_code: '411001', line1: null, line2: null, state: null },
  invoice_number: 'CCS-0042',
  is_invoice_generated: false,
  receipt_number: null,
  units: null,
  customer_id: CUSTOMER_ID,
  product_id: PRODUCT_ID,
  discount_id: null,
  subscription_id: null,
  checkout_id: 'e7f6a5b4-c3d2-4e1f-9a8b-7c6d5e4f3a2b',
  metadata: { user_id: USER_ID },
  platform_fee_amount: 0,
  platform_fee_currency: null,
  customer,
  product: {
    metadata: {},
    id: PRODUCT_ID,
    created_at: '2026-08-02T11:00:00.000Z',
    modified_at: '2026-10-17T08:00:00.000Z',
    trial_interval: null,
    trial_interval_count: null,
    name: 'longbook',
    description: 'One-time licence for longbook on iPhone and Mac.',
    visibility: 'public' as const,
    recurring_interval: null,
    recurring_interval_count: null,
    meter_interval: null,
    meter_interval_count: null,
    is_recurring: false,
    is_archived: false,
    organization_id: ORGANIZATION_ID,
  },
  discount: null,
  subscription: null,
  items: [{
    created_at: '2026-10-31T09:40:58.004Z',
    modified_at: null,
    id: 'f1e2d3c4-b5a6-4978-8a9b-0c1d2e3f4a5b',
    label: 'longbook',
    amount: 3800,
    tax_amount: 0,
    proration: false,
    product_price_id: 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d',
    start_timestamp: null,
    end_timestamp: null,
  }],
  description: 'longbook',
  refundable_amount: 3800,
  refundable_tax_amount: 0,
}

export const orderPaid = {
  type: 'order.paid',
  timestamp: PAID_AT,
  api_version: '2026-10',
  data: order,
} satisfies webhooks.WebhookOrderPaidPayload

export const orderRefunded = {
  type: 'order.refunded',
  timestamp: '2026-11-02T14:05:31.000Z',
  api_version: '2026-10',
  data: { ...order, status: 'refunded' as const, refunded_amount: 3800, refundable_amount: 0, modified_at: '2026-11-02T14:05:30.000Z' },
} satisfies webhooks.WebhookOrderRefundedPayload

export const benefitGrantCreated = {
  type: 'benefit_grant.created',
  timestamp: '2026-10-31T09:41:09.000Z',
  api_version: '2026-10',
  data: {
    created_at: '2026-10-31T09:41:08.700Z',
    modified_at: null,
    id: '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
    granted_at: '2026-10-31T09:41:08.900Z',
    is_granted: true,
    revoked_at: null,
    is_revoked: false,
    subscription_id: null,
    order_id: ORDER_ID,
    customer_id: CUSTOMER_ID,
    benefit_id: '5d6e7f80-9a1b-4c2d-8e3f-4a5b6c7d8e9f',
    customer: { ...customer, email: 'Alex.Morgan@example.com' },
    benefit: {
      id: '5d6e7f80-9a1b-4c2d-8e3f-4a5b6c7d8e9f',
      created_at: '2026-08-02T11:05:00.000Z',
      modified_at: null,
      type: 'license_keys',
      description: 'longbook licence key',
      selectable: true,
      deletable: true,
      is_deleted: false,
      organization_id: ORGANIZATION_ID,
      metadata: {},
      visibility: 'public',
      properties: { prefix: 'LONGBOOK', expires: null, activations: { limit: 1, enable_customer_admin: false }, limit_usage: null },
      visibility_configurable: true,
    },
    properties: { license_key_id: LICENSE_KEY_ID, display_key: '****-7C1D' },
  },
} satisfies webhooks.WebhookBenefitGrantCreatedPayload

/** An order in the shape Polar sent before its 2026 API versions: amount, and the buyer as user. */
export const legacyOrderPaid = {
  type: 'order.paid',
  data: {
    id: '91e0c7aa-3f1d-4b6e-a2c4-6f0d8e1b2a3c',
    created_at: '2026-08-14T09:12:00.000Z',
    amount: 3800,
    tax_amount: 0,
    currency: 'USD',
    product_id: PRODUCT_ID,
    customer_id: CUSTOMER_ID,
    user: { id: '2b3c4d5e-6f70-4812-9a3b-4c5d6e7f8091', email: 'jordan.lee@example.com' },
    metadata: { user_id: USER_ID },
  },
}
