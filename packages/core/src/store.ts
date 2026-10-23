// Storage adapter. Apps talk to a LongbookStore, never to the filesystem directly — the
// desktop app's FileStore (JSON on disk) is the one real implementation today. A Supabase-backed
// CloudStore existed here for the killed "Longbook Cloud" product; removed, not just unused.
import type {
  Commitment,
  CommitmentInsert,
  CommitmentUpdate,
  Member,
  Account,
  MergeUndoRow,
  EntityKind,
} from './model'
import type { LoadedData, MergeInput } from './data'

type EntityRow = { id: string; name_key: string }
// Fields either entity kind can carry through an update. Some are kind-specific and the backend
// strips the ones that don't apply: photo_url/member_group are a member's, member_id (the
// optional owner) is a payment method's.
type EntityFields = {
  name?: string
  photo_url?: string | null
  member_group?: 'family' | 'team' | null
  member_id?: string | null
}

/**
 * Portable snapshot of a user's financial memory — **their own rows and nothing else**.
 * The "Export my data" file format. Excludes merge_undo and account/owner ids.
 *
 * Owned-rows-only is a contract, not a description: today it's a no-op filter, but a
 * future shared-read policy would turn an unfiltered export/re-import into laundering.
 */
export interface LongbookExport {
  app: 'longbook'
  version: 1
  exported_at: string
  commitments: Commitment[]
  members: Member[]
  accounts: Account[]
}

/** Everything the apps need to read and mutate a user's data, independent of where it lives. */
export interface LongbookStore {
  loadAll(): Promise<LoadedData>
  ensureEntity(kind: EntityKind, rawName: string, existing: EntityRow[]): Promise<string | null>
  insertCommitment(payload: CommitmentInsert): Promise<Commitment>
  updateCommitment(id: string, payload: CommitmentUpdate): Promise<Commitment>
  deleteCommitment(id: string): Promise<void>
  createEntity(kind: EntityKind, name: string): Promise<Member | Account>
  updateEntity(kind: EntityKind, id: string, fields: EntityFields): Promise<Member | Account>
  deleteEntity(kind: EntityKind, id: string): Promise<void>
  keepTrial(sub: Commitment): Promise<Commitment>
  scheduleCancellation(sub: Commitment, isoDate?: string): Promise<Commitment>
  clearScheduledCancellation(sub: Commitment): Promise<Commitment>
  mergeEntities(input: MergeInput): Promise<MergeUndoRow | null>
  undoMerge(undo: MergeUndoRow): Promise<void>
  /**
   * Snapshot the store's data into the portable export format. Implementations owe the
   * owned-rows-only contract on `LongbookExport`: export what this user owns, never merely what
   * this user can read.
   */
  exportData(): Promise<LongbookExport>
  /**
   * Load an exported snapshot into this store. Idempotent upsert by id (entities first, then
   * commitments). This is how a device seeds its local store from a backup.
   */
  importData(data: LongbookExport): Promise<void>
}

/**
 * Build a portable export from already-loaded data, shared by every store implementation.
 *
 * A shaper, not a gate: exports whatever rows it's handed. Ownership is the caller's to
 * establish — "everything loaded" equals "everything owned" only until a shared-read
 * policy ships.
 */
export function toExport(data: Pick<LoadedData, 'subs' | 'members' | 'methods'>, exportedAt: string): LongbookExport {
  return {
    app: 'longbook',
    version: 1,
    exported_at: exportedAt,
    commitments: data.subs,
    members: data.members,
    accounts: data.methods,
  }
}
