#!/usr/bin/env -S npx tsx
// Writes the media kit's text from media-kit/kit.json and media-kit/files.json: the page's body and
// JSON-LD, the Markdown copy at media-kit/index.md, and the sitemap's list of the kit's images.
// Run: npm run site:media-kit:text; --check fails when any of them is stale.
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const SITE = join(ROOT, 'apps/longbook-site')
const KIT = join(SITE, 'media-kit')
const CHECK = process.argv.includes('--check')
const ORIGIN = 'https://longbook.app'
const PAGE = `${ORIGIN}/media-kit/`

type Row = {
  path: string; url: string; type: string; bytes: number; width: number; height: number
  sha256: string; title: string; description: string; group: string; rights: string
}
type Named = { label: string; file: string }
type Screen = { slug: string; title: string; text: string; source: string }

const kit = JSON.parse(readFileSync(join(KIT, 'kit.json'), 'utf8'))
const list = JSON.parse(readFileSync(join(KIT, 'files.json'), 'utf8')) as { files: Row[]; preview: Row[] }
const rows = new Map([...list.files, ...list.preview].map((row) => [row.path, row]))
const row = (path: string): Row => {
  const found = rows.get(path)
  if (!found) throw new Error(`media-kit/files.json has no ${path}; run npm run site:media-kit`)
  return found
}

const esc = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
// kit.json writes a link as [text](address), the one piece of markup it carries.
const html = (s: string): string =>
  esc(s).replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, text, href) => `<a href="${href.replace(ORIGIN, '')}">${text}</a>`)
const size = (bytes: number): string =>
  bytes >= 1e6 ? `${(bytes / 1e6).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1e3))} KB`
const kind = (r: Row): string => r.path.split('.').pop()!.toUpperCase()
const noEmail = (s: string): string => `<!--email_off-->${s}<!--/email_off-->`

const screenName = (platform: string, i: number, s: Screen): string =>
  `longbook-${platform}-${String(i + 1).padStart(2, '0')}-${s.slug}`
const founderBase = `longbook-founder-${kit.founder.name.toLowerCase().replace(/ /g, '-')}`

// Anything kit.json names must have been built with the same words, or the images carry stale ones.
const stale: string[] = []
for (const [platform, label] of [['iphone', 'iPhone'], ['mac', 'Mac']] as const) {
  kit.screens[platform].forEach((s: Screen, i: number) => {
    const r = row(`screenshots/${platform}/${screenName(platform, i, s)}.png`)
    if (r.title !== `longbook on ${label}: ${s.title}` || !r.description.startsWith(s.text)) stale.push(r.path)
  })
}
for (const logo of kit.logos) {
  for (const f of logo.files as Named[]) if (row(f.file).title !== `longbook: ${logo.title}`) stale.push(f.file)
}
if (stale.length) {
  console.error(`media-kit — files.json describes ${stale.length} file(s) differently from kit.json, e.g. ${stale[0]}.`)
  console.error('Rebuild the images, which carry those words: npm run site:media-kit')
  process.exit(1)
}

// ---- the page ---------------------------------------------------------------------------------

const download = (label: string, path: string): string =>
  `<a href="/media-kit/files/${path}" download="${path.split('/').pop()}">${esc(label)}</a>`

const logoArt = (art: string, alt: string): string => {
  const src = (name: string): string => `/media-kit/files/logo/${name}`
  switch (art) {
    case 'dark':
      return `<div class="art on-dark"><img src="${src('longbook-logo-on-dark.svg')}" width="300" height="73" alt="${esc(alt)}"></div>`
    case 'light':
      return `<div class="art on-light"><img src="${src('longbook-logo-on-light.svg')}" width="300" height="73" alt="${esc(alt)}"></div>`
    case 'icon':
      return `<div class="art on-light"><img class="ic" src="${src('longbook-app-icon.svg')}" width="120" height="120" alt="${esc(alt)}"></div>`
    case 'mark':
      return `<div class="art split"><div class="on-dark"><img class="bk" src="${src('longbook-mark.svg')}" width="66" height="104" alt="${esc(alt)} on a dark background"></div>` +
        `<div class="on-light"><img class="bk" src="${src('longbook-mark.svg')}" width="66" height="104" alt="${esc(alt)} on a light background"></div></div>`
    default:
      return `<div class="art split"><div class="on-light"><img class="bk mono" src="${src('longbook-mark-black.png')}" width="88" height="88" alt="${esc(alt)}, black"></div>` +
        `<div class="on-dark"><img class="bk mono" src="${src('longbook-mark-white.png')}" width="88" height="88" alt="${esc(alt)}, white"></div></div>`
  }
}

const screenFigure = (platform: 'iphone' | 'mac', label: string) => (s: Screen, i: number): string => {
  const name = screenName(platform, i, s)
  const preview = row(`preview/${name}.jpg`)
  const device = platform === 'iphone' ? 'phone' : 'mac'
  return `          <figure class="shot">
            <div class="${device}"><img src="/media-kit/files/${preview.path}" width="${preview.width}" height="${preview.height}" loading="lazy" alt="${esc(`${s.title} on ${label}: ${s.text}`)}"></div>
            <figcaption><p class="item-t">${esc(s.title)}</p><p class="item-d">${esc(s.text)}</p><div class="dls">${download('Framed', `screenshots/${platform}/framed/${name}-framed.png`)}${download('Original', `screenshots/${platform}/${name}.png`)}</div></figcaption>
          </figure>`
}

const heroPreview = row('preview/longbook-hero.jpg')
const founderPreview = row(`preview/${founderBase}.jpg`)
const sections = ['About', 'Facts', 'Logos', 'Screenshots', 'Colour and type', 'Founder', 'Contact']
const anchor = (s: string): string => ({ About: 'about', 'Colour and type': 'colour' } as Record<string, string>)[s] ?? s.toLowerCase()

const body = `<header class="hero">
  <div class="hero-in">
    <img class="hero-icon" src="/media-kit/files/logo/longbook-app-icon.svg" width="64" height="64" alt="">
    <h1 class="lb-display-xl">${esc(kit.title)}</h1>
    <p class="lead">${esc(kit.lead)}</p>
    <div class="acts">
      <a class="btn" id="zip" href="#logos">Download everything <span class="size" hidden></span></a>
      ${noEmail(`<a class="btn ghost" href="mailto:${kit.email}">Email ${kit.email}</a>`)}
    </div>
    <p class="meta" id="usage">${esc(kit.usage)}</p>
    <p class="meta">Updated ${esc(kit.updatedLabel)}</p>
  </div>
  <img class="hero-art" src="/media-kit/files/${heroPreview.path}" width="${heroPreview.width}" height="${heroPreview.height}" fetchpriority="high" alt="${esc(kit.hero.alt)}">
</header>

<div class="kit">
  <nav class="index" aria-label="On this page">
    <span class="ribbon" aria-hidden="true"></span>
    <ul>
${sections.map((s) => `      <li><a href="#${anchor(s)}">${esc(s)}</a></li>`).join('\n')}
    </ul>
  </nav>

  <main>
    <section id="about" aria-labelledby="about-h">
      <h2 id="about-h" class="lb-display-lg">About longbook</h2>
      <p class="intro">${esc(kit.aboutIntro)}</p>
      <div class="copier card">
        <div class="seg" role="tablist" aria-label="Description length">
${kit.descriptions.map((d: { id: string; label: string }, i: number) => `          <button type="button" role="tab" id="tab-${d.id}" aria-controls="panel-${d.id}" aria-selected="${i === 0}"${i ? ' tabindex="-1"' : ''}>${esc(d.label)}</button>`).join('\n')}
        </div>
${kit.descriptions.map((d: { id: string; label: string; text: string }) => `        <div class="panel" role="tabpanel" id="panel-${d.id}" aria-labelledby="tab-${d.id}" tabindex="0">
          <p>${esc(d.text)}</p>
        </div>`).join('\n')}
        <div class="copier-foot">
          <span class="count" aria-live="polite"></span>
          <button class="btn sm" type="button" id="copy-desc">Copy text</button>
        </div>
      </div>
      <div class="spell">
        <p>${esc(kit.spelling.text)}</p>
        <span class="yes"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 8.5l3.2 3L13 4.5"/></svg>${esc(kit.spelling.right)}</span>
${kit.spelling.wrong.map((w: string) => `        <span class="no"><span class="sr">Not </span>${esc(w)}</span>`).join('\n')}
      </div>
    </section>

    <section id="facts" aria-labelledby="facts-h">
      <h2 id="facts-h" class="lb-display-lg">Facts</h2>
      <ul class="rows">
${kit.facts.map((f: { key: string; value: string; href?: string }) => {
  const value = f.href ? `<a href="${f.href.replace(ORIGIN, '') || '/'}">${esc(f.value)}</a>` : esc(f.value)
  return `        <li><span class="k">${esc(f.key)}</span><span class="v">${f.href?.startsWith('mailto:') ? noEmail(value) : value}</span></li>`
}).join('\n')}
      </ul>

      <h3 class="lb-title">What it does</h3>
      <div class="does">
${kit.does.map((d: { title: string; text: string }) => `        <div><p class="item-t">${esc(d.title)}</p><p class="item-d">${esc(d.text)}</p></div>`).join('\n')}
      </div>
    </section>

    <section id="logos" aria-labelledby="logos-h">
      <h2 id="logos-h" class="lb-display-lg">Logos</h2>
      <p class="intro">${esc(kit.logosIntro)}</p>
      <div class="tiles">
${kit.logos.map((l: { title: string; text: string; art: string; alt: string; files: Named[] }, i: number) => `        <figure class="tile ${i < 2 ? 'half' : 'third'} card">
          ${logoArt(l.art, l.alt)}
          <figcaption>
            <div><p class="item-t">${esc(l.title)}</p><p class="item-d">${esc(l.text)}</p></div>
            <div class="dls">${l.files.map((f) => download(f.label, f.file)).join('')}</div>
          </figcaption>
        </figure>`).join('\n')}
      </div>

      <h3 class="lb-title">Using the logo</h3>
      <ul class="rules">
${kit.rules.map((r: string) => `        <li>${esc(r)}</li>`).join('\n')}
      </ul>
      <div class="donts">
${kit.misuse.map((m: { class: string; label: string; alt: string }) => `        <figure><div class="art on-dark"><img class="${m.class}" src="/media-kit/files/logo/longbook-mark.svg" width="48" height="76" alt="${esc(m.alt)}"></div><figcaption><svg viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M2.5 2.5l7 7M9.5 2.5l-7 7"/></svg>${esc(m.label)}</figcaption></figure>`).join('\n')}
      </div>
    </section>

    <section id="screenshots" aria-labelledby="shots-h">
      <h2 id="shots-h" class="lb-display-lg">Screenshots</h2>
      <p class="intro">${esc(kit.screensIntro)}</p>

      <div class="herodl card">
        <img src="/media-kit/files/${heroPreview.path}" width="${heroPreview.width}" height="${heroPreview.height}" loading="lazy" alt="${esc(kit.hero.alt)}">
        <div>
          <p class="item-t">${esc(kit.hero.title)}</p>
          <p class="item-d">${esc(kit.hero.text)} ${row('images/longbook-hero-light.jpg').width} × ${row('images/longbook-hero-light.jpg').height}.</p>
          <div class="dls">${download('Light, JPG', 'images/longbook-hero-light.jpg')}${download('Dark, JPG', 'images/longbook-hero-dark.jpg')}${download('Light, transparent', 'images/longbook-hero-light-transparent.png')}${download('Dark, transparent', 'images/longbook-hero-dark-transparent.png')}</div>
        </div>
      </div>

      <h3 class="lb-title">iPhone</h3>
      <div class="shelf">
        <div class="phones">
${kit.screens.iphone.map(screenFigure('iphone', 'iPhone')).join('\n')}
        </div>
      </div>

      <h3 class="lb-title">Mac</h3>
      <div class="shelf">
        <div class="macs">
${kit.screens.mac.map(screenFigure('mac', 'Mac')).join('\n')}
        </div>
      </div>
    </section>

    <section id="colour" aria-labelledby="colour-h">
      <h2 id="colour-h" class="lb-display-lg">Colour and type</h2>
      <p class="intro">${esc(kit.colourIntro)}</p>
      <div class="swatches">
${kit.colours.map((c: { name: string; hex: string; role: string }) => `        <button class="swatch card" type="button" style="--c:${c.hex}" data-hex="${c.hex}"><span class="chip"></span><span class="sw"><span class="item-t">${esc(c.name)}</span><span class="hex">${c.hex}</span><span class="item-d">${esc(c.role)}</span></span></button>`).join('\n')}
      </div>
      <div class="faces">
${kit.type.map((t: { name: string; face: string; role: string; sample: string; href: string }) => `        <div class="face ${t.face} card">
          <span class="aa" aria-hidden="true">Aa</span>
          <p class="item-t">${esc(t.name)}</p>
          <p class="item-d">${esc(t.role)}</p>
          <p class="sample">${esc(t.sample)}</p>
          <a href="${t.href}" rel="noopener">${esc(t.name)} on Google Fonts</a>
        </div>`).join('\n')}
      </div>
      <p class="note">${esc(kit.typeNote)}</p>
    </section>

    <section id="founder" aria-labelledby="founder-h">
      <h2 id="founder-h" class="lb-display-lg">Founder</h2>
      <div class="founder">
        <div>
          <img src="/media-kit/files/${founderPreview.path}" width="${founderPreview.width}" height="${founderPreview.height}" loading="lazy" alt="${esc(kit.founder.alt)}">
          <div class="dls">${download('Photo, JPG', `founder/${founderBase}.jpg`)}${download('Square, JPG', `founder/${founderBase}-square.jpg`)}</div>
        </div>
        <div>
          <h3 class="lb-title">${esc(kit.founder.name)}</h3>
          <p class="role">${esc(kit.founder.role)}</p>
          <blockquote>
${kit.founder.quote.map((q: string, i: number, all: string[]) => `            <p>${i === 0 ? '“' : ''}${esc(q)}${i === all.length - 1 ? '”' : ''}</p>`).join('\n')}
          </blockquote>
          <p class="sig">On X as <a href="https://x.com/${kit.founder.x}" rel="noopener">@${kit.founder.x}</a></p>
        </div>
      </div>
    </section>

    <section id="contact" aria-labelledby="contact-h">
      <h2 id="contact-h" class="lb-display-lg">Contact</h2>
      ${noEmail(`<a class="mail lb-display-lg" href="mailto:${kit.email}">${kit.email}</a>`)}
${kit.contact.map((c: string) => `      <p>${html(c)}</p>`).join('\n')}
    </section>
  </main>
</div>`

// ---- structured data ---------------------------------------------------------------------------

const org = `${ORIGIN}/#organization`
const image = (r: Row, preview?: Row): Record<string, unknown> => ({
  '@type': 'ImageObject',
  '@id': r.url,
  contentUrl: r.url,
  name: r.title,
  caption: r.description,
  encodingFormat: r.type,
  width: r.width,
  height: r.height,
  ...(preview ? { thumbnailUrl: preview.url } : {}),
  creator: { '@id': org },
  creditText: kit.credit,
  copyrightNotice: r.rights,
  license: `${PAGE}#usage`,
  acquireLicensePage: `${PAGE}#usage`,
})
const previewOf = (r: Row): Row | undefined => {
  const m = r.path.match(/^screenshots\/(?:iphone|mac)\/(?:framed\/)?(longbook-[a-z]+-\d\d-[a-z-]+?)(?:-framed)?\.png$/)
  return m ? rows.get(`preview/${m[1]}.jpg`) : undefined
}
const originals = list.files.filter((r) => /^screenshots\/(iphone|mac)\/longbook-/.test(r.path))
const graph = {
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'Organization', '@id': org, name: 'longbook', url: `${ORIGIN}/`, email: kit.email,
      logo: image(row('logo/longbook-app-icon-512.png')), founder: { '@id': `${PAGE}#founder` },
    },
    {
      '@type': 'Person', '@id': `${PAGE}#founder`, name: kit.founder.name, jobTitle: 'Founder',
      worksFor: { '@id': org }, image: image(row(`founder/${founderBase}-square.jpg`)),
      sameAs: [`https://x.com/${kit.founder.x}`],
    },
    {
      '@type': 'SoftwareApplication', '@id': `${ORIGIN}/#app`, name: 'longbook', url: `${ORIGIN}/`,
      applicationCategory: kit.app.category, operatingSystem: kit.app.os, softwareVersion: kit.app.version,
      description: kit.descriptions[1].text, publisher: { '@id': org },
      offers: { '@type': 'Offer', price: kit.app.price, priceCurrency: kit.app.currency },
      screenshot: originals.map((r) => ({ '@id': r.url })),
    },
    {
      '@type': 'CollectionPage', '@id': PAGE, url: PAGE, name: kit.title, description: kit.lead,
      inLanguage: 'en', dateModified: kit.updated, about: { '@id': `${ORIGIN}/#app` }, publisher: { '@id': org },
      primaryImageOfPage: { '@id': row('images/longbook-hero-light.jpg').url },
      associatedMedia: list.files.filter((r) => r.type.startsWith('image/') && !r.path.includes('/framed/')).map((r) => image(r, previewOf(r))),
    },
  ],
}
const jsonld = noEmail(`<script type="application/ld+json">\n${JSON.stringify(graph, null, 2)}\n</script>`)

// ---- Markdown, for AI readers -----------------------------------------------------------------

const md = (s: string): string => s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '[$1]($2)')
const fileLine = (label: string, r: Row, indent = '  '): string =>
  `${indent}- ${label}: [${r.path.split('/').pop()}](${r.url}) (${kind(r)}, ${r.width} × ${r.height}, ${size(r.bytes)})`
const screensMd = (platform: 'iphone' | 'mac', label: string): string =>
  kit.screens[platform].map((s: Screen, i: number) => {
    const name = screenName(platform, i, s)
    return [
      `${i + 1}. **${s.title}:** ${s.text}`,
      fileLine('Original', row(`screenshots/${platform}/${name}.png`), '   '),
      fileLine(`Framed in the ${label} frame`, row(`screenshots/${platform}/framed/${name}-framed.png`), '   '),
    ].join('\n')
  }).join('\n')

const markdown = `# ${kit.title}

> ${kit.lead}

${kit.usage} Updated ${kit.updatedLabel}.

- The page: ${PAGE}
- Every file, with its size, dimensions and SHA-256: ${PAGE}files.json
- Press contact: ${kit.email}

## About longbook

${kit.aboutIntro}

${kit.descriptions.map((d: { label: string; text: string }) => `### ${d.label}\n\n${d.text}`).join('\n\n')}

${kit.spelling.text} Write **${kit.spelling.right}**, not ${kit.spelling.wrong.join(', ').replace(/, ([^,]*)$/, ' or $1')}.

## Facts

${kit.facts.map((f: { key: string; value: string }) => `- **${f.key}:** ${f.value}`).join('\n')}

### What it does

${kit.does.map((d: { title: string; text: string }) => `- **${d.title}.** ${d.text}`).join('\n')}

## Logos

${kit.logosIntro}

${kit.logos.map((l: { title: string; text: string; files: Named[] }) => [`- **${l.title}.** ${l.text}`, ...l.files.map((f) => fileLine(f.label, row(f.file)))].join('\n')).join('\n')}

### Using the logo

${kit.rules.map((r: string) => `- ${r}`).join('\n')}

## Screenshots

${kit.screensIntro}

### Hero image

${kit.hero.text}

${['light', 'dark'].flatMap((tone) => [fileLine(`${tone[0].toUpperCase()}${tone.slice(1)}, JPG`, row(`images/longbook-hero-${tone}.jpg`)), fileLine(`${tone[0].toUpperCase()}${tone.slice(1)}, transparent PNG`, row(`images/longbook-hero-${tone}-transparent.png`))]).map((l) => l.replace(/^ {2}/, '')).join('\n')}

### iPhone

${screensMd('iphone', 'iPhone')}

### Mac

${screensMd('mac', 'Mac')}

## Colour and type

${kit.colourIntro.replace(/ Select a colour[^.]*\./, '')}

${kit.colours.map((c: { name: string; hex: string; role: string }) => `- **${c.name}** \`${c.hex}\`: ${c.role}`).join('\n')}

${kit.type.map((t: { name: string; role: string; href: string }) => `- **${t.name}:** ${t.role} ${t.href}`).join('\n')}

${kit.typeNote}

## Founder

**${kit.founder.name}**, ${kit.founder.role.charAt(0).toLowerCase()}${kit.founder.role.slice(1)}. On X as @${kit.founder.x}.

${kit.founder.quote.map((q: string) => `> ${q}`).join('\n>\n')}

${fileLine('Photo', row(`founder/${founderBase}.jpg`)).replace(/^ {2}/, '')}
${fileLine('Square', row(`founder/${founderBase}-square.jpg`)).replace(/^ {2}/, '')}

## Contact

${kit.email}

${kit.contact.map((c: string) => md(c)).join('\n\n')}
`

// ---- the sitemap --------------------------------------------------------------------------------

const imageEntries = list.files.filter((r) => r.type.startsWith('image/'))
  .map((r) => `    <image:image><image:loc>${r.url}</image:loc></image:image>`).join('\n')
const kitEntry = `  <url>\n    <loc>${PAGE}</loc>\n${imageEntries}\n  </url>\n`

// ---- write, or check ------------------------------------------------------------------------------

const region = (text: string, name: string, content: string): string => {
  const start = text.indexOf(`<!-- media-kit:${name}`)
  const endTag = `<!-- /media-kit:${name} -->`
  const end = text.indexOf(endTag)
  if (start < 0 || end < start) throw new Error(`media-kit/index.html has no media-kit:${name} region`)
  const open = text.slice(start, text.indexOf('-->', start) + 3)
  return `${text.slice(0, start)}${open}\n${content}\n${text.slice(end)}`
}

const pagePath = join(KIT, 'index.html')
const mdPath = join(KIT, 'index.md')
const sitemapPath = join(SITE, 'sitemap.xml')
const page = readFileSync(pagePath, 'utf8')
const sitemap = readFileSync(sitemapPath, 'utf8')
const nextSitemap = sitemap
  .replace(/<urlset xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9"(?: xmlns:image="[^"]*")?>/,
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">')
  .replace(/  <url>(?:(?!<\/url>)[\s\S])*?<loc>https:\/\/longbook\.app\/media-kit\/<\/loc>[\s\S]*?<\/url>\n/, kitEntry)
const outputs: [string, string, string][] = [
  [pagePath, page, region(region(page, 'jsonld', jsonld), 'body', body)],
  [mdPath, (() => { try { return readFileSync(mdPath, 'utf8') } catch { return '' } })(), markdown],
  [sitemapPath, sitemap, nextSitemap],
]
if (!nextSitemap.includes(kitEntry)) throw new Error('sitemap.xml has no entry for /media-kit/')

const changed = outputs.filter(([, before, after]) => before !== after)
if (CHECK) {
  if (changed.length) {
    for (const [path] of changed) console.error(`media-kit — ${path.replace(`${ROOT}/`, '')} is stale.`)
    console.error('Regenerate it from media-kit/kit.json and files.json: npm run site:media-kit:text')
    process.exit(1)
  }
  console.log('media-kit — the page, index.md and the sitemap match kit.json and files.json.')
} else {
  for (const [path, , after] of changed) writeFileSync(path, after)
  console.log(`media-kit — ${changed.length ? changed.map(([p]) => p.replace(`${ROOT}/`, '')).join(', ') : 'nothing'} written.`)
}
