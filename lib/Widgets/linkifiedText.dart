import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// نص عادي، بس أي رابط جواه (رابط دعوة مكالمة groupify:// أو رابط
/// http/https عادي) بيصير ملوّن وتحته خط وقابل للضغط عليه مباشرة.
class LinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  final void Function(String url) onLinkTap;

  const LinkifiedText({
    super.key,
    required this.text,
    required this.style,
    required this.linkColor,
    required this.onLinkTap,
  });

  static final RegExp _linkPattern = RegExp(
    r'groupify://\S+|https?://\S+',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final matches = _linkPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: style);
    }

    final spans = <InlineSpan>[];
    var lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: style.copyWith(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => onLinkTap(url),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return Text.rich(TextSpan(style: style, children: spans));
  }
}
