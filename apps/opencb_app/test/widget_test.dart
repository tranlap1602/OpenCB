import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opencb_app/main.dart';

void main() {
  testWidgets('OpenCB shell renders clipboard workflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const OpenCbApp());
    await tester.pump();

    expect(find.text('OpenCB'), findsOneWidget);
    expect(find.text('Lịch sử'), findsWidgets);
    expect(find.byTooltip('Mở chọn nhanh'), findsNothing);
    expect(find.byTooltip('Dọn clipboard'), findsWidgets);

    await tester.tap(find.text('Thiết bị'));
    await tester.pumpAndSettle();
    expect(find.text('Sync'), findsWidgets);
    expect(find.text('QR pairing'), findsOneWidget);
    await tester.ensureVisible(find.text('Nhập payload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập payload'));
    await tester.pumpAndSettle();
    expect(find.text('Payload pairing'), findsOneWidget);
    expect(find.text('Áp dụng payload'), findsOneWidget);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cài đặt'));
    await tester.pumpAndSettle();
    expect(find.text('Cài đặt'), findsWidgets);
    expect(find.text('Ngôn ngữ'), findsOneWidget);
    expect(find.text('Bắt clipboard'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('Tự dán từ chọn nhanh'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -760));
    await tester.pumpAndSettle();
    expect(find.text('Lưu trữ'), findsOneWidget);
    expect(find.text('Ứng dụng loại trừ'), findsOneWidget);
  });
}
