#!/usr/bin/env -S npx tsx
// Writes the purchase email as HTML and text into a folder you can open, once as a buyer sees it
// and once as a TestFlight tester does, for a made-up buyer. Nothing is sent.
// Run: npm run email:preview [folder]. The folder defaults to a temporary one.
import { mkdirSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { renderPurchaseEmail } from '../supabase/functions/_shared/purchase-email.ts'

const out = resolve(process.argv[2] ?? join(tmpdir(), 'longbook-purchase-email'))
mkdirSync(out, { recursive: true })

const buyer = { email: 'alex.morgan@example.com', purchasedAt: new Date(), majorVersion: 1 }
for (const [name, environment] of [['purchase', 'Production'], ['purchase-test', 'Sandbox']] as const) {
  const mail = renderPurchaseEmail({ ...buyer, environment })
  writeFileSync(join(out, `${name}.html`), mail.html)
  writeFileSync(join(out, `${name}.txt`), mail.text)
  console.log(`${name}: ${mail.subject}`)
}
console.log(`written to ${out} — open the .html files in a browser. Nothing was sent.`)
