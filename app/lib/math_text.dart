import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

// "$...$" 로 감싼 LaTeX 수식이 섞인 한국어 문장을 예쁘게 그린다.
// (웹의 KaTeX(MathText)와 같은 역할. 학생 풀이 화면에서도 재사용.)
class MathText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const MathText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    // '$' 기준으로 자르면 홀수 칸이 수식, 짝수 칸이 일반 글자.
    final parts = text.split(r'$');
    final spans = <InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (i.isEven) {
        if (parts[i].isNotEmpty) {
          spans.add(TextSpan(text: parts[i], style: base));
        }
      } else {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(
              parts[i],
              textStyle: base,
              // 수식이 깨지면(잘못된 LaTeX) 원문 그대로 보여줌.
              onErrorFallback: (_) => Text('\$${parts[i]}\$', style: base),
            ),
          ),
        );
      }
    }
    return Text.rich(TextSpan(children: spans));
  }
}
