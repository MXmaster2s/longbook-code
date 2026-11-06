// Comments on a shared report: what a viewer may send, how often, and that only the owner reads
// them and can delete one. Run: npm run cloud:test.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { COMMENT_LIMITS, isCommentId, rateRefusal, readComment, windowStart } from '../supabase/functions/share-report/comments.ts'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const source = readFileSync(join(ROOT, 'supabase/functions/share-report/index.ts'), 'utf8')
const between = (from: string, to: string) => source.slice(source.indexOf(from), source.indexOf(to, source.indexOf(from)))

test('a comment is kept as typed, within its caps', () => {
  assert.deepEqual(readComment({ module_id: 'm1', body: '  Paid twice? ', author: 'Asha' }), {
    comment: { moduleId: 'm1', body: '  Paid twice? ', author: 'Asha' },
  })
  assert.deepEqual(readComment({ module_id: 'm1', body: 'Fine' }), { comment: { moduleId: 'm1', body: 'Fine', author: '' } })
  assert.ok('refusal' in readComment({ module_id: 'm1', body: '   ' }))
  assert.ok('refusal' in readComment({ module_id: 'm1', body: 'x'.repeat(COMMENT_LIMITS.body + 1) }))
  assert.ok('comment' in readComment({ module_id: 'm1', body: 'x'.repeat(COMMENT_LIMITS.body) }))
  assert.ok('refusal' in readComment({ module_id: 'm1', body: 'Fine', author: 'a'.repeat(COMMENT_LIMITS.author + 1) }))
  assert.ok('refusal' in readComment({ module_id: '', body: 'Fine' }))
  assert.ok('refusal' in readComment({ module_id: 'm'.repeat(COMMENT_LIMITS.moduleId + 1), body: 'Fine' }))
  assert.ok('refusal' in readComment({ module_id: 3, body: 'Fine' }))
})

test('one link takes a few comments an hour and a fixed number in all', () => {
  assert.equal(rateRefusal(0, 0), null)
  assert.equal(rateRefusal(COMMENT_LIMITS.perWindow - 1, 50), null)
  assert.match(rateRefusal(COMMENT_LIMITS.perWindow, 50) ?? '', /try again later/)
  assert.match(rateRefusal(0, COMMENT_LIMITS.perShare) ?? '', /all the comments/)
  const now = new Date('2026-11-03T12:00:00Z')
  assert.equal(windowStart(now), '2026-11-03T11:00:00.000Z')
})

test('a comment id is a uuid, so a malformed one never reaches the database', () => {
  assert.ok(isCommentId('5b1c2f9e-0000-4000-8000-000000000000'))
  assert.ok(!isCommentId('5b1c2f9e'))
  assert.ok(!isCommentId("1' or '1'='1"))
  assert.ok(!isCommentId(undefined))
})

test('the function refuses a flood with 429 and gives a viewer no comments', () => {
  const comment = between('async function handleComment', 'async function handleRevoke')
  assert.ok(comment.includes('readComment('))
  assert.ok(comment.includes('refuse(limited, 429)'))
  assert.ok(comment.indexOf('rateRefusal(') < comment.indexOf(".insert("), 'counted before it is stored')
  const view = between('async function handleView', 'async function handleComment')
  assert.ok(!view.includes("from('report_comments')"), 'a viewer reads no comments')
  assert.ok(view.includes('comments: []'))
})

test('the owner, and only the owner, deletes one comment of their own link', () => {
  assert.ok(source.includes("case 'delete_comment':"))
  const remove = between('async function handleDeleteComment', 'function shareIdIn')
  assert.ok(remove.includes('await ownerShare(req, service, body.id)'))
  assert.ok(remove.includes('isCommentId(body.comment_id)'))
  assert.ok(remove.includes(".eq('share_id', gate.shareId)"), 'scoped to the owner’s own link')
  assert.ok(between('async function handleComments', 'async function handleDeleteComment').includes("select('id, module_id"))
})
