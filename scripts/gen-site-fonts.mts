// The app's two faces, cut for the web from the TTFs it draws with, and the site's own
// handwriting face. Fraunces' SOFT and WONK axes are pinned where the app leaves them.
// Not drift-checked: woff2 bytes are not stable across compressor versions.
import { execFileSync } from 'node:child_process'
import { mkdirSync, copyFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
const SRC = join(ROOT, 'packages/swift-design/Sources/DesignSystem/Resources/Fonts')
const SITE_SRC = join(ROOT, 'apps/longbook-site-content/fonts')
const OUT = join(ROOT, 'apps/longbook-site/fonts')
const PYTHON = process.env.LONGBOOK_PYTHON ?? 'python3'

const CUT = `
import sys, os
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

src, site_src, out = sys.argv[1], sys.argv[2], sys.argv[3]
# LBFontLoader sets wght and opsz and nothing else, so the other axes stay where the face
# ships them. Pinning them there is what the app already draws, minus the unused deltas.
PIN = {"Fraunces-Variable": {"SOFT": 0, "WONK": 1}, "PublicSans-Variable": {}}
SITE = {"Caveat-Variable": {}}

for name, pins in list(PIN.items()) + list(SITE.items()):
    font = TTFont(os.path.join(src if name in PIN else site_src, name + ".ttf"))
    if "DSIG" in font:
        del font["DSIG"]
    if pins:
        instancer.instantiateVariableFont(font, pins, inplace=True, updateFontNames=False)
    if name in SITE:
        # The site's face draws two short lowercase notes, so it carries those letters only.
        from fontTools import subset
        opts = subset.Options(); opts.layout_features = ["*"]; opts.name_IDs = ["*"]; opts.notdef_outline = True
        sub = subset.Subsetter(opts); sub.populate(unicodes=list(range(0x61, 0x7B)) + [0x20, 0x2C, 0x27])
        sub.subset(font)
    font.flavor = "woff2"
    dest = os.path.join(out, name + ".woff2")
    font.save(dest)
    axes = ",".join(a.axisTag for a in font["fvar"].axes)
    coverage = set()
    for table in font["cmap"].tables:
        coverage |= set(table.cmap)
    print(f"{name}.woff2  {os.path.getsize(dest) / 1024:6.1f} KB  axes: {axes}  glyphs: {len(coverage)}")
`

mkdirSync(OUT, { recursive: true })

try {
  execFileSync(PYTHON, ['-c', 'import fontTools, brotli'], { stdio: 'pipe' })
} catch {
  console.error(`${PYTHON} needs fonttools and brotli: python3 -m pip install fonttools brotli`)
  console.error('or point LONGBOOK_PYTHON at an interpreter that has them.')
  process.exit(1)
}

console.log(execFileSync(PYTHON, ['-c', CUT, SRC, SITE_SRC, OUT], { encoding: 'utf8' }).trim())

// The OFL requires its own text to travel with the font it licenses.
for (const licence of ['OFL-Fraunces.txt', 'OFL-PublicSans.txt']) {
  copyFileSync(join(SRC, licence), join(OUT, licence))
}
copyFileSync(join(SITE_SRC, 'OFL-Caveat.txt'), join(OUT, 'OFL-Caveat.txt'))
console.log('licences copied beside the faces.')
