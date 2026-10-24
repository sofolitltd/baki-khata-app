import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show Printing;

import 'auth.dart';
import 'ledger.dart';
import 'models.dart';
import 'store.dart';
import 'theme.dart';
import 'utils.dart';

/// প্রিন্টে কাস্টমারদের কীভাবে ভাগ করে সাজানো হবে।
enum PrintGroup { lastBaki, due, name }

/// একই মাসের কাস্টমাররা এক ভাগে। নাম অনুযায়ী হলে শিরোনাম ছাড়া একটাই ভাগ।
class PrintSection {
  PrintSection(this.title, this.customers);
  final String? title;
  final List<Customer> customers;

  double get sum => customers.fold(0, (s, c) => s + c.balance);
}

List<PrintSection> printSections(
  Ledger ledger,
  PrintGroup group,
  bool oldestFirst,
) {
  final list = Store.instance.all
      .where((c) => c.ledger == ledger && c.hasDue)
      .toList();
  if (group == PrintGroup.name) {
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [PrintSection(null, list)];
  }

  DateTime? key(Customer c) =>
      group == PrintGroup.lastBaki ? c.lastBakiAt : c.dueDate;
  // তারিখ ছাড়া যারা, তারা সবার শেষে
  list.sort((a, b) {
    final (x, y) = (key(a), key(b));
    if (x == null || y == null) {
      if (x == y) return a.name.compareTo(b.name);
      return x == null ? 1 : -1;
    }
    return oldestFirst ? x.compareTo(y) : y.compareTo(x);
  });

  final sections = <PrintSection>[];
  String? last;
  for (final c in list) {
    final d = key(c);
    final title = d == null
        ? (group == PrintGroup.due ? 'তারিখ ঠিক হয়নি' : 'তারিখ নেই')
        : bn(DateFormat('MMMM yyyy', 'bn').format(d));
    if (title != last) {
      sections.add(PrintSection(title, []));
      last = title;
    }
    sections.last.customers.add(c);
  }
  return sections;
}

/// কেটে আলাদা করা যায় এমন স্লিপের তালিকা বানিয়ে ফোনের প্রিন্ট ডায়লগ খোলে
/// (সেখান থেকে PDF হিসেবেও সেভ করা যায়)।
///
/// pdf প্যাকেজ বাংলা যুক্তাক্ষর ঠিকমতো জোড়া দিতে পারে না, তাই প্রতিটা পাতা
/// Flutter-এর নিজস্ব টেক্সট ইঞ্জিনে ছবি হিসেবে এঁকে PDF-এ বসানো হয়।
Future<void> printDueSlips({
  required Ledger ledger,
  required PrintGroup group,
  required bool oldestFirst,
}) async {
  final sections = printSections(ledger, group, oldestFirst);
  final pngs = await renderSlipPages(sections, ledger, group, oldestFirst);
  final doc = pw.Document(title: '${LedgerText.of(ledger).addTitle}র তালিকা');
  for (final png in pngs) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
        ),
      ),
    );
  }
  final bytes = await doc.save();
  await Printing.layoutPdf(
    name: 'baki-khata-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf',
    format: PdfPageFormat.a4,
    onLayout: (_) async => bytes,
  );
}

/// প্রতিটা A4 পাতা PNG হিসেবে।
@visibleForTesting
Future<List<Uint8List>> renderSlipPages(
  List<PrintSection> sections,
  Ledger ledger,
  PrintGroup group,
  bool oldestFirst,
) async {
  final pages = _paginate(sections);
  final painter = _SlipPainter(
    ledger: ledger,
    group: group,
    oldestFirst: oldestFirst,
    sections: sections,
  );
  return [
    for (var i = 0; i < pages.length; i++)
      await painter.render(pages[i], i + 1, pages.length),
  ];
}

// ---- পাতা ভাগ ----
// সব মাপ পয়েন্টে (A4 = ৫৯৫ × ৮৪২)।

const _pageW = 595.28, _pageH = 841.89, _margin = 28.0;
const _contentW = _pageW - _margin * 2;
const _slipH = 128.0, _headerH = 56.0, _sectionH = 28.0, _footerH = 18.0;

sealed class _Item {
  const _Item();
  double get height;
}

class _Header extends _Item {
  const _Header();
  @override
  double get height => _headerH;
}

class _SectionTitle extends _Item {
  const _SectionTitle(this.section);
  final PrintSection section;
  @override
  double get height => _sectionH;
}

/// পাশাপাশি দুটো (শেষেরটা একটাও হতে পারে) স্লিপ।
class _SlipRow extends _Item {
  const _SlipRow(this.customers);
  final List<Customer> customers;
  @override
  double get height => _slipH;
}

typedef _Placed = ({_Item item, double y});

List<List<_Placed>> _paginate(List<PrintSection> sections) {
  final items = <_Item>[const _Header()];
  for (final s in sections) {
    if (s.title != null) items.add(_SectionTitle(s));
    for (var i = 0; i < s.customers.length; i += 2) {
      items.add(_SlipRow(s.customers.skip(i).take(2).toList()));
    }
  }

  const bottom = _pageH - _margin - _footerH;
  final pages = <List<_Placed>>[[]];
  var y = _margin;
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    // মাসের শিরোনাম একা পাতার নিচে পড়ে না থেকে প্রথম সারির সাথে যায়
    final need =
        item.height +
        (item is _SectionTitle && i + 1 < items.length
            ? items[i + 1].height
            : 0);
    if (y + need > bottom && pages.last.isNotEmpty) {
      pages.add([]);
      y = _margin;
    }
    pages.last.add((item: item, y: y));
    y += item.height;
  }
  return pages;
}

// ---- আঁকা ----

class _SlipPainter {
  _SlipPainter({
    required this.ledger,
    required this.group,
    required this.oldestFirst,
    required this.sections,
  });

  final Ledger ledger;
  final PrintGroup group;
  final bool oldestFirst;
  final List<PrintSection> sections;

  /// পয়েন্ট থেকে পিক্সেল (~১৮০ DPI) — প্রিন্টে লেখা পরিষ্কার থাকে।
  static const _scale = 2.5;

  LedgerText get _t => LedgerText.of(ledger);

  static const _ink = Color(0xFF111111);
  static const _muted = Color(0xFF555555);

  Future<Uint8List> render(List<_Placed> page, int no, int total) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_scale);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _pageW, _pageH),
      Paint()..color = Colors.white,
    );
    for (final (:item, :y) in page) {
      switch (item) {
        case _Header():
          _header(canvas, y);
        case _SectionTitle(:final section):
          _sectionTitle(canvas, y, section);
        case _SlipRow(:final customers):
          for (var i = 0; i < customers.length; i++) {
            _slip(
              canvas,
              Rect.fromLTWH(
                _margin + i * _contentW / 2,
                y,
                _contentW / 2,
                _slipH,
              ),
              customers[i],
            );
          }
      }
    }
    _text(
      canvas,
      'পৃষ্ঠা ${bn(no)}/${bn(total)}',
      const Offset(_margin, _pageH - _margin - 10),
      width: _contentW,
      size: 9,
      color: _muted,
      align: TextAlign.center,
    );

    final image = await recorder.endRecording().toImage(
      (_pageW * _scale).round(),
      (_pageH * _scale).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  void _header(Canvas canvas, double y) {
    final shop = AuthService.instance.account?.shopName ?? '';
    final all = sections.expand((s) => s.customers);
    final sum = all.fold<double>(0, (s, c) => s + c.balance);
    final order = switch (group) {
      PrintGroup.lastBaki =>
        'শেষ ${_t.addTitle}র মাস অনুযায়ী, ${oldestFirst ? 'পুরোনো' : 'নতুন'} আগে',
      PrintGroup.due =>
        'দেওয়ার তারিখের মাস অনুযায়ী, ${oldestFirst ? 'আগেরটা' : 'পরেরটা'} আগে',
      PrintGroup.name => 'নাম অনুযায়ী',
    };
    var dy = y;
    if (shop.isNotEmpty) {
      dy += _text(canvas, shop, Offset(_margin, dy), size: 16, bold: true);
    }
    dy += _text(
      canvas,
      '${_t.addTitle}র তালিকা — $order',
      Offset(_margin, dy),
      size: 12,
      bold: shop.isEmpty,
    );
    _text(
      canvas,
      'মোট ${bn(all.length)} জন • ${taka(sum)} • প্রিন্ট: ${fmtDate(DateTime.now())}',
      Offset(_margin, dy + 2),
      size: 10,
      color: _muted,
    );
  }

  void _sectionTitle(Canvas canvas, double y, PrintSection s) {
    final r = Rect.fromLTWH(_margin, y + 4, _contentW, _sectionH - 8);
    canvas.drawRect(r, Paint()..color = const Color(0xFFEDEDED));
    _text(
      canvas,
      s.title!,
      Offset(r.left + 8, r.top + 3),
      size: 12,
      bold: true,
    );
    _text(
      canvas,
      '${bn(s.customers.length)} জন • ${taka(s.sum)}',
      Offset(r.left, r.top + 4),
      width: r.width - 8,
      size: 10,
      align: TextAlign.right,
    );
  }

  void _slip(Canvas canvas, Rect r, Customer c) {
    _dashedRect(canvas, r);
    const pad = 10.0;
    final inner = r.deflate(pad);

    final amount = _layout(taka(c.balance), size: 15, bold: true);
    amount.paint(canvas, Offset(inner.right - amount.width, inner.top));
    var y =
        inner.top +
        _text(
          canvas,
          c.name,
          inner.topLeft,
          width: inner.width - amount.width - 8,
          size: 13,
          bold: true,
        ) +
        2;

    void line(String s) =>
        y += _text(canvas, s, Offset(inner.left, y), width: inner.width);

    if (c.phones.isNotEmpty) line('মোবাইল: ${c.phones.join(', ')}');
    if (c.address.isNotEmpty) line(c.address);
    if (c.lastBakiAt != null) {
      line(
        'শেষ ${_t.addTitle}: ${fmtDate(c.lastBakiAt!)} (${agoLabel(c.lastBakiAt!)})',
      );
    }
    if (c.dueDate != null) {
      line(
        'দেওয়ার কথা: ${fmtDate(c.dueDate!)} (${dueLabel(c.dueDate!, ledger)})',
      );
    }

    _text(
      canvas,
      '${_t.reduceTitle}: ______________   তারিখ: ____________',
      Offset(inner.left, inner.bottom - 12),
      width: inner.width,
    );
  }

  void _dashedRect(Canvas canvas, Rect r) {
    final paint = Paint()
      ..color = const Color(0xFF888888)
      ..strokeWidth = 0.6;
    const dash = 4.0, gap = 3.0;
    void dashed(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * (d + dash).clamp(0, len), paint);
      }
    }

    dashed(r.topLeft, r.topRight);
    dashed(r.bottomLeft, r.bottomRight);
    dashed(r.topLeft, r.bottomLeft);
    dashed(r.topRight, r.bottomRight);
  }

  TextPainter _layout(
    String s, {
    double size = 10,
    bool bold = false,
    Color color = _ink,
    double width = double.infinity,
    TextAlign align = TextAlign.left,
  }) => TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontFamily: appFont,
        fontSize: size,
        height: 1.25,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: 1,
    ellipsis: '…',
  )..layout(minWidth: width.isFinite ? width : 0, maxWidth: width);

  /// এক লাইন লেখে, উচ্চতা ফেরত দেয়।
  double _text(
    Canvas canvas,
    String s,
    Offset at, {
    double size = 10,
    bool bold = false,
    Color color = _ink,
    double width = _contentW,
    TextAlign align = TextAlign.left,
  }) {
    final tp = _layout(
      s,
      size: size,
      bold: bold,
      color: color,
      width: width,
      align: align,
    );
    tp.paint(canvas, at);
    return tp.height;
  }
}
