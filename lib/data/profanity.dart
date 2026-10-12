/// A basic list of vulgar / abusive words used to warn a user before they send
/// a message that could get them into trouble. This is intentionally a simple
/// client-side check — a warning, not censorship. It is not exhaustive.
const Set<String> _kProfanity = {
  'fuck', 'fucking', 'fucker', 'motherfucker', 'shit', 'bullshit', 'bitch',
  'bastard', 'asshole', 'arsehole', 'dick', 'dickhead', 'prick', 'cock',
  'pussy', 'cunt', 'slut', 'whore', 'wanker', 'twat', 'bollocks',
  'nigger', 'nigga', 'faggot', 'retard', 'rape', 'raping', 'rapist',
  'kill you', 'kill yourself', 'kys',
};

/// Stems that are vulgar in ANY form, so every word starting with them is
/// flagged ("fucks", "fucked", "fuckin", "shitty", "bitches", "wankers"...).
/// Only stems with no innocent words starting with them belong here — "dick",
/// "cock", "prick" and "rape" are NOT stems (dickens, cockpit, prickly,
/// rapeseed), they only match whole words plus a plural "s".
const List<String> _kStems = [
  'fuck', 'motherfuck', 'shit', 'bullshit', 'bitch', 'cunt', 'wank', 'whore',
  'slut', 'nigg', 'fagg', 'bastard', 'asshole', 'arsehole', 'bollock',
  'dickhead',
];

/// Common disguised spellings, matched as whole words.
const Set<String> _kVariants = {'fck', 'fcking', 'fuk', 'fuking', 'fuq', 'stfu'};

/// Returns the offending words/phrases found in [text] (empty if clean).
/// Matching is case-insensitive. Single words match whole-word, plus their
/// plural, plus anything starting with a vulgar stem; "f*ck"-style asterisks
/// are ignored. Multi-word phrases (e.g. "kill you") match as substrings.
List<String> profanityIn(String text) {
  // Drop asterisks/dots used to disguise words ("f*ck", "sh.t" stays split).
  final lower = text.toLowerCase().replaceAll('*', '');
  // Split into word tokens for whole-word matching.
  final tokens = lower.split(RegExp(r"[^a-z']+")).where((w) => w.isNotEmpty).toSet();
  final hits = <String>{};
  for (final bad in _kProfanity) {
    if (bad.contains(' ')) {
      // Phrase — substring match.
      if (lower.contains(bad)) hits.add(bad);
    } else if (tokens.contains(bad) || tokens.contains('${bad}s')) {
      hits.add(bad);
    }
  }
  for (final t in tokens) {
    if (_kVariants.contains(t) || _kStems.any(t.startsWith)) hits.add(t);
  }
  return hits.toList();
}

/// Whether [text] contains any flagged word.
bool hasProfanity(String text) => profanityIn(text).isNotEmpty;
