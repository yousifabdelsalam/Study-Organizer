import 'package:flutter/material.dart';

class AText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? align;
  final int? maxLines;
  final TextOverflow? overflow;
  const AText(this.text,
      {super.key, this.style, this.align, this.maxLines, this.overflow});

  @override
  Widget build(BuildContext context) {
    final ar =
    RegExp(r'[\u0600-\u06FF\u0750-\u077F]').hasMatch(text);
    return Text(text,
        style: (style ?? const TextStyle()).copyWith(height: ar ? 1.6 : 1.4),
        textAlign: align ?? (ar ? TextAlign.right : TextAlign.left),
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        maxLines: maxLines,
        overflow: overflow);
  }
}