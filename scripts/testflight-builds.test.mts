// The public beta takes the iPhone build only. Run: npm run device-build:test.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { joinsPublicBeta } from './testflight-builds.mts'

test('the iPhone build joins the public beta; the Mac build and an unknown platform do not', () => {
  assert.equal(joinsPublicBeta('IOS'), true)
  assert.equal(joinsPublicBeta('MAC_OS'), false)
  assert.equal(joinsPublicBeta('TV_OS'), false)
  assert.equal(joinsPublicBeta(undefined), false)
})
