// An in-memory stand-in for the parts of supabase-js the polar functions use, so the flow test
// runs the real function files with no database. Filters behave as PostgREST's do on these
// rows; row-level security is not modelled, as the functions use the service role.
type Row = Record<string, any>

// Kept on globalThis: the test imports this file as ESM and the functions require it as CommonJS.
const shared = globalThis as { __webPurchaseDb?: typeof made }
const made = {
  tables: {} as Record<string, Row[]>,
  users: [] as { id: string; email: string; email_confirmed_at?: string | null }[],
  keys: { entitlements: 'user_id', web_orders: 'order_id', cloud_grants: 'user_id', licence_price_steps: 'tier' } as Record<string, string>,
  reset() {
    this.tables = {}
    this.users = []
  },
  rows(table: string): Row[] {
    return (this.tables[table] ??= [])
  },
}
export const db = (shared.__webPurchaseDb ??= made)

class Query {
  private tests: ((r: Row) => boolean)[] = []
  private op: 'select' | 'update' | 'upsert' | 'insert' | 'delete' = 'select'
  private payload: Row = {}
  private returning = false
  private single = false
  private max = Infinity
  private rank: { column: string; ascending: boolean } | null = null
  private counted = false

  constructor(private table: string) {}

  select(_columns?: string, options?: { count?: string }): this {
    if (this.op === 'select') this.counted = !!options?.count
    else this.returning = true
    return this
  }
  update(payload: Row): this {
    this.op = 'update'
    this.payload = payload
    return this
  }
  upsert(payload: Row): this {
    this.op = 'upsert'
    this.payload = payload
    return this
  }
  insert(payload: Row): this {
    this.op = 'insert'
    this.payload = payload
    return this
  }
  delete(): this {
    this.op = 'delete'
    return this
  }
  eq(column: string, value: unknown): this {
    this.tests.push((r) => r[column] === value)
    return this
  }
  ilike(column: string, pattern: string): this {
    const source = pattern.replace(/\\?[\s\S]/g, (c) => {
      if (c === '%' || c === '*') return '.*'
      if (c === '_') return '.'
      return c.slice(-1).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    })
    const like = new RegExp(`^${source}$`, 'i')
    this.tests.push((r) => typeof r[column] === 'string' && like.test(r[column]))
    return this
  }
  gte(column: string, value: string): this {
    this.tests.push((r) => new Date(r[column]).getTime() >= new Date(value).getTime())
    return this
  }
  is(column: string, value: null): this {
    this.tests.push((r) => (r[column] ?? null) === value)
    return this
  }
  not(column: string, _op: 'is', value: null): this {
    this.tests.push((r) => (r[column] ?? null) !== value)
    return this
  }
  or(_filter: string): this {
    return this
  }
  order(column: string, options: { ascending: boolean }): this {
    this.rank = { column, ascending: options.ascending }
    return this
  }
  limit(n: number): this {
    this.max = n
    return this
  }
  maybeSingle(): this {
    this.single = true
    return this
  }

  private run(): { data: unknown; error: { message: string } | null; count?: number } {
    const rows = db.rows(this.table)
    const key = db.keys[this.table] ?? 'id'
    const matched = () => rows.filter((r) => this.tests.every((t) => t(r)))
    let out: Row[] = []
    if (this.op === 'upsert' || this.op === 'insert') {
      const held = rows.find((r) => r[key] === this.payload[key])
      if (held && this.op === 'insert') return { data: null, error: { message: 'duplicate key' } }
      if (held) Object.assign(held, this.payload)
      else rows.push({ ...this.payload })
      out = [held ?? rows[rows.length - 1]!]
    } else if (this.op === 'update') {
      out = matched()
      for (const r of out) Object.assign(r, this.payload)
    } else if (this.op === 'delete') {
      out = matched()
      db.tables[this.table] = rows.filter((r) => !out.includes(r))
    } else {
      out = matched()
      if (this.rank) {
        const { column, ascending } = this.rank
        out = [...out].sort((a, b) => (a[column] < b[column] ? -1 : 1) * (ascending ? 1 : -1))
      }
      out = out.slice(0, this.max)
    }
    const copies = out.map((r) => ({ ...r }))
    if (this.op !== 'select' && !this.returning) return { data: null, error: null }
    if (this.counted) return { data: null, error: null, count: copies.length }
    return { data: this.single ? copies[0] ?? null : copies, error: null }
  }

  then<T>(ok: (value: any) => T): Promise<T> {
    return Promise.resolve(ok(this.run()))
  }
}

export function createClient(_url: string, _key: string) {
  return {
    from: (table: string) => new Query(table),
    auth: {
      getUser: async (jwt: string) => {
        const user = db.users.find((u) => `token-${u.id}` === jwt)
        return { data: { user: user ?? null }, error: user ? null : { message: 'bad token' } }
      },
      admin: {
        getUserById: async (id: string) => {
          const user = db.users.find((u) => u.id === id)
          return { data: { user: user ?? null }, error: user ? null : { message: 'not found' } }
        },
      },
    },
  }
}

export type SupabaseClient = ReturnType<typeof createClient>
