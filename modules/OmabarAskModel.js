// What the Ask box does with a question: which chat site it opens, with the
// question already in the link where the site takes one, or on the clipboard
// where it doesn't. Kept apart from the QML so tests/test_ask_model.py can run
// it under node.

// Each provider's normal chat page (not a coding tool).
//   name       - what the chip says
//   full       - the product's full name, for notices
//   prefill    - link that opens a new chat with the question filled in ("" if none)
//   home       - page to open when the question goes on the clipboard instead
//   sends      - whether the prefilled link sends the question by itself
//
// Claude Duet and ChatGPT Dots are agents with no link that carries a
// question, so they get the clipboard; their page can be set with the
// "links" setting once you know the address you use.
var PROVIDERS = [
  { id: "claude",  name: "Claude",  full: "Claude",       prefill: "https://claude.ai/new?q=", home: "https://claude.ai/new",         sends: false },
  { id: "chatgpt", name: "ChatGPT", full: "ChatGPT",      prefill: "https://chatgpt.com/?q=",  home: "https://chatgpt.com/",          sends: true  },
  { id: "gemini",  name: "Gemini",  full: "Gemini",       prefill: "",                         home: "https://gemini.google.com/app", sends: false },
  { id: "grok",    name: "Grok",    full: "Grok",         prefill: "https://grok.com/?q=",     home: "https://grok.com/",             sends: true  },
  { id: "duet",    name: "Duet",    full: "Claude Duet",  prefill: "",                         home: "https://claude.ai/",            sends: false },
  { id: "dot",     name: "Dot",     full: "ChatGPT Dot",  prefill: "",                         home: "https://chatgpt.com/",          sends: false }
]

// Links longer than this go wrong on some sites (cut short, or refused), so a
// longer question goes on the clipboard instead.
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

// { url, copy, sends, name }: open `url`; if `copy` is set, put the question on
// the clipboard first, because the link can't carry it.
// `links` (optional, from the bar setting) maps an id to the page to open for
// it instead of the usual one, e.g. { duet: "https://claude.ai/…" }.
function plan(id, text, links) {
  var p = provider(id)
  var own = links && typeof links === "object" && typeof links[p.id] === "string" && /^https:\/\//.test(links[p.id]) ? links[p.id] : ""
  var question = clean(text)
  if (!question) return null
  if (p.prefill && !own) {
    var url = p.prefill + encodeURIComponent(question)
    if (url.length <= MAX_LINK) return { url: url, copy: false, sends: p.sends, name: p.full }
  }
  return { url: own || p.home, copy: true, sends: false, name: p.full }
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
  module.exports = { PROVIDERS: PROVIDERS, provider: provider, providerIds: providerIds, shown: shown, clean: clean, plan: plan, remember: remember }
}
