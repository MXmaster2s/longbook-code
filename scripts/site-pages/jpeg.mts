// Reads a JPEG's size and writes its descriptive metadata: an XMP packet (APP1) and IPTC
// records (APP13), the two places Google Images and photo tools look for a title, caption,
// creator and copyright. Camera and capture data is dropped; the colour profile is kept.

export interface ImageMeta {
  title: string
  description: string
  keywords: string[]
  pageUrl: string
}

export const CREATOR = 'longbook'
export const COPYRIGHT = '© 2026 longbook'
export const RIGHTS_URL = 'https://longbook.app/terms/'
// Where the same pictures are offered for use: the media kit, free when writing about longbook.
export const ACQUIRE_URL = 'https://longbook.app/media-kit/#usage'
const XMP_ID = 'http://ns.adobe.com/xap/1.0/\0'
const PHOTOSHOP_ID = 'Photoshop 3.0\0'

interface Segment {
  marker: number
  start: number
  end: number
}

// Every marker segment up to the start of scan; the compressed image data is left untouched.
function segments(buf: Buffer): { list: Segment[]; scanStart: number } {
  if (buf[0] !== 0xff || buf[1] !== 0xd8) throw new Error('not a JPEG')
  const list: Segment[] = []
  let i = 2
  while (i < buf.length) {
    if (buf[i] !== 0xff) throw new Error(`bad marker at ${i}`)
    const marker = buf[i + 1]!
    if (marker === 0xda) return { list, scanStart: i }
    const length = buf.readUInt16BE(i + 2)
    list.push({ marker, start: i, end: i + 2 + length })
    i += 2 + length
  }
  throw new Error('no start of scan')
}

export function jpegSize(buf: Buffer): { width: number; height: number } {
  for (const s of segments(buf).list) {
    const m = s.marker
    if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) {
      return { height: buf.readUInt16BE(s.start + 5), width: buf.readUInt16BE(s.start + 7) }
    }
  }
  throw new Error('no frame header')
}

const esc = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

const alt = (s: string): string => `<rdf:Alt><rdf:li xml:lang="x-default">${esc(s)}</rdf:li></rdf:Alt>`

export function xmpPacket(meta: ImageMeta): string {
  const bag = meta.keywords.map((k) => `<rdf:li>${esc(k)}</rdf:li>`).join('')
  return [
    '<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>',
    '<x:xmpmeta xmlns:x="adobe:ns:meta/">',
    '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">',
    '<rdf:Description rdf:about=""',
    ' xmlns:dc="http://purl.org/dc/elements/1.1/"',
    ' xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"',
    ' xmlns:xmpRights="http://ns.adobe.com/xap/1.0/rights/"',
    ' xmlns:Iptc4xmpCore="http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/"',
    ` photoshop:Credit="${esc(CREATOR)}"`,
    ` photoshop:Source="${esc(meta.pageUrl)}"`,
    ' xmpRights:Marked="True"',
    ` xmpRights:WebStatement="${esc(RIGHTS_URL)}">`,
    `<dc:title>${alt(meta.title)}</dc:title>`,
    `<dc:description>${alt(meta.description)}</dc:description>`,
    `<Iptc4xmpCore:AltTextAccessibility>${alt(meta.description)}</Iptc4xmpCore:AltTextAccessibility>`,
    `<dc:creator><rdf:Seq><rdf:li>${esc(CREATOR)}</rdf:li></rdf:Seq></dc:creator>`,
    `<dc:rights>${alt(COPYRIGHT)}</dc:rights>`,
    `<dc:subject><rdf:Bag>${bag}</rdf:Bag></dc:subject>`,
    '</rdf:Description>',
    '</rdf:RDF>',
    '</x:xmpmeta>',
    '<?xpacket end="w"?>',
  ].join('\n')
}

// One IPTC-IIM dataset: 0x1C, record, number, a two-byte length, the bytes.
function dataset(record: number, number: number, value: Buffer): Buffer {
  if (value.length > 0x7fff) throw new Error('IPTC value too long')
  const head = Buffer.from([0x1c, record, number, value.length >> 8, value.length & 0xff])
  return Buffer.concat([head, value])
}

const utf8 = (s: string, max: number): Buffer => {
  const b = Buffer.from(s, 'utf8')
  if (b.length <= max) return b
  return Buffer.from(Buffer.from(s, 'utf8').subarray(0, max).toString('utf8').replace(/\uFFFD$/, ''), 'utf8')
}

export function iptcRecords(meta: ImageMeta): Buffer {
  return Buffer.concat([
    dataset(1, 90, Buffer.from([0x1b, 0x25, 0x47])), // coded character set: UTF-8
    dataset(2, 0, Buffer.from([0x00, 0x04])),
    dataset(2, 5, utf8(meta.title, 64)),
    dataset(2, 120, utf8(meta.description, 2000)),
    dataset(2, 80, utf8(CREATOR, 32)),
    dataset(2, 110, utf8(CREATOR, 32)),
    dataset(2, 115, utf8('longbook.app', 32)),
    dataset(2, 116, utf8(COPYRIGHT, 128)),
    ...meta.keywords.map((k) => dataset(2, 25, utf8(k, 64))),
  ])
}

function segment(marker: number, payload: Buffer): Buffer {
  if (payload.length + 2 > 0xffff) throw new Error('segment too long')
  const head = Buffer.from([0xff, marker, (payload.length + 2) >> 8, (payload.length + 2) & 0xff])
  return Buffer.concat([head, payload])
}

function photoshopBlock(iptc: Buffer): Buffer {
  const size = Buffer.alloc(4)
  size.writeUInt32BE(iptc.length)
  const pad = iptc.length % 2 ? Buffer.from([0]) : Buffer.alloc(0)
  return Buffer.concat([Buffer.from(PHOTOSHOP_ID, 'latin1'), Buffer.from('8BIM', 'latin1'),
    Buffer.from([0x04, 0x04, 0x00, 0x00]), size, iptc, pad])
}

// Rewrites the header: JFIF and the ICC profile stay, any Exif, XMP or IPTC goes, and the
// new XMP and IPTC go in right after JFIF. The scan data is copied byte for byte.
export function withMetadata(buf: Buffer, meta: ImageMeta): Buffer {
  const { list, scanStart } = segments(buf)
  const keep = list.filter((s) => s.marker !== 0xe1 && s.marker !== 0xed)
  const jfif = keep.filter((s) => s.marker === 0xe0)
  const rest = keep.filter((s) => s.marker !== 0xe0)
  const slice = (s: Segment): Buffer => buf.subarray(s.start, s.end)
  return Buffer.concat([
    Buffer.from([0xff, 0xd8]),
    ...jfif.map(slice),
    segment(0xe1, Buffer.concat([Buffer.from(XMP_ID, 'latin1'), Buffer.from(xmpPacket(meta), 'utf8')])),
    segment(0xed, photoshopBlock(iptcRecords(meta))),
    ...rest.map(slice),
    buf.subarray(scanStart),
  ])
}

export interface FoundMeta {
  xmp: string | null
  caption: string | null
  hasExif: boolean
}

// What a checker needs back: the XMP text, the IPTC caption, and whether Exif crept in.
export function readMetadata(buf: Buffer): FoundMeta {
  const found: FoundMeta = { xmp: null, caption: null, hasExif: false }
  for (const s of segments(buf).list) {
    const body = buf.subarray(s.start + 4, s.end)
    if (s.marker === 0xe1 && body.subarray(0, XMP_ID.length).toString('latin1') === XMP_ID) {
      found.xmp = body.subarray(XMP_ID.length).toString('utf8')
    } else if (s.marker === 0xe1 && body.subarray(0, 4).toString('latin1') === 'Exif') {
      found.hasExif = true
    } else if (s.marker === 0xed) {
      const i = body.indexOf(Buffer.from([0x1c, 0x02, 120]))
      if (i >= 0) {
        const len = body.readUInt16BE(i + 3)
        found.caption = body.subarray(i + 5, i + 5 + len).toString('utf8')
      }
    }
  }
  return found
}
