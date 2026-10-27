// Reads the top level of an XML property list: each key of the outer dictionary and the kind
// of value it holds (true, false, string, array, dict, data…). Values themselves are never kept.
export function topLevelKinds(xml: string): Record<string, string> {
  const out: Record<string, string> = {}
  const tag = /<(\/?)([A-Za-z]+)[^>]*?(\/?)>|([^<]+)/g
  let depth = 0
  let inKey = false
  let key = ''
  let pending: string | null = null
  for (const m of xml.replace(/<!--[\s\S]*?-->/g, '').matchAll(tag)) {
    const [, close, name, selfClose, text] = m
    if (text !== undefined) {
      if (inKey) key += text
      continue
    }
    if (name === 'plist') continue
    if (close) {
      if (name === 'key') {
        inKey = false
        if (depth === 1) pending = key.trim()
      } else if (name === 'dict' || name === 'array') depth--
      continue
    }
    if (name === 'key') {
      inKey = true
      key = ''
      continue
    }
    if (depth === 1 && pending !== null) {
      out[pending] = name
      pending = null
    }
    if ((name === 'dict' || name === 'array') && !selfClose) depth++
  }
  return out
}

export const topLevelKeys = (xml: string): string[] => Object.keys(topLevelKinds(xml))
