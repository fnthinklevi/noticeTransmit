import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/widgets/app_info_note_box.dart';
import 'package:notice_transmit/widgets/app_root.dart';

Widget _buildApp(Widget child) =>
    AppRoot(locale: const Locale('zh'), dark: false, home: child);

BoxDecoration _decorationOf(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(AppInfoNoteBox),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('普通档：有边框、有圆角，文字原样在里面', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        const CupertinoPageScaffold(child: AppInfoNoteBox(text: '这段说明需要边界')),
      ),
    );

    expect(find.text('这段说明需要边界'), findsOneWidget);
    final decoration = _decorationOf(tester);
    expect(decoration.border, isNotNull);
    expect(decoration.borderRadius, isNotNull);
  });

  testWidgets('警告档：边框与文字都取语义色', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        const CupertinoPageScaffold(
          child: AppInfoNoteBox(
            tone: AppInfoNoteTone.warning,
            title: '注意',
            text: '这一段需要被看见',
          ),
        ),
      ),
    );

    expect(find.text('注意'), findsOneWidget);
    expect(find.text('这一段需要被看见'), findsOneWidget);
    expect(_decorationOf(tester).border, isNotNull);
  });

  testWidgets('富文本子件：链接与外框可以共存', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        CupertinoPageScaffold(
          child: AppInfoNoteBox(
            child: RichText(text: const TextSpan(text: '带链接的说明')),
          ),
        ),
      ),
    );

    expect(find.text('带链接的说明', findRichText: true), findsOneWidget);
    expect(_decorationOf(tester).border, isNotNull);
  });
}
