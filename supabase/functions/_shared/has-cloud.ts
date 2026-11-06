// Asks the database's one rule, has_cloud, for an account. Answers yes while the function
// is not in the database yet, so a function may be deployed ahead of its migration; any
// other failure answers no.

export interface CloudClient {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: { code?: string } | null }>
}

export const CLOUD_REQUIRED = 'This needs longbook Cloud. Subscribe in the longbook app, under Account.'

export async function hasCloud(client: CloudClient, userId: string): Promise<boolean> {
  const { data, error } = await client.rpc('has_cloud', { uid: userId })
  if (error) return error.code === 'PGRST202'
  return data === true
}
