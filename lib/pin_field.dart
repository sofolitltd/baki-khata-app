import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ৫ ডিজিটের PIN-এর সাধারণ ইনপুট ফিল্ড: সংখ্যার কীপ্যাড খোলে,
/// শুধু ডিজিট নেয়, আর ৫টির বেশি লেখা যায় না। [onCompleted] ৫টি পূর্ণ হলে চলে।
class PinField extends StatefulWidget {
  const PinField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.label = 'PIN',
    this.onChanged,
    this.onCompleted,
    this.textInputAction = TextInputAction.done,
  });

  static const pinLength = 5;

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final VoidCallback? onChanged;
  final VoidCallback? onCompleted;
  final TextInputAction textInputAction;

  @override
  State<PinField> createState() => _PinFieldState();
}

class _PinFieldState extends State<PinField> {
  bool _hide = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      keyboardType: TextInputType.number,
      textInputAction: widget.textInputAction,
      obscureText: _hide,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(PinField.pinLength),
      ],
      onChanged: (v) {
        widget.onChanged?.call();
        if (v.length == PinField.pinLength) widget.onCompleted?.call();
      },
      decoration: InputDecoration(
        labelText: widget.label,
        counterText: '',
        prefixIcon: const Icon(Icons.lock_rounded),
        suffixIcon: IconButton(
          icon: Icon(
            _hide ? Icons.visibility_rounded : Icons.visibility_off_rounded,
          ),
          onPressed: () => setState(() => _hide = !_hide),
        ),
      ),
    );
  }
}
