import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'ledger.dart';
import 'models.dart';
import 'utils.dart';

const _w = [
  'শূন্য',
  'এক',
  'দুই',
  'তিন',
  'চার',
  'পাঁচ',
  'ছয়',
  'সাত',
  'আট',
  'নয়',
  'দশ',
  'এগারো',
  'বারো',
  'তেরো',
  'চৌদ্দ',
  'পনেরো',
  'ষোলো',
  'সতেরো',
  'আঠারো',
  'ঊনিশ',
  'বিশ',
  'একুশ',
  'বাইশ',
  'তেইশ',
  'চব্বিশ',
  'পঁচিশ',
  'ছাব্বিশ',
  'সাতাশ',
  'আটাশ',
  'ঊনত্রিশ',
  'ত্রিশ',
  'একত্রিশ',
  'বত্রিশ',
  'তেত্রিশ',
  'চৌত্রিশ',
  'পঁয়ত্রিশ',
  'ছত্রিশ',
  'সাঁইত্রিশ',
  'আটত্রিশ',
  'ঊনচল্লিশ',
  'চল্লিশ',
  'একচল্লিশ',
  'বিয়াল্লিশ',
  'তেতাল্লিশ',
  'চুয়াল্লিশ',
  'পঁয়তাল্লিশ',
  'ছেচল্লিশ',
  'সাতচল্লিশ',
  'আটচল্লিশ',
  'ঊনপঞ্চাশ',
  'পঞ্চাশ',
  'একান্ন',
  'বাহান্ন',
  'তিপ্পান্ন',
  'চুয়ান্ন',
  'পঞ্চান্ন',
  'ছাপ্পান্ন',
  'সাতান্ন',
  'আটান্ন',
  'ঊনষাট',
  'ষাট',
  'একষট্টি',
  'বাষট্টি',
  'তেষট্টি',
  'চৌষট্টি',
  'পঁয়ষট্টি',
  'ছেষট্টি',
  'সাতষট্টি',
  'আটষট্টি',
  'ঊনসত্তর',
  'সত্তর',
  'একাত্তর',
  'বাহাত্তর',
  'তিয়াত্তর',
  'চুয়াত্তর',
  'পঁচাত্তর',
  'ছিয়াত্তর',
  'সাতাত্তর',
  'আটাত্তর',
  'ঊনআশি',
  'আশি',
  'একাশি',
  'বিরাশি',
  'তিরাশি',
  'চুরাশি',
  'পঁচাশি',
  'ছিয়াশি',
  'সাতাশি',
  'আটাশি',
  'ঊননব্বই',
  'নব্বই',
  'একানব্বই',
  'বিরানব্বই',
  'তিরানব্বই',
  'চুরানব্বই',
  'পঁচানব্বই',
  'ছিয়ানব্বই',
  'সাতানব্বই',
  'আটানব্বই',
  'নিরানব্বই',
];

/// সংখ্যা → বাংলা কথা (যেমন ৪৫০০ → "চার হাজার পাঁচশো")। কোটি পর্যন্ত।
String banglaWords(int n) {
  if (n == 0) return _w[0];
  final parts = <String>[];
  var r = n;
  void unit(int size, String name) {
    final q = r ~/ size;
    if (q > 0) {
      parts.add('${banglaWords(q)} $name');
      r %= size;
    }
  }

  unit(10000000, 'কোটি');
  unit(100000, 'লক্ষ');
  unit(1000, 'হাজার');
  final h = r ~/ 100;
  if (h > 0) {
    parts.add('${_w[h]}শো');
    r %= 100;
  }
  if (r > 0) parts.add(_w[r]);
  return parts.join(' ');
}

/// টাকার অঙ্ক কথায়, পয়সা থাকলে সেটাও ("দুই হাজার টাকা পঞ্চাশ পয়সা")।
String takaWords(num amount) {
  final v = amount.abs();
  final whole = v.floor();
  final paisa = ((v - whole) * 100).round();
  final t = '${banglaWords(whole)} টাকা';
  return paisa > 0 ? '$t ${banglaWords(paisa)} পয়সা' : t;
}

// ---------- ইংরেজি অক্ষরের নাম → বাংলা অক্ষর (শুধু পড়ার জন্য) ----------

/// নামে প্রায়ই আসে এমন শব্দ, যেগুলো নিয়মে ঠিক আসে না।
const _phoneticWords = {
  'md': 'মোহাম্মদ',
  'mohammad': 'মোহাম্মদ',
  'muhammad': 'মুহাম্মদ',
  'mst': 'মোসাম্মৎ',
  'store': 'স্টোর',
  'stores': 'স্টোর',
  'shop': 'শপ',
  'traders': 'ট্রেডার্স',
  'enterprise': 'এন্টারপ্রাইজ',
  'bhai': 'ভাই',
  'uncle': 'আঙ্কেল',
  'aunty': 'আন্টি',
  'sir': 'স্যার',
  'madam': 'ম্যাডাম',
  'boss': 'বস',
  'new': 'নিউ',
  'and': 'অ্যান্ড',
};

const _consonants = {
  'chh': 'ছ',
  'kh': 'খ',
  'gh': 'ঘ',
  'ng': 'ং',
  'ch': 'চ',
  'jh': 'ঝ',
  'th': 'থ',
  'dh': 'ধ',
  'ph': 'ফ',
  'bh': 'ভ',
  'sh': 'শ',
  'k': 'ক',
  'g': 'গ',
  'c': 'ক',
  'j': 'জ',
  't': 'ত',
  'd': 'দ',
  'n': 'ন',
  'p': 'প',
  'f': 'ফ',
  'b': 'ব',
  'm': 'ম',
  'r': 'র',
  'l': 'ল',
  's': 'স',
  'h': 'হ',
  'z': 'জ',
  'x': 'ক্স',
  'v': 'ভ',
  'q': 'ক',
};

/// (স্বাধীন রূপ, কার)
const _vowels = {
  'ee': ('ঈ', 'ী'),
  'oo': ('উ', 'ু'),
  'ou': ('ঔ', 'ৌ'),
  'oi': ('ঐ', 'ৈ'),
  'ai': ('আই', 'াই'),
  'a': ('আ', 'া'),
  'i': ('ই', 'ি'),
  'u': ('উ', 'ু'),
  'e': ('এ', 'ে'),
  'o': ('ও', 'ো'),
};

String? _match(String w, int i, Map<String, Object> table) {
  for (var len = 3; len >= 1; len--) {
    if (i + len > w.length) continue;
    final k = w.substring(i, i + len);
    if (table.containsKey(k)) return k;
  }
  return null;
}

/// একটা ইংরেজি শব্দকে উচ্চারণ অনুযায়ী বাংলা অক্ষরে — Bablu → বাব্লু।
String _phoneticWord(String word) {
  final w = word.toLowerCase();
  final known = _phoneticWords[w];
  if (known != null) return known;
  final out = StringBuffer();
  // ব্যঞ্জনের পরে: পরের ব্যঞ্জনে যুক্তাক্ষর, পরের স্বরে কার
  var afterConsonant = false;
  // য়-এর পরে: পরের স্বরে কার, কিন্তু ব্যঞ্জনে যুক্তাক্ষর নয় (Rayhan → রায়হান)
  var afterYa = false;
  var i = 0;
  while (i < w.length) {
    final v = _match(w, i, _vowels);
    if (v != null) {
      final (alone, kar) = _vowels[v]!;
      out.write(afterConsonant || afterYa ? kar : alone);
      afterConsonant = afterYa = false;
      i += v.length;
      continue;
    }
    final ch = w[i];
    final nextIsVowel = i + 1 < w.length && _match(w, i + 1, _vowels) != null;
    if (ch == 'y' && afterConsonant) {
      out.write('্য'); // য-ফলা
      afterConsonant = false;
      afterYa = true;
      i++;
      continue;
    }
    if (ch == 'w' && afterConsonant && i > 0 && w[i - 1] == 's') {
      out.write('্ব'); // Swapan → স্বপন
      afterConsonant = false;
      afterYa = true;
      i++;
      continue;
    }
    if (ch == 'y' || ch == 'w') {
      // Wahid → ওয়াহিদ, Anwar → আনওয়ার, Jewel → জেওয়েল
      out.write(ch == 'w' && nextIsVowel ? 'ওয়' : (ch == 'w' ? 'ও' : 'য়'));
      afterConsonant = false;
      afterYa = ch == 'y' || nextIsVowel;
      i++;
      continue;
    }
    final c = _match(w, i, _consonants);
    if (c == null) {
      out.write(ch);
      afterConsonant = afterYa = false;
      i++;
      continue;
    }
    if (afterConsonant && c != 'ng') out.write('্'); // যুক্তাক্ষর
    out.write(_consonants[c]);
    afterConsonant = c != 'ng';
    afterYa = false;
    i += c.length;
  }
  return out.toString();
}

/// লেখার ভেতরের ইংরেজি শব্দগুলো বাংলা অক্ষরে, যাতে বাংলা ভয়েস ভেঙে না পড়ে।
String banglaForSpeech(String text) =>
    text.replaceAllMapped(RegExp(r'[A-Za-z]+'), (m) => _phoneticWord(m[0]!));

/// ফোনের নিজস্ব TTS দিয়ে পুরোটা বাংলা ভয়েসে পড়ে শোনায় — ইংরেজিতে লেখা নামও।
/// (নামগুলো ইংরেজি ভয়েসে পড়লে তালিকা শুনতে অদ্ভুত লাগে।)
/// ইন্টারনেট লাগে না (বাংলা ভয়েস ফোনে থাকলে)।
class Voice {
  Voice._();
  static final Voice instance = Voice._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  static const _languages = ['bn-BD', 'bn-IN', 'bn'];
  static const _googleEngine = 'com.google.android.tts';

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      var lang = await _banglaLanguage();
      // ফোনের ডিফল্ট ইঞ্জিনে (যেমন Samsung) বাংলা না থাকলে Google-এরটায় যাওয়া
      if (lang == null && defaultTargetPlatform == TargetPlatform.android) {
        final engines = await _tts.getEngines;
        if (engines is List && engines.contains(_googleEngine)) {
          await _tts.setEngine(_googleEngine);
          lang = await _banglaLanguage();
        }
      }
      if (lang == null) return false;
      await _tts.setLanguage(lang);
      await _pickBanglaVoice(lang);
      await _tts.setSpeechRate(0.45);
      await _tts.awaitSpeakCompletion(true);
      _ready = true;
    } catch (_) {
      return false;
    }
    return true;
  }

  Future<String?> _banglaLanguage() async {
    for (final l in _languages) {
      if (await _tts.isLanguageAvailable(l) == true) return l;
    }
    return null;
  }

  /// ইঞ্জিনের ডিফল্ট ভয়েস অনেক সময় বাংলা হয় না — নিজে বাংলা ভয়েস বাছাই,
  /// ঠিক লোকেলের আর অফলাইনেরটা আগে।
  Future<void> _pickBanglaVoice(String lang) async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) return;
      String locale(Map v) => '${v['locale']}'.replaceAll('_', '-');
      final bangla = [
        for (final v in voices)
          if (v is Map && locale(v).toLowerCase().startsWith('bn')) v,
      ];
      if (bangla.isEmpty) return;
      int score(Map v) =>
          (locale(v) == lang ? 2 : 0) + (v['network_required'] == '1' ? 0 : 1);
      bangla.sort((a, b) => score(b).compareTo(score(a)));
      final v = bangla.first;
      await _tts.setVoice({'name': '${v['name']}', 'locale': '${v['locale']}'});
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  static const noVoiceMsg =
      'এই ফোনে বাংলা ভয়েস নেই। ফোনের সেটিংসে Google Text-to-speech-এ বাংলা ভয়েস ডাউনলোড করুন';

  /// পড়া শেষ হওয়া (বা থামানো) পর্যন্ত অপেক্ষা করে। বাংলা ভয়েস না থাকলে
  /// বা ত্রুটি হলে false।
  Future<bool> speak(String text) async {
    if (kIsWeb || !await _init()) return false;
    try {
      await _tts.speak(banglaForSpeech(text));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// পড়ে শোনায়। বাংলা ভয়েস না থাকলে বা ত্রুটি হলে বার্তা দেখায়।
  Future<void> say(BuildContext context, String text) async {
    if (kIsWeb) return;
    await stop();
    if (!await _init()) {
      if (context.mounted) toast(context, noVoiceMsg);
      return;
    }
    if (!await speak(text) && context.mounted) {
      toast(context, 'ভয়েস চালানো যায়নি');
    }
  }
}

/// একজন কাস্টমার/পাওনাদারের বাকির কথা।
String customerSpeech(Customer c) {
  final pabo = c.ledger == Ledger.pabo;
  if (!c.hasDue) {
    return pabo
        ? '${c.name}-এর কাছে আপনার কোনো পাওনা নেই।'
        : '${c.name}-কে আপনার কোনো টাকা দিতে হবে না।';
  }
  final amount = takaWords(c.balance);
  final base = pabo
      ? '${c.name}-এর কাছে আপনার $amount পাওনা আছে।'
      : '${c.name}-কে আপনাকে $amount দিতে হবে।';
  if (c.dueDate == null) return base;
  final d = daysUntil(c.dueDate!);
  final when = d < 0
      ? 'মেয়াদ ${banglaWords(-d)} দিন আগে পার হয়ে গেছে।'
      : d == 0
      ? 'আজই ${pabo ? 'আদায়ের' : 'পরিশোধের'} দিন।'
      : '${banglaWords(d)} দিন পর ${pabo ? 'আদায়ের' : 'পরিশোধের'} মেয়াদ।';
  return '$base $when';
}

/// হোমের সারাংশ।
String summarySpeech({
  required Ledger ledger,
  required double total,
  required int people,
  required double overdue,
  required double collectedToday,
}) {
  final pabo = ledger == Ledger.pabo;
  if (total < 0.01) {
    return pabo ? 'আপনার কোনো পাওনা বাকি নেই।' : 'আপনার কোনো দেনা বাকি নেই।';
  }
  final parts = <String>[
    pabo
        ? 'মোট পাওনা ${takaWords(total)}, ${banglaWords(people)} জনের কাছে।'
        : 'মোট দেনা ${takaWords(total)}, ${banglaWords(people)} জনকে দিতে হবে।',
    if (overdue >= 0.01) 'এর মধ্যে মেয়াদ পার হয়েছে ${takaWords(overdue)}।',
    if (collectedToday >= 0.01)
      'আজ ${pabo ? 'আদায়' : 'পরিশোধ'} হয়েছে ${takaWords(collectedToday)}।',
  ];
  return parts.join(' ');
}

// ---------- ভয়েস ইনপুট (বলে লেখা) ----------

const _unit = {'কোটি': 10000000, 'লক্ষ': 100000, 'লাখ': 100000, 'হাজার': 1000};

/// বলা কথা থেকে টাকার অঙ্ক: "৫০০", "500", "চার হাজার পাঁচশো", "দুই লাখ"। না বুঝলে null।
double? parseSpokenAmount(String text) {
  final t = toEnDigits(text).replaceAll(',', '');
  final digits = RegExp(r'\d+(\.\d+)?').firstMatch(t);
  if (digits != null) return double.tryParse(digits.group(0)!);

  final word = <String, int>{
    for (var i = 0; i < _w.length; i++) _w[i]: i,
    'দুই': 2,
    'দু': 2,
    'আঠার': 18,
    'ষোল': 16,
    'পনের': 15,
    'তের': 13,
    'বার': 12,
    'এগার': 11,
  };
  var total = 0, current = 0;
  var any = false;
  for (var tok in t.split(RegExp(r'\s+'))) {
    if (tok.isEmpty) continue;
    if (_unit.containsKey(tok)) {
      total += (current == 0 ? 1 : current) * _unit[tok]!;
      current = 0;
      any = true;
    } else if (tok == 'শো' || tok == 'শ') {
      current = (current == 0 ? 1 : current) * 100;
      any = true;
    } else if (tok.endsWith('শো') &&
        word.containsKey(tok.substring(0, tok.length - 2))) {
      current += word[tok.substring(0, tok.length - 2)]! * 100;
      any = true;
    } else if (word.containsKey(tok)) {
      current += word[tok]!;
      any = true;
    }
  }
  return any ? (total + current).toDouble() : null;
}

/// মাইক বাটন: চাপলে শোনা শুরু, আবার চাপলে থামে। বলা কথা [onText]-এ আসে।
class MicButton extends StatefulWidget {
  const MicButton({super.key, required this.onText, this.onFinal, this.color});

  /// চলতি (আংশিক) ও শেষ ফলাফল।
  final ValueChanged<String> onText;

  /// শুধু শেষ ফলাফল।
  final ValueChanged<String>? onFinal;
  final Color? color;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> {
  static final SpeechToText _stt = SpeechToText();
  static bool _inited = false;
  static String? _locale;
  bool _listening = false;

  Future<bool> _init() async {
    if (_inited) return true;
    try {
      final ok = await _stt.initialize(
        onStatus: (st) {
          if ((st == 'done' || st == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!ok) return false;
      final locales = await _stt.locales();
      for (final l in locales) {
        if (l.localeId.toLowerCase().replaceAll('-', '_').startsWith('bn')) {
          _locale = l.localeId;
          if (_locale!.toLowerCase().endsWith('bd')) break;
        }
      }
      _inited = true;
    } catch (_) {
      return false;
    }
    return true;
  }

  Future<void> _toggle() async {
    if (kIsWeb) return;
    if (_listening) {
      await _stt.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!await _init()) {
      if (mounted) {
        toast(
          context,
          'ভয়েস ইনপুট চালু করা যায়নি। মাইক্রোফোনের অনুমতি ও Google ভয়েস সেবা দেখুন',
        );
      }
      return;
    }
    if (_locale == null && mounted) {
      toast(
        context,
        'বাংলা ভয়েস পাওয়া যায়নি, ফোনের ডিফল্ট ভাষায় শোনা হচ্ছে',
      );
    }
    setState(() => _listening = true);
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: _locale,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (r) {
        widget.onText(r.recognizedWords);
        if (r.finalResult) widget.onFinal?.call(r.recognizedWords);
      },
    );
  }

  @override
  void dispose() {
    if (_listening) _stt.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: _listening ? 'থামান' : 'বলে লিখুন',
      onPressed: _toggle,
      icon: Icon(
        _listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
        color: _listening ? cs.error : widget.color ?? cs.primary,
      ),
    );
  }
}
