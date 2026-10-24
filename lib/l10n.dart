import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

/// Flutter-এর বাংলা লোকালাইজেশন সময় ২৪ ঘণ্টায় দেখায় (টাইম পিকারেও)।
/// দোকানদাররা AM/PM-এ অভ্যস্ত, তাই বাকি সব বাংলা রেখে শুধু সময় ১২ ঘণ্টায়।
class _BnMaterial12h extends MaterialLocalizationBn {
  _BnMaterial12h()
    : super(
        fullYearFormat: intl.DateFormat.y('bn'),
        compactDateFormat: intl.DateFormat.yMd('bn'),
        shortDateFormat: intl.DateFormat.yMMMd('bn'),
        mediumDateFormat: intl.DateFormat.MMMEd('bn'),
        longDateFormat: intl.DateFormat.yMMMMEEEEd('bn'),
        yearMonthFormat: intl.DateFormat.yMMMM('bn'),
        shortMonthDayFormat: intl.DateFormat.MMMd('bn'),
        decimalFormat: intl.NumberFormat.decimalPattern('bn'),
        twoDigitZeroPaddedFormat: intl.NumberFormat('00', 'bn'),
      );

  @override
  TimeOfDayFormat get timeOfDayFormatRaw => TimeOfDayFormat.h_colon_mm_space_a;
}

class _BnMaterial12hDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _BnMaterial12hDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'bn';

  @override
  // বাংলা তারিখের intl ডাটা ফ্লাটারের ডেলিগেটেই লোড হয়। সেটা
  // SynchronousFuture, তাই then-ও সাথে সাথে চলে — প্রথম ফ্রেম ফাঁকা থাকে না।
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate
          .load(locale)
          .then((_) => _BnMaterial12h());

  @override
  bool shouldReload(_BnMaterial12hDelegate old) => false;
}

/// একই ধরনের ডেলিগেটের মধ্যে প্রথমটাই চলে, তাই এটা সবার আগে।
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  _BnMaterial12hDelegate(),
  ...GlobalMaterialLocalizations.delegates,
];
