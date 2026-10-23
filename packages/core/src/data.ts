// Shapes shared by every LongbookStore implementation — not tied to any particular backend.
import type { Commitment, Member, Account, MergeUndoRow, Group, ChargeRow, EntityKind, Tag, Placeholder } from './model'

export interface LoadedData {
  subs: Commitment[]
  members: Member[]
  methods: Account[]
  undo: MergeUndoRow | null
  /**
   * How the owner has arranged their methods and members. Optional because it is
   * genuinely absent: only a vault-backed store can return groups. `undefined` means
   * "this store doesn't do groups", distinct from `[]` meaning "the owner has none".
   */
  groups?: Group[]
  /**
   * Every charge, past and planned. Same optionality as `groups`: `undefined` means "this
   * store doesn't carry charges", `[]` means none written yet.
   */
  charges?: ChargeRow[]
  /**
   * The vault's own tag registry — names and icons. Same optionality again:
   * `undefined` where a store cannot answer, `[]` where the owner has registered none.
   */
  tags?: Tag[]
  /** Commitments named at setup and waiting for details; `undefined` where a store cannot say. */
  toFillIn?: Placeholder[]
}

export interface MergeInput {
  kind: EntityKind
  ids: string[]
  canonicalId: string
  members: Member[]
  methods: Account[]
  subs: Commitment[]
  ownerId: string
}
