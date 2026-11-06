// @longbook/core — shared domain logic and types for desktop + iOS.

// Types & constants
export type {
  Commitment,
  CommitmentInsert,
  CommitmentUpdate,
  Member,
  Account,
  MergeUndoRow,
  Group,
  GroupKind,
  AccountGroup,
  MemberGroup,
  TagGroup,
  Tag,
  TagKind,
  Details,
  DetailValue,
  ChargeRow,
  ChargeBasis,
  BillingCycle,
  SubStatus,
  EntityKind,
  CurrencyCode,
  Hint,
} from './model'
export { CURRENCIES, QUICK_CURRENCIES, CURRENCY_SYMBOL } from './model'
export { LIBRARY_TAGS, libraryTag } from './library'
export type { LibraryTag } from './library'
// The contract files as constants (generated), and the chapter/revision helpers over them.
export { CONTRACT_REVISION, LLMS_TXT, SCHEMA_JSON, LIBRARY_JSON, PROMPTS_JSON } from './contract'
export { RELEASE_VERSION } from './release'
export { PROMPTS, PROMPT_GROUPS, findPrompt, promptKey, promptPhrase } from './prompts'
export type { LongbookPrompt, PromptGroup, PromptGroupId } from './prompts'
export { contractRevisionOf, guideKey, guideKeys, guideSlug, guideSections, guideSection, promptGuideKey, WHOLE_GUIDE } from './guide'
export type { GuideSection } from './guide'

// Domain — dates
export {
  parseDate,
  toISO,
  todayMid,
  daysBetween,
  monthsBetween,
  addMonthsClamped,
  dueLabel,
  relativeDayLabel,
  fmtDate,
} from './domain/dates'

// Domain — money
export { fmtMoney, fmtMoneyTotals, monthlyEquiv, annualEquiv, cycleLabel } from './domain/money'
export type { FmtMoneyOpts } from './domain/money'

// Domain — the casing rule (a spec and a list; nothing to call at runtime, see casing.ts)
export { BRAND_CASING, CASING_WHITELIST } from './domain/casing'
export type { CasingWhitelistEntry } from './domain/casing'

// Domain — names & avatars
export { nameKey } from './domain/names'
export { tagPalette, entityPalette, vaultPalettes, monogram } from './domain/avatar'
export type { Palette, Palettes } from './domain/avatar'

// Domain — a commitment's standing
export { cancelInfo, displayStatus, isEffectivelyActive } from './domain/renewal'
export type { CancelInfo } from './domain/renewal'

// Data layer — LoadedData/MergeInput are the shared shapes every LongbookStore implementation
// returns/accepts.
export type { LoadedData, MergeInput } from './data'

// Domain — data minimization (Financial-Memory-Data-Policy): the memory cannot hold secrets.
export { scanText, scanFields, scannableWords, numberWord, policyFix, DATA_POLICY_REFUSAL } from './domain/dataPolicy'
export type { DataPolicyViolation } from './domain/dataPolicy'

// Storage adapter — the apps talk to a LongbookStore, never to the filesystem directly.
export { toExport } from './store'
export type { LongbookStore, LongbookExport } from './store'

// Selectors — spend by group, summed from the rows in a window
export { defaultWindow, spendByTag, spendByMember, spendByMethod } from './selectors'
export type { TagSpend, MemberSpend, MethodSpend } from './selectors'

// The ledger — every charge a row; the one generator writes rows on request
export {
  isIncome,
  isTransfer,
  isSpending,
  storedDirection,
  allCharges,
  incomeCharges,
  transferCharges,
  nextDueDay,
  chargesOf,
  chargesInRange,
  nextChargeOnOrAfter,
  nextUnpaidChargeOnOrAfter,
  isLiveCommitment,
  liveCommitments,
  plannedThrough,
  plansRunningShort,
  activeUpcoming,
  nextPaymentDay,
  sumByCurrency,
  spendSeriesRange,
  CUSTOM_DAYS_LIMIT,
  stepFrom,
  planCharges,
} from './ledger'
export type { Charge, DueMeta, PaymentDay, CurrencyAmount, MonthPoint } from './ledger'
