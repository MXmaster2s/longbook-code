// Builds the media kit's files from media-kit/kit.json, the brand sources, the store screenshots, the
// homepage captures and the founder's photo; every image carries its title, description and rights.
// Writes media-kit/files.json. Run: npm run site:media-kit. The built files are never committed.
import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let fm = FileManager.default
let root = URL(fileURLWithPath: #filePath).standardizedFileURL
  .deletingLastPathComponent().deletingLastPathComponent()
let origin = "https://longbook.app/media-kit/"

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("media-kit — \(message)\n".utf8))
  exit(1)
}

// ---- the kit's own description of itself -----------------------------------------------------

struct Kit: Decodable {
  struct Named: Decodable { let label: String; let file: String }
  struct Logo: Decodable { let id: String; let title: String; let text: String; let files: [Named] }
  struct Screen: Decodable { let slug: String; let title: String; let text: String; let source: String }
  struct Screens: Decodable { let iphone: [Screen]; let mac: [Screen] }
  struct Hero: Decodable { let title: String; let text: String; let light: String; let dark: String }
  struct Founder: Decodable { let name: String; let role: String; let photo: String; let faceCentre: Double; let alt: String }
  let usage: String
  let credit: String
  let rights: String
  let keywords: [String]
  let logos: [Logo]
  let hero: Hero
  let screens: Screens
  let founder: Founder
}

let site = root.appendingPathComponent("apps/longbook-site/media-kit")
let kit: Kit = {
  guard let data = try? Data(contentsOf: site.appendingPathComponent("kit.json")) else { fail("cannot read media-kit/kit.json") }
  do { return try JSONDecoder().decode(Kit.self, from: data) } catch { fail("media-kit/kit.json: \(error)") }
}()

func run(_ args: [String]) -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = args
  process.currentDirectoryURL = root
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice
  do { try process.run() } catch { fail("could not run \(args[0])") }
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

// Worktrees share one git directory, and the uncommitted sources live beside it in the main checkout.
let mainCheckout = URL(fileURLWithPath: run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"]))
  .deletingLastPathComponent()

func source(_ path: String) -> URL {
  for base in [root, mainCheckout] {
    let url = base.appendingPathComponent(path)
    if fm.fileExists(atPath: url.path) { return url }
  }
  fail("\(path) is missing. Screenshots go in images/screenshots; photos and captures in images/media-kit.")
}

let out = site.appendingPathComponent("files")
try? fm.removeItem(at: out)

func target(_ path: String) -> URL {
  let url = out.appendingPathComponent(path)
  do {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  } catch { fail("cannot create \(path)") }
  return url
}

// ---- what each file is, for its own metadata and for files.json -----------------------------

struct About {
  let title: String
  let text: String
  let group: String
  var rights: String = kit.rights
}

var described: [String: (about: About, width: Int, height: Int)] = [:]

func keywords(_ about: About) -> [String] {
  var words = kit.keywords
  if about.group.contains("iphone") { words.append("screenshot") }
  if about.group.contains("mac") { words.append("screenshot") }
  if about.group == "logo" { words.append("logo") }
  return words
}

func xmp(_ about: About) -> CGMutableImageMetadata {
  let meta = CGImageMetadataCreateMutable()
  let text: [(String, String)] = [
    ("dc:title[x-default]", about.title), ("dc:description[x-default]", about.text),
    ("dc:rights[x-default]", about.rights), ("xmpRights:UsageTerms[x-default]", kit.usage),
    ("xmpRights:WebStatement", origin), ("photoshop:Credit", kit.credit), ("photoshop:Source", origin),
    ("photoshop:Headline", about.title), ("xmp:CreatorTool", "longbook media kit"),
  ]
  for (path, value) in text { CGImageMetadataSetValueWithPath(meta, nil, path as CFString, value as CFString) }
  let lists: [(String, CGImageMetadataType, [String])] = [("creator", .arrayOrdered, [kit.credit]), ("subject", .arrayUnordered, keywords(about))]
  for (name, type, values) in lists {
    if let tag = CGImageMetadataTagCreate(kCGImageMetadataNamespaceDublinCore, kCGImageMetadataPrefixDublinCore, name as CFString, type, values as CFArray) {
      CGImageMetadataSetTagWithPath(meta, nil, "dc:\(name)" as CFString, tag)
    }
  }
  return meta
}

// Foundation dictionaries, not Swift ones: ImageIO writes IPTC fields in the dictionary's order, and
// a Swift dictionary's order changes with every run, which would change every JPEG's bytes.
func dictionary(_ pairs: [(CFString, Any)]) -> NSMutableDictionary {
  let result = NSMutableDictionary()
  for (key, value) in pairs { result[key] = value }
  return result
}

func properties(_ about: About) -> NSMutableDictionary {
  dictionary([
    (kCGImagePropertyTIFFDictionary, dictionary([
      (kCGImagePropertyTIFFImageDescription, about.text), (kCGImagePropertyTIFFArtist, kit.credit),
      (kCGImagePropertyTIFFCopyright, about.rights), (kCGImagePropertyTIFFSoftware, "longbook media kit"),
    ])),
    (kCGImagePropertyIPTCDictionary, dictionary([
      (kCGImagePropertyIPTCObjectName, about.title), (kCGImagePropertyIPTCHeadline, about.title),
      (kCGImagePropertyIPTCCaptionAbstract, about.text), (kCGImagePropertyIPTCByline, [kit.credit]),
      (kCGImagePropertyIPTCCopyrightNotice, about.rights), (kCGImagePropertyIPTCCredit, kit.credit),
      (kCGImagePropertyIPTCSource, origin), (kCGImagePropertyIPTCKeywords, keywords(about)),
      (kCGImagePropertyIPTCRightsUsageTerms, kit.usage),
    ])),
  ])
}

let crcTable: [UInt32] = (0..<256).map { n in
  var c = UInt32(n)
  for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
  return c
}

func crc32(_ bytes: Data) -> UInt32 {
  var c: UInt32 = 0xFFFF_FFFF
  for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
  return c ^ 0xFFFF_FFFF
}

func bigEndian(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }

/// The PNG text chunks that tools reading no XMP still show: title, author, description, copyright.
func addTextChunks(_ url: URL, _ about: About) {
  guard var png = try? Data(contentsOf: url), png.count > 12,
    String(decoding: png[(png.count - 8)..<(png.count - 4)], as: UTF8.self) == "IEND"
  else { fail("\(url.lastPathComponent) is not a finished PNG") }
  var chunks = Data()
  let pairs = [("Title", about.title), ("Author", kit.credit), ("Description", about.text), ("Copyright", about.rights),
               ("Comment", "\(kit.usage) \(origin)"), ("Software", "longbook media kit")]
  for (key, value) in pairs {
    var body = Data(key.utf8)
    body.append(contentsOf: [0, 0, 0])
    body.append(contentsOf: Array("en".utf8))
    body.append(contentsOf: [0, 0])
    body.append(Data(value.utf8))
    let kind = Data("iTXt".utf8)
    chunks.append(bigEndian(UInt32(body.count)))
    chunks.append(kind)
    chunks.append(body)
    chunks.append(bigEndian(crc32(kind + body)))
  }
  png.insert(contentsOf: chunks, at: png.count - 12)
  do { try png.write(to: url) } catch { fail("cannot write \(url.lastPathComponent)") }
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
  CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// A drawing surface measured from the top-left, as every layout below is written.
final class Canvas {
  let width: Int, height: Int, ctx: CGContext

  init(_ width: Int, _ height: Int) {
    self.width = width
    self.height = height
    guard let ctx = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("cannot make a \(width)×\(height) canvas") }
    ctx.interpolationQuality = .high
    self.ctx = ctx
  }

  func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
    CGRect(x: x, y: Double(height) - y - h, width: w, height: h)
  }

  var all: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

  func fill(_ r: CGRect, radius: Double = 0, _ color: CGColor) {
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
  }

  func draw(_ image: CGImage, in r: CGRect, radius: Double = 0) {
    ctx.saveGState()
    if radius > 0 {
      ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
      ctx.clip()
    }
    ctx.draw(image, in: r)
    ctx.restoreGState()
  }

  var image: CGImage {
    guard let image = ctx.makeImage() else { fail("cannot finish an image") }
    return image
  }
}

func load(_ url: URL) -> CGImage {
  guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
  else { fail("cannot read \(url.lastPathComponent)") }
  return image
}

/// Every image goes out through here, re-encoded in sRGB with its own metadata and nothing else.
func write(_ image: CGImage, to path: String, _ about: About, jpeg quality: Double? = nil) {
  let type = quality == nil ? UTType.png : UTType.jpeg
  let url = target(path)
  guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
  else { fail("cannot write \(path)") }
  let options = properties(about)
  if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
  CGImageDestinationAddImageAndMetadata(dest, image, xmp(about), options as CFDictionary)
  guard CGImageDestinationFinalize(dest) else { fail("cannot write \(path)") }
  if quality == nil { addTextChunks(url, about) }
  described[path] = (about, image.width, image.height)
}

func resized(_ image: CGImage, width: Int) -> CGImage {
  let height = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
  let canvas = Canvas(width, height)
  canvas.draw(image, in: canvas.all)
  return canvas.image
}

func cropped(_ image: CGImage, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGImage {
  guard let part = image.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else { fail("cannot crop") }
  return part
}

func onColour(_ image: CGImage, _ colour: CGColor) -> CGImage {
  let canvas = Canvas(image.width, image.height)
  canvas.fill(canvas.all, colour)
  canvas.draw(image, in: canvas.all)
  return canvas.image
}

/// The smallest box holding every visible pixel, from the top-left.
func visibleBounds(_ image: CGImage) -> (x: Int, y: Int, w: Int, h: Int) {
  let (w, h) = (image.width, image.height)
  var px = [UInt8](repeating: 0, count: w * h * 4)
  let found: (Int, Int, Int, Int)? = px.withUnsafeMutableBytes { buffer in
    guard let ctx = CGContext(
      data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let bytes = buffer.bindMemory(to: UInt8.self)
    var (minX, minY, maxX, maxY) = (w, h, -1, -1)
    for y in 0..<h {
      for x in 0..<w where bytes[(y * w + x) * 4 + 3] > 0 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
      }
    }
    return maxX < 0 ? nil : (minX, minY, maxX - minX + 1, maxY - minY + 1)
  }
  guard let box = found else { fail("an image with nothing visible") }
  return (box.0, box.1, box.2, box.3)
}

// ---- screens --------------------------------------------------------------------------------

/// The Dynamic Island, where iOS draws it on a 3x screenshot. Screens captured without one get it.
func withIsland(_ shot: CGImage) -> CGImage {
  let canvas = Canvas(shot.width, shot.height)
  canvas.draw(shot, in: canvas.all)
  canvas.fill(canvas.rect((Double(shot.width) - 376) / 2, 42, 376, 110), radius: 55, rgb(0, 0, 0))
  return canvas.image
}

func phone(_ shot: CGImage) -> CGImage {
  let (sw, sh) = (Double(shot.width), Double(shot.height))
  let k = sw / 1320
  let (radius, bezel, rim, button) = (186 * k, 40 * k, 12 * k, 7 * k)
  let (bodyW, bodyH) = (sw + 2 * (bezel + rim), sh + 2 * (bezel + rim))
  let canvas = Canvas(Int((bodyW + 2 * button).rounded()), Int(bodyH.rounded()))
  let steel = rgb(58, 58, 64)
  for (y, h) in [(420.0, 110.0), (600, 190), (830, 190)] {
    canvas.fill(canvas.rect(0, y * k, button + 12 * k, h * k), radius: 6 * k, steel)
  }
  canvas.fill(canvas.rect(Double(canvas.width) - button - 12 * k, 700 * k, button + 12 * k, 290 * k), radius: 6 * k, steel)
  canvas.fill(canvas.rect(button, 0, bodyW, bodyH), radius: radius + bezel + rim, rgb(70, 70, 76))
  canvas.fill(canvas.rect(button + 3 * k, 3 * k, bodyW - 6 * k, bodyH - 6 * k), radius: radius + bezel + rim - 3 * k, rgb(38, 38, 42))
  canvas.fill(canvas.rect(button + rim, rim, sw + 2 * bezel, sh + 2 * bezel), radius: radius + bezel, rgb(6, 6, 8))
  canvas.draw(withIsland(shot), in: canvas.rect(button + rim + bezel, rim + bezel, sw, sh), radius: radius)
  return canvas.image
}

/// The three window buttons a capture of the Mac app's content leaves out.
func withLights(_ shot: CGImage) -> CGImage {
  let k = Double(shot.width) / 1440
  let canvas = Canvas(shot.width, shot.height)
  canvas.draw(shot, in: canvas.all)
  for (i, color) in [rgb(255, 95, 87), rgb(254, 188, 46), rgb(40, 200, 64)].enumerated() {
    let (r, x) = (6 * k, (20 + Double(i) * 20) * k)
    canvas.ctx.setFillColor(color)
    canvas.ctx.fillEllipse(in: canvas.rect(x - r, 17 * k - r, 2 * r, 2 * r))
  }
  return canvas.image
}

func window(_ shot: CGImage) -> CGImage {
  let (sw, sh) = (Double(shot.width), Double(shot.height))
  let k = sw / 1440
  let (margin, radius) = (90 * k, 16 * k)
  let canvas = Canvas(Int((sw + 2 * margin).rounded()), Int((sh + 2 * margin).rounded()))
  let frame = canvas.rect(margin, margin, sw, sh)
  canvas.ctx.saveGState()
  canvas.ctx.setShadow(offset: CGSize(width: 0, height: -26 * k), blur: 68 * k, color: CGColor(gray: 0, alpha: 0.45))
  canvas.fill(frame, radius: radius, rgb(13, 17, 21))
  canvas.ctx.restoreGState()
  canvas.draw(withLights(shot), in: frame, radius: radius)
  canvas.ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
  canvas.ctx.setStrokeColor(rgb(255, 255, 255, 0.14))
  canvas.ctx.setLineWidth(1)
  canvas.ctx.strokePath()
  return canvas.image
}

let demo = "Demo data: every name and amount is made up."
for (platform, label, screens) in [("iphone", "iPhone", kit.screens.iphone), ("mac", "Mac", kit.screens.mac)] {
  for (i, screen) in screens.enumerated() {
    let name = "longbook-\(platform)-\(String(format: "%02d", i + 1))-\(screen.slug)"
    let title = "longbook on \(label): \(screen.title)"
    let about = About(title: title, text: "\(screen.text) \(demo)", group: "screenshot-\(platform)")
    let shot = load(source("images/screenshots/\(screen.source)"))
    write(shot, to: "screenshots/\(platform)/\(name).png", about)
    let framed = About(title: "\(title), framed", text: about.text, group: "screenshot-\(platform)-framed")
    if platform == "iphone" {
      write(phone(shot), to: "screenshots/\(platform)/framed/\(name)-framed.png", framed)
      write(resized(withIsland(shot), width: 480), to: "preview/\(name).jpg", About(title: title, text: about.text, group: "preview"), jpeg: 0.78)
    } else {
      write(window(shot), to: "screenshots/\(platform)/framed/\(name)-framed.png", framed)
      // The page shows every Mac screen at the store's 16:10, from the top.
      let tall = cropped(shot, 0, 0, shot.width, min(shot.height, shot.width * 10 / 16))
      write(resized(withLights(tall), width: min(1200, tall.width)), to: "preview/\(name).jpg", About(title: title, text: about.text, group: "preview"), jpeg: 0.8)
    }
  }
}

// ---- the hero: the homepage's own device stage, captured light and dark ------------------------

for (tone, ground) in [("light", rgb(255, 255, 255)), ("dark", rgb(13, 17, 21))] {
  let capture = load(source(tone == "light" ? kit.hero.light : kit.hero.dark))
  let about = About(title: "longbook on Mac and iPhone, \(tone)", text: "\(kit.hero.text) \(demo)", group: "hero")
  write(onColour(capture, ground), to: "images/longbook-hero-\(tone).jpg", about, jpeg: 0.9)
  write(capture, to: "images/longbook-hero-\(tone)-transparent.png", about)
  if tone == "light" {
    // The page shows it up to 1210 points wide, so the preview keeps the capture's full 2x width.
    write(onColour(capture, ground), to: "preview/longbook-hero.jpg", About(title: about.title, text: about.text, group: "preview"), jpeg: 0.8)
  }
}

// ---- the founder ----------------------------------------------------------------------------

let photo = load(source(kit.founder.photo))
let person = About(title: "\(kit.founder.name), \(kit.founder.role.prefix(1).lowercased())\(kit.founder.role.dropFirst())",
                   text: kit.founder.alt, group: "founder", rights: "Photo courtesy of longbook")
let base = "longbook-founder-\(kit.founder.name.lowercased().replacingOccurrences(of: " ", with: "-"))"
write(onColour(photo, rgb(255, 255, 255)), to: "founder/\(base).jpg", person, jpeg: 0.92)
let side = min(photo.width, photo.height)
let left = max(0, min(photo.width - side, Int(Double(photo.width) * kit.founder.faceCentre) - side / 2))
let square = onColour(cropped(photo, left, 0, side, side), rgb(255, 255, 255))
write(square, to: "founder/\(base)-square.jpg", person, jpeg: 0.92)
write(resized(square, width: 640), to: "preview/\(base).jpg", About(title: person.title, text: person.text, group: "preview", rights: person.rights), jpeg: 0.85)
// The home page's "Why I built longbook" shows the same photo, small.
write(resized(square, width: 320), to: "preview/\(base)-320.jpg", About(title: person.title, text: person.text, group: "preview", rights: person.rights), jpeg: 0.82)

// ---- the logo -------------------------------------------------------------------------------

func logoAbout(_ file: String) -> About {
  guard let logo = kit.logos.first(where: { $0.files.contains { $0.file == file } }) else { fail("\(file) is not in kit.json") }
  return About(title: "longbook: \(logo.title)", text: "\(logo.text) \(kit.usage)", group: "logo")
}

let iconSVG = source("apps/longbook-site/logo.svg")
let logo = String(decoding: (try? Data(contentsOf: iconSVG)) ?? Data(), as: UTF8.self)
func matches(_ pattern: String) -> [String] {
  guard let re = try? NSRegularExpression(pattern: pattern) else { fail("bad pattern") }
  return re.matches(in: logo, range: NSRange(logo.startIndex..., in: logo)).compactMap {
    Range($0.range, in: logo).map { String(logo[$0]) }
  }
}
guard let defs = matches(#"<defs>[\s\S]*?</defs>"#).first else { fail("logo.svg has no <defs>") }
let bookPaths = matches(#"<path[^>]*/>"#).joined(separator: "\n")
// The book's extent inside the 512 icon, measured from its path data.
let (bookX, bookY, bookW, bookH) = (138.1, 59.5, 244.2, 393.0)

func number(_ v: Double) -> String { String(format: "%.1f", v) }

func escaped(_ s: String) -> String {
  s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}

/// An SVG's title, description and Dublin Core record, written where every reader looks for them.
func svgHead(_ about: About) -> String {
  """
  <title>\(escaped(about.title))</title>
  <desc>\(escaped(about.text))</desc>
  <metadata><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:dc="http://purl.org/dc/elements/1.1/"><rdf:Description rdf:about="">\
  <dc:title>\(escaped(about.title))</dc:title><dc:description>\(escaped(about.text))</dc:description>\
  <dc:creator>\(escaped(kit.credit))</dc:creator><dc:rights>\(escaped(about.rights))</dc:rights>\
  <dc:source>\(origin)</dc:source></rdf:Description></rdf:RDF></metadata>
  """
}

func svg(_ body: String, viewBox: (Double, Double, Double, Double), to path: String) {
  let about = logoAbout("logo/" + path)
  let text = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="\(number(viewBox.0)) \(number(viewBox.1)) \(number(viewBox.2)) \(number(viewBox.3))">
    \(svgHead(about))
    \(body)
    </svg>

    """
  do { try Data(text.utf8).write(to: target("logo/" + path)) } catch { fail("cannot write \(path)") }
  described["logo/" + path] = (about, Int(viewBox.2.rounded()), Int(viewBox.3.rounded()))
}

/// "longbook" in Fraunces as the site header sets it: weight 560, optical size 16.
func wordmark(size: CGFloat) -> (path: CGPath, bounds: CGRect, ascent: CGFloat, descent: CGFloat) {
  let url = source("apps/longbook-site/fonts/Fraunces-Variable.woff2")
  guard let base = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
  else { fail("cannot read Fraunces") }
  let axes: [NSNumber: NSNumber] = [NSNumber(value: 0x7767_6874): 560, NSNumber(value: 0x6F70_737A): 16]
  let desc = CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute as String: axes] as CFDictionary)
  let font = CTFontCreateWithFontDescriptor(desc, size, nil)
  let line = CTLineCreateWithAttributedString(
    NSAttributedString(string: "longbook", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
  let path = CGMutablePath()
  for glyphRun in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
    let n = CTRunGetGlyphCount(glyphRun)
    var glyphs = [CGGlyph](repeating: 0, count: n)
    var points = [CGPoint](repeating: .zero, count: n)
    CTRunGetGlyphs(glyphRun, CFRange(location: 0, length: n), &glyphs)
    CTRunGetPositions(glyphRun, CFRange(location: 0, length: n), &points)
    for i in 0..<n {
      var move = CGAffineTransform(translationX: points[i].x, y: points[i].y)
      if let glyph = CTFontCreatePathForGlyph(font, glyphs[i], &move) { path.addPath(glyph) }
    }
  }
  return (path, CTLineGetBoundsWithOptions(line, .useGlyphPathBounds), CTFontGetAscent(font), CTFontGetDescent(font))
}

func svgPath(_ path: CGPath) -> String {
  var d = ""
  path.applyWithBlock { element in
    let p = element.pointee.points
    func xy(_ i: Int) -> String { "\(number(p[i].x)) \(number(-p[i].y))" }
    switch element.pointee.type {
    case .moveToPoint: d += "M" + xy(0)
    case .addLineToPoint: d += "L" + xy(0)
    case .addQuadCurveToPoint: d += "Q" + xy(0) + " " + xy(1)
    case .addCurveToPoint: d += "C" + xy(0) + " " + xy(1) + " " + xy(2)
    case .closeSubpath: d += "Z"
    @unknown default: break
    }
  }
  return d
}

// The lockup follows the site header: the book 1.5 times the type size, centred on the line
// box, then a gap of 0.72 of the size before the wordmark.
let unit: CGFloat = 1000
let vector = wordmark(size: unit)
let scale = 1.5 * unit / bookH
let lockTop = -(vector.ascent - vector.descent) / 2 - 0.75 * unit
let textLeft = bookW * scale + 0.72 * unit
let lockRight = textLeft + vector.bounds.width
let lockBottom = max(lockTop + 1.5 * unit, -vector.bounds.minY)
for (name, ink) in [("on-dark", "#FFFFFF"), ("on-light", "#26241F")] {
  svg("""
    \(defs)
    <g transform="translate(0 \(number(lockTop))) scale(\(String(format: "%.5f", scale))) translate(\(-bookX) \(-bookY))">
    \(bookPaths)
    </g>
    <path fill="\(ink)" transform="translate(\(number(textLeft - vector.bounds.minX)) 0)" d="\(svgPath(vector.path))"/>
    """, viewBox: (0, lockTop, lockRight, lockBottom - lockTop), to: "longbook-logo-\(name).svg")
}

let mark = load(source("images/brand/longbook_icon_nobackground.png"))
let box = visibleBounds(mark)
let book = cropped(mark, box.x, box.y, box.w, box.h)
let px: CGFloat = 400
let raster = wordmark(size: px)
let (rasterBookH, gap) = (1.5 * px, (0.72 * px).rounded())
let rasterBookW = (CGFloat(book.width) * rasterBookH / CGFloat(book.height)).rounded()
let baseline = (raster.ascent - raster.descent) / 2 + rasterBookH / 2
let lockW = Int((rasterBookW + gap + raster.bounds.width + 4).rounded(.up))
let lockH = Int(max(rasterBookH, baseline - raster.bounds.minY + 2).rounded(.up))
for (name, ink) in [("on-dark", rgb(255, 255, 255)), ("on-light", rgb(38, 36, 31))] {
  let canvas = Canvas(lockW, lockH)
  canvas.draw(book, in: canvas.rect(0, 0, rasterBookW, rasterBookH))
  canvas.ctx.saveGState()
  canvas.ctx.translateBy(x: rasterBookW + gap - raster.bounds.minX, y: CGFloat(lockH) - baseline)
  canvas.ctx.addPath(raster.path)
  canvas.ctx.setFillColor(ink)
  canvas.ctx.fillPath()
  canvas.ctx.restoreGState()
  write(canvas.image, to: "logo/longbook-logo-\(name).png", logoAbout("logo/longbook-logo-\(name).png"))
}

// The app icon's square SVG is the site's own logo.svg with this file's title and record in place.
let iconBody = logo.replacingOccurrences(of: #"^[\s\S]*?<title>longbook</title>\s*"#, with: "", options: .regularExpression)
  .replacingOccurrences(of: #"</svg>\s*$"#, with: "", options: .regularExpression)
svg(iconBody.trimmingCharacters(in: .whitespacesAndNewlines), viewBox: (0, 0, 512, 512), to: "longbook-app-icon.svg")
let icon = load(source("images/brand/longbook_icon.png"))
write(resized(icon, width: 1024), to: "logo/longbook-app-icon-1024.png", logoAbout("logo/longbook-app-icon-1024.png"))
write(resized(icon, width: 512), to: "logo/longbook-app-icon-512.png", logoAbout("logo/longbook-app-icon-512.png"))
svg("\(defs)\n\(bookPaths)", viewBox: (bookX - 2, bookY - 2, bookW + 4, bookH + 4), to: "longbook-mark.svg")
write(book, to: "logo/longbook-mark.png", logoAbout("logo/longbook-mark.png"))
let glyph = load(source("images/brand/macOS_menu_bar.png"))
write(glyph, to: "logo/longbook-mark-black.png", logoAbout("logo/longbook-mark-black.png"))
let white = Canvas(glyph.width, glyph.height)
white.draw(glyph, in: white.all)
white.ctx.setBlendMode(.sourceIn)
white.fill(white.all, rgb(255, 255, 255))
write(white.image, to: "logo/longbook-mark-white.png", logoAbout("logo/longbook-mark-white.png"))

for logo in kit.logos {
  for file in logo.files where described[file.file] == nil { fail("kit.json names \(file.file), which nothing built") }
}

// ---- the list -------------------------------------------------------------------------------

let prefix = out.path + "/"
guard let walker = fm.enumerator(at: out, includingPropertiesForKeys: [.isRegularFileKey]) else { fail("cannot list the files") }
var rows: [[String: Any]] = []
for case let url as URL in walker {
  guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
    url.lastPathComponent != ".DS_Store",
    let data = try? Data(contentsOf: url)
  else { continue }
  let path = url.standardizedFileURL.path.replacingOccurrences(of: prefix, with: "")
  guard let info = described[path] else { fail("\(path) was built without a description") }
  let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
  rows.append([
    "path": path, "url": origin + "files/" + path, "type": type, "bytes": data.count,
    "width": info.width, "height": info.height, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
    "title": info.about.title, "description": info.about.text, "group": info.about.group, "rights": info.about.rights,
  ])
}
rows.sort { ($0["path"] as? String ?? "") < ($1["path"] as? String ?? "") }
let isPreview = { (row: [String: Any]) -> Bool in (row["path"] as? String ?? "").hasPrefix("preview/") }
let list: [String: Any] = [
  "about": "Every file in the longbook media kit, with its size, dimensions and SHA-256. The page: \(origin)",
  "files": rows.filter { !isPreview($0) }, "preview": rows.filter(isPreview),
]
guard let json = try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
else { fail("cannot write files.json") }
do { try (json + Data("\n".utf8)).write(to: site.appendingPathComponent("files.json")) } catch { fail("cannot write files.json") }

let downloads = rows.filter { !isPreview($0) }
let megabytes = Double(downloads.reduce(0) { $0 + ($1["bytes"] as? Int ?? 0) }) / 1_000_000
print("media-kit — \(downloads.count) downloads (\(String(format: "%.1f", megabytes)) MB) and \(rows.count - downloads.count) page images")
print("  built into apps/longbook-site/media-kit/files; listed in media-kit/files.json")
