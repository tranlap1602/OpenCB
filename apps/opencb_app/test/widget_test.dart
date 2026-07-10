import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opencb_app/main.dart';

void main() {
  testWidgets('Mobile devices page keeps diagnostics scroll extent finite', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const OpenCbApp());
    await tester.pump();
    await tester.tap(find.text('Thiết bị').last);
    await tester.pumpAndSettle();

    final diagnosticsTitle = find.text('Chẩn đoán LAN');
    expect(diagnosticsTitle, findsOneWidget);
    final devicesList = find
        .ancestor(of: diagnosticsTitle, matching: find.byType(ListView))
        .first;
    final outerScrollable = find
        .descendant(of: devicesList, matching: find.byType(Scrollable))
        .first;
    final outerPosition = tester
        .state<ScrollableState>(outerScrollable)
        .position;
    expect(outerPosition.maxScrollExtent.isFinite, isTrue);

    await tester.scrollUntilVisible(
      diagnosticsTitle,
      360,
      scrollable: outerScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(diagnosticsTitle);
    await tester.pumpAndSettle();
    expect(outerPosition.maxScrollExtent.isFinite, isTrue);
    expect(outerPosition.maxScrollExtent, lessThan(5000));
  });

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
    await tester.tap(find.textContaining('OpenCB v').first);
    await tester.pumpAndSettle();
    expect(find.text('Cập nhật ứng dụng'), findsOneWidget);
    expect(find.text('Xuất báo cáo sự cố'), findsOneWidget);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
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
