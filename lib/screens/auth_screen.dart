import 'package:flutter/material.dart';

import '../auth.dart';
import '../pin_field.dart';
import '../utils.dart';

/// লগইন ও সাইন আপ — ফোন নাম্বার + ৫ ডিজিটের PIN (বিকাশের মতো)।
/// সফল হলে AuthGate নিজেই হোমে নিয়ে যায়।
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  late final _phone = TextEditingController(
    text: AuthService.instance.lastPhone,
  );
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  final _phoneFocus = FocusNode();
  final _pinFocus = FocusNode();
  final _pin2Focus = FocusNode();
  bool _signUp = false;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    // নাম্বার মনে থাকলে সরাসরি PIN-এ, নইলে নাম্বারে — সংখ্যার কীপ্যাড নিজে খোলে।
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (AuthService.normalizePhone(_phone.text) != null
              ? _pinFocus
              : _phoneFocus)
          .requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _pin, _pin2]) {
      c.dispose();
    }
    for (final f in [_phoneFocus, _pinFocus, _pin2Focus]) {
      f.dispose();
    }
    super.dispose();
  }

  void _toggle() => setState(() {
    _signUp = !_signUp;
    _err = null;
    _pin.clear();
    _pin2.clear();
  });

  Future<void> _submit() async {
    if (_busy) return;
    if (_signUp && _pin.text != _pin2.text) {
      setState(() {
        _err = 'দুই বারের PIN মেলেনি';
        _pin2.clear();
      });
      _pin2Focus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    final auth = AuthService.instance;
    final msg = _signUp
        ? await auth.register(
            name: _name.text,
            phone: _phone.text,
            pin: _pin.text,
          )
        : await auth.login(phone: _phone.text, pin: _pin.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = msg;
      if (msg != null) {
        _pin.clear();
        _pin2.clear();
      }
    });
    if (msg != null) _pinFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final phoneOk = AuthService.normalizePhone(_phone.text) != null;
    final pinOk = _pin.text.length == PinField.pinLength;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/logo/logo_256.png',
                      width: 84,
                      height: 84,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _signUp ? 'নতুন অ্যাকাউন্ট খুলুন' : 'বাকির খাতায় লগইন',
                    textAlign: TextAlign.center,
                    style: t.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _signUp
                        ? 'নাম, ফোন নাম্বার আর ${bn(PinField.pinLength)} ডিজিটের PIN দিন'
                        : 'ফোন নাম্বার আর ${bn(PinField.pinLength)} ডিজিটের PIN দিন',
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  if (_signUp) ...[
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'আপনার নাম',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: _phone,
                    focusNode: _phoneFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      setState(() {});
                      // ১১ ডিজিট হলেই PIN-এ চলে যায়।
                      if (AuthService.normalizePhone(_phone.text) != null &&
                          _phone.text.length >= 11) {
                        _pinFocus.requestFocus();
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'ফোন নাম্বার',
                      hintText: '০১৭XXXXXXXX',
                      prefixIcon: Icon(Icons.phone_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  PinField(
                    label: _signUp
                        ? 'PIN (${bn(PinField.pinLength)} ডিজিট)'
                        : 'PIN',
                    controller: _pin,
                    focusNode: _pinFocus,
                    onChanged: () => setState(() {}),
                    onCompleted: () {
                      if (_signUp) {
                        _pin2Focus.requestFocus();
                      } else if (phoneOk) {
                        _submit();
                      }
                    },
                  ),
                  if (_signUp) ...[
                    const SizedBox(height: 14),
                    PinField(
                      label: 'আবার PIN দিন',
                      controller: _pin2,
                      focusNode: _pin2Focus,
                      onChanged: () => setState(() {}),
                      onCompleted: () {
                        if (phoneOk && _name.text.trim().isNotEmpty) _submit();
                      },
                    ),
                  ],
                  if (_err != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _err!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.error),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed:
                        _busy ||
                            !phoneOk ||
                            !pinOk ||
                            (_signUp && _pin2.text.length != _pin.text.length)
                        ? null
                        : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_signUp ? 'সাইন আপ' : 'লগইন'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy ? null : _toggle,
                    child: Text(
                      _signUp
                          ? 'আগেই অ্যাকাউন্ট আছে? লগইন করুন'
                          : 'নতুন? অ্যাকাউন্ট খুলুন',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
