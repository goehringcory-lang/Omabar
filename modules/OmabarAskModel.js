// What the Ask box does with a question: which chat site it opens and how the
// question gets asked there. Kept apart from the QML so
// tests/test_ask_model.py can run it under node.

// Each provider's normal chat page (not a coding tool).
//   name    - what the chip says
//   full    - the product's full name, for notices
//   prefill - link that opens a new chat with the question in it ("" if none)
//   home    - page to open when the question is pasted in instead
//   sends   - whether the prefilled link sends the question by itself; if
//             not, bin/omabar-ask presses Enter once the page is up
//   title   - a word in the browser window's title once the site is open,
//             so keys are only ever sent to it
//
// Gemini, Claude Duet and ChatGPT Dots have no link that carries a question,
// so bin/omabar-ask pastes it into the chat box and presses Enter. Duet's and
// Dot's page can be set with the "links" setting.
var PROVIDERS = [
  { id: "claude",  name: "Claude",  full: "Claude",      prefill: "https://claude.ai/new?q=", home: "https://claude.ai/new",         sends: false, title: "Claude" },
  { id: "chatgpt", name: "ChatGPT", full: "ChatGPT",     prefill: "https://chatgpt.com/?q=",  home: "https://chatgpt.com/",          sends: true,  title: "ChatGPT" },
  { id: "gemini",  name: "Gemini",  full: "Gemini",      prefill: "",                         home: "https://gemini.google.com/app", sends: false, title: "Gemini" },
  { id: "grok",    name: "Grok",    full: "Grok",        prefill: "https://grok.com/?q=",     home: "https://grok.com/",             sends: true,  title: "Grok" },
  { id: "duet",    name: "Duet",    full: "Claude Duet", prefill: "",                         home: "https://claude.ai/",            sends: false, title: "Claude" },
  { id: "dot",     name: "Dot",     full: "ChatGPT Dot", prefill: "",                         home: "https://chatgpt.com/",          sends: false, title: "ChatGPT" }
]

// How many pictures one question can carry. Every site takes at least this
// many in one message.
var MAX_PICTURES = 4

// Links longer than this go wrong on some sites (cut short, or refused), so a
// longer question is pasted in instead.
var MAX_LINK = 6000

function provider(id) {
  for (var i = 0; i < PROVIDERS.length; i++) if (PROVIDERS[i].id === id) return PROVIDERS[i]
  return PROVIDERS[0]
}

function providerIds() {
  var out = []
  for (var i = 0; i < PROVIDERS.length; i++) out.push(PROVIDERS[i].id)
  return out
}

// The order the chips show in: the ones named in `only` (a list of ids, from
// the bar setting), else all of them.
function shown(only) {
  if (!Array.isArray(only) || only.length === 0) return PROVIDERS.slice()
  var out = []
  for (var i = 0; i < only.length; i++) {
    var id = String(only[i]).toLowerCase()
    for (var j = 0; j < PROVIDERS.length; j++) {
      if (PROVIDERS[j].id === id && out.indexOf(PROVIDERS[j]) === -1) out.push(PROVIDERS[j])
    }
  }
  return out.length ? out : PROVIDERS.slice()
}

function clean(text) {
  return String(text === undefined || text === null ? "" : text).replace(/\r\n?/g, "\n").trim()
}

// { url, mode, title, name } for bin/omabar-ask: open `url`, then
//   "link"  - nothing more (the link asks it)
//   "enter" - press Enter (the link filled it in)
//   "paste" - paste the question (and any pictures) into the chat box and
//             press Enter
// `links` (optional, from the bar setting) maps an id to the page to open for
// it instead of the usual one, e.g. { duet: "https://claude.ai/…" }.
// `pictures` is how many pictures go with it; a picture can't travel in a
// link, so a question with pictures is always pasted in, and a picture on its
// own (no text) is a question too.
function plan(id, text, links, pictures) {
  var p = provider(id)
  var own = links && typeof links === "object" && typeof links[p.id] === "string" && /^https:\/\//.test(links[p.id]) ? links[p.id] : ""
  var question = clean(text)
  var withPictures = Number(pictures) > 0
  if (!question && !withPictures) return null
  if (p.prefill && !own && !withPictures) {
    var url = p.prefill + encodeURIComponent(question)
    if (url.length <= MAX_LINK) return { url: url, mode: p.sends ? "link" : "enter", title: p.title, name: p.full }
  }
  return { url: own || p.home, mode: "paste", title: p.title, name: p.full }
}

// Adds a pasted picture's path to the list, up to MAX_PICTURES, without
// repeats. Returns the new list.
function addPicture(list, path) {
  var out = Array.isArray(list) ? list.slice() : []
  path = String(path || "").trim()
  if (!path || out.indexOf(path) !== -1 || out.length >= MAX_PICTURES) return out
  out.push(path)
  return out
}

// Keeps the last few questions, newest first, without repeats.
function remember(history, text, keep) {
  var question = clean(text)
  var list = Array.isArray(history) ? history.slice() : []
  if (!question) return list
  var at = list.indexOf(question)
  if (at !== -1) list.splice(at, 1)
  list.unshift(question)
  return list.slice(0, keep || 20)
}

if (typeof module !== "undefined") {
  module.exports = { PROVIDERS: PROVIDERS, MAX_PICTURES: MAX_PICTURES, addPicture: addPicture, provider: provider, providerIds: providerIds, shown: shown, clean: clean, plan: plan, remember: remember }
}
