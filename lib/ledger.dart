import 'package:flutter/material.dart';

/// দুইটা আলাদা খাতা — কখনো মেশে না।
///   pabo : আমি পাবো (কাস্টমারের কাছে বাকি)
///   debo : আমি দেবো (মহাজন/সাপ্লায়ারের কাছে দেনা)
///
/// দুই খাতাতেই লেনদেন `baki` (বাকি/দেনা বাড়ে) আর `joma` (জমা/পরিশোধে কমে) —
/// তাই হিসাবের লজিক একই, শুধু লেখা আর রঙ আলাদা।
enum Ledger { pabo, debo }

class LedgerText {
  const LedgerText({
    required this.name,
    required this.party,
    required this.partyPlural,
    required this.partyHint,
    required this.total,
    required this.add,
    required this.reduce,
    required this.addShort,
    required this.reduceShort,
    required this.newEntry,
    required this.addSave,
    required this.reduceSave,
    required this.addTitle,
    required this.reduceTitle,
    required this.reduceWho,
    required this.whatHint,
    required this.whenAsk,
    required this.whenUnset,
    required this.hasDue,
    required this.dueToday,
    required this.dueTomorrow,
    required this.dueInDays,
    required this.added,
    required this.reduced,
    required this.reducedToday,
    required this.actToday,
    required this.rate,
    required this.biggest,
    required this.advance,
    required this.allSettled,
    required this.emptyHint,
  });

  final String name, party, partyPlural, partyHint, total;
  final String add, reduce, addShort, reduceShort, newEntry;
  final String addSave, reduceSave, addTitle, reduceTitle, reduceWho;
  final String whatHint, whenAsk, whenUnset, hasDue;
  final String dueToday, dueTomorrow, dueInDays;
  final String added, reduced, reducedToday, actToday, rate, biggest;
  final String advance, allSettled, emptyHint;

  static LedgerText of(Ledger l) => l == Ledger.pabo ? pabo : debo;

  static const pabo = LedgerText(
    name: 'পাওনা',
    party: 'কাস্টমার',
    partyPlural: 'কাস্টমার',
    partyHint: 'কাস্টমারের নাম',
    total: 'মোট পাওনা',
    add: 'বাকি দিলাম',
    reduce: 'জমা পেলাম',
    addShort: 'বাকি লিখুন',
    reduceShort: 'জমা নিন',
    newEntry: 'নতুন বাকি',
    addSave: 'বাকি সেভ করুন',
    reduceSave: 'জমা সেভ করুন',
    addTitle: 'বাকি',
    reduceTitle: 'জমা',
    reduceWho: 'কার কাছ থেকে জমা পেলেন?',
    whatHint: 'কী নিল? (ঐচ্ছিক)',
    whenAsk: 'কবে দেবে?',
    whenUnset: 'কবে দেবে ঠিক হয়নি',
    hasDue: 'বাকি আছে',
    dueToday: 'আজ দেওয়ার কথা',
    dueTomorrow: 'আগামীকাল দেবে',
    dueInDays: 'দিন পর দেবে',
    added: 'বাকি দেওয়া',
    reduced: 'আদায় হয়েছে',
    reducedToday: 'আজ আদায়',
    actToday: 'আজ আদায় করুন',
    rate: 'আদায়ের হার',
    biggest: 'সবচেয়ে বেশি বাকি',
    advance: 'অগ্রিম জমা',
    allSettled: 'সব বাকি পরিশোধ হয়েছে ✓',
    emptyHint: 'নিচের "নতুন বাকি" বাটনে চাপ দিয়ে প্রথম বাকি লিখুন',
  );

  static const debo = LedgerText(
    name: 'দেনা',
    party: 'পাওনাদার',
    partyPlural: 'পাওনাদার',
    partyHint: 'মহাজন / সাপ্লায়ারের নাম',
    total: 'মোট দেনা',
    add: 'মাল/টাকা নিলাম',
    reduce: 'পরিশোধ করলাম',
    addShort: 'দেনা লিখুন',
    reduceShort: 'পরিশোধ',
    newEntry: 'নতুন দেনা',
    addSave: 'দেনা সেভ করুন',
    reduceSave: 'পরিশোধ সেভ করুন',
    addTitle: 'দেনা',
    reduceTitle: 'পরিশোধ',
    reduceWho: 'কাকে পরিশোধ করলেন?',
    whatHint: 'কী নিলেন? (ঐচ্ছিক)',
    whenAsk: 'কবে দেবেন?',
    whenUnset: 'কবে দেবেন ঠিক হয়নি',
    hasDue: 'দেনা আছে',
    dueToday: 'আজ দিতে হবে',
    dueTomorrow: 'আগামীকাল দিতে হবে',
    dueInDays: 'দিন পর দিতে হবে',
    added: 'নতুন দেনা',
    reduced: 'পরিশোধ করেছি',
    reducedToday: 'আজ পরিশোধ',
    actToday: 'আজ পরিশোধ করুন',
    rate: 'পরিশোধের হার',
    biggest: 'সবচেয়ে বেশি দেনা',
    advance: 'অগ্রিম দেওয়া',
    allSettled: 'সব দেনা শোধ হয়েছে ✓',
    emptyHint: 'নিচের "নতুন দেনা" বাটনে চাপ দিয়ে প্রথম দেনা লিখুন',
  );
}

/// খাতার রঙ: পাওনা = টিল, দেনা = ইন্ডিগো।
Color ledgerAccent(Ledger l, Brightness b) => switch ((l, b)) {
  (Ledger.pabo, Brightness.light) => const Color(0xFF0F766E),
  (Ledger.pabo, Brightness.dark) => const Color(0xFF4DB6AC),
  (Ledger.debo, Brightness.light) => const Color(0xFF4338CA),
  (Ledger.debo, Brightness.dark) => const Color(0xFF8B8FF5),
};

/// হেডার কার্ডের গ্রেডিয়েন্ট।
List<Color> ledgerGradient(Ledger l) => l == Ledger.pabo
    ? const [Color(0xFF0F766E), Color(0xFF134E4A)]
    : const [Color(0xFF4338CA), Color(0xFF312E81)];
