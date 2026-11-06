// A page's share card at 1200×630: the mark, the headline in Fraunces, one line, and the page's
// own screens from features/img bleeding off the right edge. Dark, like the screenshots in it.
// site-og serves it beside the site and photographs it with headless Chrome.
import type { ShareTarget } from './seo.mts'

const esc = (s: string): string => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

// Which screens to show is decided by the caller: a key whose image is not built is passed as null.
export function shareCardHtml(t: ShareTarget, iphone: string | null, mac: string | null): string {
  const shape = iphone && mac ? 'both' : iphone ? 'phone' : mac ? 'mac' : 'none'
  const macEl = mac
    ? `<div class="mac"><div class="bar"><i></i><i></i><i></i></div><img src="/features/img/${mac}.jpg" alt=""></div>` : ''
  const phoneEl = iphone ? `<div class="iph"><img src="/features/img/${iphone}.jpg" alt=""></div>` : ''
  const markEl = shape === 'none' ? '<img class="big" src="/logo.svg" alt="">' : ''
  return `<!doctype html>
<html><head><meta charset="utf-8">
<style>
@font-face { font-family:'Fraunces'; src:url(/fonts/Fraunces-Variable.woff2) format('woff2'); font-weight:100 900; }
@font-face { font-family:'Public Sans'; src:url(/fonts/PublicSans-Variable.woff2) format('woff2'); font-weight:100 900; }
* { box-sizing:border-box; margin:0; }
html, body { width:1200px; height:630px; overflow:hidden; background:#0D1115; }
body { position:relative; color:#D3D8DE; font-family:'Public Sans', sans-serif; -webkit-font-smoothing:antialiased; }
.glow { position:absolute; inset:0; background:radial-gradient(640px 520px at 960px 420px, rgba(109,90,230,.30), transparent 70%); }
.text { position:absolute; left:72px; top:64px; bottom:60px; width:${shape === 'none' ? 640 : 540}px; display:flex; flex-direction:column; }
.brand { display:flex; align-items:center; gap:14px; }
.brand img { width:44px; height:44px; border-radius:11px; }
.brand span { font-family:'Fraunces', serif; font-size:30px; font-weight:560; color:#EEF0F3; letter-spacing:-.01em; }
.words { margin:auto 0; }
h1 { font-family:'Fraunces', serif; font-weight:500; font-size:66px; line-height:1.04; letter-spacing:-.02em; color:#F2F3F5; font-optical-sizing:auto; }
p { margin-top:22px; font-size:25px; line-height:1.42; color:#A3ACB7; }
.site { font-size:21px; color:#8F82F2; font-weight:600; letter-spacing:.01em; }
.mac { position:absolute; left:${shape === 'mac' ? 668 : 620}px; top:${shape === 'mac' ? 92 : 78}px; width:680px; height:620px; border-radius:14px; overflow:hidden;
  background:#14171D; border:1px solid #2A303A; box-shadow:0 30px 80px rgba(0,0,0,.55); }
.mac .bar { height:30px; display:flex; align-items:center; gap:8px; padding:0 14px; background:#181C23; border-bottom:1px solid #262B34; }
.mac .bar i { width:12px; height:12px; border-radius:50%; background:#FF5F57; }
.mac .bar i:nth-child(2) { background:#FEBC2E; } .mac .bar i:nth-child(3) { background:#28C840; }
.mac img { display:block; width:100%; }
.iph { position:absolute; left:${shape === 'phone' ? 760 : 930}px; top:${shape === 'phone' ? 70 : 150}px; width:${shape === 'phone' ? 330 : 270}px; padding:10px;
  border-radius:${shape === 'phone' ? 56 : 48}px; background:#1B1F26; border:1px solid #333A45; box-shadow:0 30px 80px rgba(0,0,0,.6); }
.iph img { display:block; width:100%; border-radius:${shape === 'phone' ? 46 : 38}px; }
.big { position:absolute; right:96px; top:165px; width:300px; height:300px; border-radius:72px; box-shadow:0 30px 90px rgba(109,90,230,.35); }
</style></head>
<body>
<div class="glow"></div>
${macEl}${phoneEl}${markEl}
<div class="text">
  <div class="brand"><img src="/logo.svg" alt=""><span>longbook</span></div>
  <div class="words"><h1>${esc(t.headline)}</h1><p>${esc(t.line)}</p></div>
  <div class="site">longbook.app</div>
</div>
<script>
// A long headline steps down until the words fit between the mark and the address.
document.fonts.ready.then(() => {
  const h = document.querySelector('h1'), box = document.querySelector('.text'), words = document.querySelector('.words')
  let size = 66
  while (size > 40 && words.offsetHeight > box.clientHeight - 150) { size -= 2; h.style.fontSize = size + 'px' }
})
</script>
</body></html>
`
}
