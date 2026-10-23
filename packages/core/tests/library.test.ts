// The seeded tag library: no tag of any kind carries a template — in the source or in the
// generated file every carrier ships. A tag is a name and an icon.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { LIBRARY_JSON, LIBRARY_TAGS, libraryTag } from '../src/index'

test('no tag of any kind carries a template, in the source or the file', () => {
  assert.ok(LIBRARY_TAGS.filter((t) => t.kind === 'commitment').length > 20, 'the commitment tags are all still there')
  assert.equal(LIBRARY_TAGS.filter((t) => t.kind === 'member').length, 8, 'and the member tags')
  assert.equal(LIBRARY_TAGS.filter((t) => t.kind === 'account').length, 8, 'and the account tags')
  assert.deepEqual(LIBRARY_TAGS.filter((t) => 'template' in t).map((t) => t.name), [])
  const file = JSON.parse(LIBRARY_JSON) as { tags: Record<string, unknown>[] }
  assert.equal(file.tags.length, LIBRARY_TAGS.length)
  for (const tag of file.tags) {
    assert.deepEqual(Object.keys(tag).sort(), ['icon', 'kind', 'name', 'name_key', 'sort'], `${String(tag.name)}: a name and an icon`)
  }
})

test('a tag is found by name in any casing within its kind, its icon with it', () => {
  assert.equal(libraryTag('account', ' Credit Card ')?.icon, 'creditcard.fill')
  assert.equal(libraryTag('member', 'Family')?.icon, 'person.2')
  assert.equal(libraryTag('commitment', 'insurance')?.icon, 'shield.checkered')
  assert.equal(libraryTag('member', 'credit card'), null, 'a name is found within its own kind')
})
