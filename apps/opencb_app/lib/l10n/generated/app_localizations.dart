import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('vi'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In vi, this message translates to:
  /// **'OpenCB'**
  String get appTitle;

  /// No description provided for @navHistory.
  ///
  /// In vi, this message translates to:
  /// **'Lịch sử'**
  String get navHistory;

  /// No description provided for @navPinned.
  ///
  /// In vi, this message translates to:
  /// **'Đã ghim'**
  String get navPinned;

  /// No description provided for @navTags.
  ///
  /// In vi, this message translates to:
  /// **'Thẻ'**
  String get navTags;

  /// No description provided for @navSendFiles.
  ///
  /// In vi, this message translates to:
  /// **'Gửi file'**
  String get navSendFiles;

  /// No description provided for @navDevices.
  ///
  /// In vi, this message translates to:
  /// **'Thiết bị'**
  String get navDevices;

  /// No description provided for @navSettings.
  ///
  /// In vi, this message translates to:
  /// **'Cài đặt'**
  String get navSettings;

  /// No description provided for @devicesLan.
  ///
  /// In vi, this message translates to:
  /// **'Thiết bị LAN'**
  String get devicesLan;

  /// No description provided for @updateApp.
  ///
  /// In vi, this message translates to:
  /// **'Cập nhật ứng dụng'**
  String get updateApp;

  /// No description provided for @back.
  ///
  /// In vi, this message translates to:
  /// **'Quay lại'**
  String get back;

  /// No description provided for @search.
  ///
  /// In vi, this message translates to:
  /// **'Tìm kiếm'**
  String get search;

  /// No description provided for @clearSearch.
  ///
  /// In vi, this message translates to:
  /// **'Xóa tìm kiếm'**
  String get clearSearch;

  /// No description provided for @clipboard.
  ///
  /// In vi, this message translates to:
  /// **'Clipboard'**
  String get clipboard;

  /// No description provided for @quickClipboardSearch.
  ///
  /// In vi, this message translates to:
  /// **'Tìm nhanh trong lịch sử clipboard.'**
  String get quickClipboardSearch;

  /// No description provided for @historyTitle.
  ///
  /// In vi, this message translates to:
  /// **'Lịch sử clipboard'**
  String get historyTitle;

  /// No description provided for @pinnedTitle.
  ///
  /// In vi, this message translates to:
  /// **'Clipboard đã ghim'**
  String get pinnedTitle;

  /// No description provided for @taggedTitle.
  ///
  /// In vi, this message translates to:
  /// **'Clipboard có thẻ'**
  String get taggedTitle;

  /// No description provided for @all.
  ///
  /// In vi, this message translates to:
  /// **'Tất cả'**
  String get all;

  /// No description provided for @pinned.
  ///
  /// In vi, this message translates to:
  /// **'Ghim'**
  String get pinned;

  /// No description provided for @tagged.
  ///
  /// In vi, this message translates to:
  /// **'Gắn thẻ'**
  String get tagged;

  /// No description provided for @appearance.
  ///
  /// In vi, this message translates to:
  /// **'Giao diện'**
  String get appearance;

  /// No description provided for @displayMode.
  ///
  /// In vi, this message translates to:
  /// **'Chế độ hiển thị'**
  String get displayMode;

  /// No description provided for @light.
  ///
  /// In vi, this message translates to:
  /// **'Sáng'**
  String get light;

  /// No description provided for @system.
  ///
  /// In vi, this message translates to:
  /// **'Hệ thống'**
  String get system;

  /// No description provided for @dark.
  ///
  /// In vi, this message translates to:
  /// **'Tối'**
  String get dark;

  /// No description provided for @materialYouPalette.
  ///
  /// In vi, this message translates to:
  /// **'Bảng màu Material You'**
  String get materialYouPalette;

  /// No description provided for @language.
  ///
  /// In vi, this message translates to:
  /// **'Ngôn ngữ'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In vi, this message translates to:
  /// **'Hệ thống'**
  String get languageSystem;

  /// No description provided for @languageVietnamese.
  ///
  /// In vi, this message translates to:
  /// **'Tiếng Việt'**
  String get languageVietnamese;

  /// No description provided for @languageEnglish.
  ///
  /// In vi, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @openUpdateSettings.
  ///
  /// In vi, this message translates to:
  /// **'Nhấn vào để mở cài đặt cập nhật'**
  String get openUpdateSettings;

  /// No description provided for @settingsDevicesSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Ghép thiết bị, quét QR và quản lý sync.'**
  String get settingsDevicesSubtitle;

  /// No description provided for @clipboardText.
  ///
  /// In vi, this message translates to:
  /// **'Văn bản'**
  String get clipboardText;

  /// No description provided for @clipboardCode.
  ///
  /// In vi, this message translates to:
  /// **'Code'**
  String get clipboardCode;

  /// No description provided for @clipboardUrl.
  ///
  /// In vi, this message translates to:
  /// **'URL'**
  String get clipboardUrl;

  /// No description provided for @clipboardImage.
  ///
  /// In vi, this message translates to:
  /// **'Ảnh'**
  String get clipboardImage;

  /// No description provided for @clipboardPath.
  ///
  /// In vi, this message translates to:
  /// **'Path'**
  String get clipboardPath;

  /// No description provided for @kindTextTitle.
  ///
  /// In vi, this message translates to:
  /// **'Clipboard văn bản'**
  String get kindTextTitle;

  /// No description provided for @kindCodeTitle.
  ///
  /// In vi, this message translates to:
  /// **'Clipboard code'**
  String get kindCodeTitle;

  /// No description provided for @kindUrlTitle.
  ///
  /// In vi, this message translates to:
  /// **'Clipboard URL'**
  String get kindUrlTitle;

  /// No description provided for @kindImageTitle.
  ///
  /// In vi, this message translates to:
  /// **'Clipboard hình ảnh'**
  String get kindImageTitle;

  /// No description provided for @kindPathTitle.
  ///
  /// In vi, this message translates to:
  /// **'Clipboard path'**
  String get kindPathTitle;

  /// No description provided for @noClipboardItems.
  ///
  /// In vi, this message translates to:
  /// **'Chưa có clipboard nào.'**
  String get noClipboardItems;

  /// No description provided for @noPinnedItems.
  ///
  /// In vi, this message translates to:
  /// **'Chưa có clipboard được ghim.'**
  String get noPinnedItems;

  /// No description provided for @noTaggedItems.
  ///
  /// In vi, this message translates to:
  /// **'Chưa có clipboard có thẻ.'**
  String get noTaggedItems;

  /// No description provided for @noMatchingItems.
  ///
  /// In vi, this message translates to:
  /// **'Không có mục phù hợp.'**
  String get noMatchingItems;

  /// No description provided for @checkUpdates.
  ///
  /// In vi, this message translates to:
  /// **'Kiểm tra cập nhật'**
  String get checkUpdates;

  /// No description provided for @autoCheckUpdates.
  ///
  /// In vi, this message translates to:
  /// **'Tự kiểm tra cập nhật'**
  String get autoCheckUpdates;

  /// No description provided for @landingPage.
  ///
  /// In vi, this message translates to:
  /// **'Trang giới thiệu'**
  String get landingPage;

  /// No description provided for @github.
  ///
  /// In vi, this message translates to:
  /// **'GitHub'**
  String get github;

  /// No description provided for @cancel.
  ///
  /// In vi, this message translates to:
  /// **'Hủy'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In vi, this message translates to:
  /// **'Lưu'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In vi, this message translates to:
  /// **'Xóa'**
  String get delete;

  /// No description provided for @deselect.
  ///
  /// In vi, this message translates to:
  /// **'Bỏ chọn'**
  String get deselect;

  /// No description provided for @clear.
  ///
  /// In vi, this message translates to:
  /// **'Dọn'**
  String get clear;

  /// No description provided for @add.
  ///
  /// In vi, this message translates to:
  /// **'Thêm'**
  String get add;

  /// No description provided for @apply.
  ///
  /// In vi, this message translates to:
  /// **'Áp dụng'**
  String get apply;

  /// No description provided for @copy.
  ///
  /// In vi, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In vi, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @openUrl.
  ///
  /// In vi, this message translates to:
  /// **'Mở URL'**
  String get openUrl;

  /// No description provided for @openFolder.
  ///
  /// In vi, this message translates to:
  /// **'Mở thư mục'**
  String get openFolder;

  /// No description provided for @openFile.
  ///
  /// In vi, this message translates to:
  /// **'Mở file'**
  String get openFile;

  /// No description provided for @pin.
  ///
  /// In vi, this message translates to:
  /// **'Ghim'**
  String get pin;

  /// No description provided for @unpin.
  ///
  /// In vi, this message translates to:
  /// **'Bỏ ghim'**
  String get unpin;

  /// No description provided for @pinnedState.
  ///
  /// In vi, this message translates to:
  /// **'Đã ghim'**
  String get pinnedState;

  /// No description provided for @tagsAction.
  ///
  /// In vi, this message translates to:
  /// **'Thẻ'**
  String get tagsAction;

  /// No description provided for @removeTag.
  ///
  /// In vi, this message translates to:
  /// **'Bỏ thẻ'**
  String get removeTag;

  /// No description provided for @editTag.
  ///
  /// In vi, this message translates to:
  /// **'Sửa màu và icon'**
  String get editTag;

  /// No description provided for @deleteTag.
  ///
  /// In vi, this message translates to:
  /// **'Xóa thẻ'**
  String get deleteTag;

  /// No description provided for @fileUnit.
  ///
  /// In vi, this message translates to:
  /// **'file'**
  String get fileUnit;

  /// No description provided for @deviceUnit.
  ///
  /// In vi, this message translates to:
  /// **'thiết bị'**
  String get deviceUnit;

  /// No description provided for @itemUnit.
  ///
  /// In vi, this message translates to:
  /// **'mục'**
  String get itemUnit;

  /// No description provided for @folderUnit.
  ///
  /// In vi, this message translates to:
  /// **'folder'**
  String get folderUnit;

  /// No description provided for @allItems.
  ///
  /// In vi, this message translates to:
  /// **'Tất cả'**
  String get allItems;

  /// No description provided for @completed.
  ///
  /// In vi, this message translates to:
  /// **'Hoàn tất'**
  String get completed;

  /// No description provided for @rejected.
  ///
  /// In vi, this message translates to:
  /// **'Từ chối'**
  String get rejected;

  /// No description provided for @error.
  ///
  /// In vi, this message translates to:
  /// **'Lỗi'**
  String get error;

  /// No description provided for @waitingForConfirm.
  ///
  /// In vi, this message translates to:
  /// **'Đang chờ xác nhận'**
  String get waitingForConfirm;

  /// No description provided for @sending.
  ///
  /// In vi, this message translates to:
  /// **'Đang gửi'**
  String get sending;

  /// No description provided for @receiving.
  ///
  /// In vi, this message translates to:
  /// **'Đang nhận'**
  String get receiving;

  /// No description provided for @canceled.
  ///
  /// In vi, this message translates to:
  /// **'Đã hủy'**
  String get canceled;

  /// No description provided for @measuring.
  ///
  /// In vi, this message translates to:
  /// **'Đang đo'**
  String get measuring;

  /// No description provided for @sendFilesContent.
  ///
  /// In vi, this message translates to:
  /// **'Nội dung gửi'**
  String get sendFilesContent;

  /// No description provided for @chooseReceivingDevice.
  ///
  /// In vi, this message translates to:
  /// **'Chọn thiết bị nhận'**
  String get chooseReceivingDevice;

  /// No description provided for @sendReceiveActivity.
  ///
  /// In vi, this message translates to:
  /// **'Hoạt động gửi nhận'**
  String get sendReceiveActivity;

  /// No description provided for @clearTransferHistory.
  ///
  /// In vi, this message translates to:
  /// **'Dọn lịch sử gửi nhận'**
  String get clearTransferHistory;

  /// No description provided for @clearTransferHistoryTitle.
  ///
  /// In vi, this message translates to:
  /// **'Dọn lịch sử gửi nhận'**
  String get clearTransferHistoryTitle;

  /// No description provided for @clearTransferHistoryBodyPrefix.
  ///
  /// In vi, this message translates to:
  /// **'Xóa'**
  String get clearTransferHistoryBodyPrefix;

  /// No description provided for @clearTransferHistoryBodySuffix.
  ///
  /// In vi, this message translates to:
  /// **'hoạt động gửi nhận đã kết thúc khỏi lịch sử.'**
  String get clearTransferHistoryBodySuffix;

  /// No description provided for @noOnlineDevices.
  ///
  /// In vi, this message translates to:
  /// **'Chưa có thiết bị online'**
  String get noOnlineDevices;

  /// No description provided for @openPairedDevicesWifi.
  ///
  /// In vi, this message translates to:
  /// **'Mở OpenCB trên thiết bị đã ghép nối trong cùng Wi-Fi/VPN.'**
  String get openPairedDevicesWifi;

  /// No description provided for @lanSyncOff.
  ///
  /// In vi, this message translates to:
  /// **'Sync LAN đang tắt'**
  String get lanSyncOff;

  /// No description provided for @enableLanToSendFiles.
  ///
  /// In vi, this message translates to:
  /// **'Bật Sync LAN để thấy thiết bị và gửi file trong mạng.'**
  String get enableLanToSendFiles;

  /// No description provided for @noTransfers.
  ///
  /// In vi, this message translates to:
  /// **'Chưa có transfer'**
  String get noTransfers;

  /// No description provided for @noTransferWithStatus.
  ///
  /// In vi, this message translates to:
  /// **'Không có mục'**
  String get noTransferWithStatus;

  /// No description provided for @chooseOnlineDeviceToSend.
  ///
  /// In vi, this message translates to:
  /// **'Chọn một thiết bị online để gửi file.'**
  String get chooseOnlineDeviceToSend;

  /// No description provided for @changeFilterToViewTransfers.
  ///
  /// In vi, this message translates to:
  /// **'Đổi bộ lọc để xem hoạt động gửi nhận khác.'**
  String get changeFilterToViewTransfers;

  /// No description provided for @dragFilesHere.
  ///
  /// In vi, this message translates to:
  /// **'Kéo file hoặc folder vào đây, hoặc chọn bên dưới.'**
  String get dragFilesHere;

  /// No description provided for @chooseFileToSend.
  ///
  /// In vi, this message translates to:
  /// **'Chọn file để gửi.'**
  String get chooseFileToSend;

  /// No description provided for @addMoreFiles.
  ///
  /// In vi, this message translates to:
  /// **'Thêm file khác vào danh sách gửi.'**
  String get addMoreFiles;

  /// No description provided for @addMoreFilesOrFolders.
  ///
  /// In vi, this message translates to:
  /// **'Thêm file hoặc folder khác vào danh sách gửi.'**
  String get addMoreFilesOrFolders;

  /// No description provided for @chooseFile.
  ///
  /// In vi, this message translates to:
  /// **'Chọn file'**
  String get chooseFile;

  /// No description provided for @chooseFolder.
  ///
  /// In vi, this message translates to:
  /// **'Chọn folder'**
  String get chooseFolder;

  /// No description provided for @selectedFiles.
  ///
  /// In vi, this message translates to:
  /// **'Đã chọn'**
  String get selectedFiles;

  /// No description provided for @clearList.
  ///
  /// In vi, this message translates to:
  /// **'Xóa danh sách'**
  String get clearList;

  /// No description provided for @removeFile.
  ///
  /// In vi, this message translates to:
  /// **'Bỏ file'**
  String get removeFile;

  /// No description provided for @send.
  ///
  /// In vi, this message translates to:
  /// **'Gửi'**
  String get send;

  /// No description provided for @sendTo.
  ///
  /// In vi, this message translates to:
  /// **'Gửi tới'**
  String get sendTo;

  /// No description provided for @receiveFrom.
  ///
  /// In vi, this message translates to:
  /// **'Nhận từ'**
  String get receiveFrom;

  /// No description provided for @incomingFileTitle.
  ///
  /// In vi, this message translates to:
  /// **'Nhận file?'**
  String get incomingFileTitle;

  /// No description provided for @incomingFileNotificationTitle.
  ///
  /// In vi, this message translates to:
  /// **'Có file gửi tới OpenCB'**
  String get incomingFileNotificationTitle;

  /// No description provided for @wantsToSend.
  ///
  /// In vi, this message translates to:
  /// **'muốn gửi'**
  String get wantsToSend;

  /// No description provided for @moreFiles.
  ///
  /// In vi, this message translates to:
  /// **'khác'**
  String get moreFiles;

  /// No description provided for @accept.
  ///
  /// In vi, this message translates to:
  /// **'Nhận'**
  String get accept;

  /// No description provided for @fileSentSuccess.
  ///
  /// In vi, this message translates to:
  /// **'Đã gửi file thành công.'**
  String get fileSentSuccess;

  /// No description provided for @fileSendPartialDone.
  ///
  /// In vi, this message translates to:
  /// **'Đã gửi xong'**
  String get fileSendPartialDone;

  /// No description provided for @fileSentTo.
  ///
  /// In vi, this message translates to:
  /// **'Đã gửi file tới'**
  String get fileSentTo;

  /// No description provided for @cannotReadSelectedFileOrFolder.
  ///
  /// In vi, this message translates to:
  /// **'Không đọc được file hoặc folder đã chọn.'**
  String get cannotReadSelectedFileOrFolder;

  /// No description provided for @cannotReadSelectedFile.
  ///
  /// In vi, this message translates to:
  /// **'Không đọc được file đã chọn.'**
  String get cannotReadSelectedFile;

  /// No description provided for @chooseFileOrFolderFirst.
  ///
  /// In vi, this message translates to:
  /// **'Chọn file hoặc folder trước.'**
  String get chooseFileOrFolderFirst;

  /// No description provided for @chooseOnlineDeviceFirst.
  ///
  /// In vi, this message translates to:
  /// **'Chọn ít nhất một thiết bị online.'**
  String get chooseOnlineDeviceFirst;

  /// No description provided for @fileReceivedDone.
  ///
  /// In vi, this message translates to:
  /// **'Đã nhận xong file.'**
  String get fileReceivedDone;

  /// No description provided for @devicePairing.
  ///
  /// In vi, this message translates to:
  /// **'Ghép thiết bị mới'**
  String get devicePairing;

  /// No description provided for @enterPayload.
  ///
  /// In vi, this message translates to:
  /// **'Nhập payload'**
  String get enterPayload;

  /// No description provided for @scanQr.
  ///
  /// In vi, this message translates to:
  /// **'Quét QR'**
  String get scanQr;

  /// No description provided for @pairedDevices.
  ///
  /// In vi, this message translates to:
  /// **'Thiết bị đã ghép'**
  String get pairedDevices;

  /// No description provided for @addDevice.
  ///
  /// In vi, this message translates to:
  /// **'Thêm thiết bị'**
  String get addDevice;

  /// No description provided for @noPairedDevices.
  ///
  /// In vi, this message translates to:
  /// **'Chưa ghép thiết bị LAN nào.'**
  String get noPairedDevices;

  /// No description provided for @pairedDeviceHint.
  ///
  /// In vi, this message translates to:
  /// **'Khi thiết bị được xác nhận bằng mã hoặc QR, thiết bị sẽ xuất hiện ở đây.'**
  String get pairedDeviceHint;

  /// No description provided for @visibleDevices.
  ///
  /// In vi, this message translates to:
  /// **'Thiết bị đang thấy'**
  String get visibleDevices;

  /// No description provided for @noVisibleDevices.
  ///
  /// In vi, this message translates to:
  /// **'Chưa thấy thiết bị OpenCB khác. Hãy mở app trên thiết bị cùng Wi-Fi/VPN.'**
  String get noVisibleDevices;

  /// No description provided for @found.
  ///
  /// In vi, this message translates to:
  /// **'tìm thấy'**
  String get found;

  /// No description provided for @connect.
  ///
  /// In vi, this message translates to:
  /// **'Kết nối'**
  String get connect;

  /// No description provided for @pair.
  ///
  /// In vi, this message translates to:
  /// **'Ghép nối'**
  String get pair;

  /// No description provided for @paired.
  ///
  /// In vi, this message translates to:
  /// **'Đã kết nối'**
  String get paired;

  /// No description provided for @notPaired.
  ///
  /// In vi, this message translates to:
  /// **'Chưa ghép nối thiết bị.'**
  String get notPaired;

  /// No description provided for @seen.
  ///
  /// In vi, this message translates to:
  /// **'thấy'**
  String get seen;

  /// No description provided for @thisDevice.
  ///
  /// In vi, this message translates to:
  /// **'Thiết bị này'**
  String get thisDevice;

  /// No description provided for @renameThisDevice.
  ///
  /// In vi, this message translates to:
  /// **'Đổi tên thiết bị này'**
  String get renameThisDevice;

  /// No description provided for @qrPairing.
  ///
  /// In vi, this message translates to:
  /// **'QR pairing'**
  String get qrPairing;

  /// No description provided for @copyPayload.
  ///
  /// In vi, this message translates to:
  /// **'Copy payload'**
  String get copyPayload;

  /// No description provided for @testConnection.
  ///
  /// In vi, this message translates to:
  /// **'Test kết nối'**
  String get testConnection;

  /// No description provided for @renameDevice.
  ///
  /// In vi, this message translates to:
  /// **'Đổi tên thiết bị'**
  String get renameDevice;

  /// No description provided for @syncDevice.
  ///
  /// In vi, this message translates to:
  /// **'Sync thiết bị'**
  String get syncDevice;

  /// No description provided for @removeDevice.
  ///
  /// In vi, this message translates to:
  /// **'Xóa thiết bị'**
  String get removeDevice;

  /// No description provided for @deviceName.
  ///
  /// In vi, this message translates to:
  /// **'Tên thiết bị'**
  String get deviceName;

  /// No description provided for @addLanDevice.
  ///
  /// In vi, this message translates to:
  /// **'Thêm thiết bị LAN'**
  String get addLanDevice;

  /// No description provided for @pairPayload.
  ///
  /// In vi, this message translates to:
  /// **'Payload pairing'**
  String get pairPayload;

  /// No description provided for @pastePairPayloadHint.
  ///
  /// In vi, this message translates to:
  /// **'Dán opencb://pair?... từ máy kia'**
  String get pastePairPayloadHint;

  /// No description provided for @applyPayload.
  ///
  /// In vi, this message translates to:
  /// **'Áp dụng payload'**
  String get applyPayload;

  /// No description provided for @hostAndPort.
  ///
  /// In vi, this message translates to:
  /// **'Host và port'**
  String get hostAndPort;

  /// No description provided for @peerPairCode.
  ///
  /// In vi, this message translates to:
  /// **'Mã pairing của thiết bị kia'**
  String get peerPairCode;

  /// No description provided for @pairPayloadInvalid.
  ///
  /// In vi, this message translates to:
  /// **'Payload không hợp lệ. Hãy dán mã bắt đầu bằng opencb://pair.'**
  String get pairPayloadInvalid;

  /// No description provided for @hostPortInvalid.
  ///
  /// In vi, this message translates to:
  /// **'Host và port không hợp lệ.'**
  String get hostPortInvalid;

  /// No description provided for @pairCodeTooShort.
  ///
  /// In vi, this message translates to:
  /// **'Mã pairing phải có ít nhất 6 ký tự.'**
  String get pairCodeTooShort;

  /// No description provided for @confirmConnection.
  ///
  /// In vi, this message translates to:
  /// **'Xác nhận kết nối'**
  String get confirmConnection;

  /// No description provided for @enterCodeShownOnPeer.
  ///
  /// In vi, this message translates to:
  /// **'Nhập mã đang hiển thị trên thiết bị kia.'**
  String get enterCodeShownOnPeer;

  /// No description provided for @codeOnPeer.
  ///
  /// In vi, this message translates to:
  /// **'Mã trên thiết bị kia'**
  String get codeOnPeer;

  /// No description provided for @scanQrInstead.
  ///
  /// In vi, this message translates to:
  /// **'Quét QR thay vì nhập mã'**
  String get scanQrInstead;

  /// No description provided for @invalidQrPairing.
  ///
  /// In vi, this message translates to:
  /// **'QR pairing không hợp lệ.'**
  String get invalidQrPairing;

  /// No description provided for @qrBelongsToOtherDevice.
  ///
  /// In vi, this message translates to:
  /// **'QR này thuộc thiết bị khác.'**
  String get qrBelongsToOtherDevice;

  /// No description provided for @pairDeviceQuestion.
  ///
  /// In vi, this message translates to:
  /// **'Ghép thiết bị?'**
  String get pairDeviceQuestion;

  /// No description provided for @wantsToPairWithThisDevice.
  ///
  /// In vi, this message translates to:
  /// **'muốn ghép nối với OpenCB trên thiết bị này.'**
  String get wantsToPairWithThisDevice;

  /// No description provided for @removeSyncDeviceTitle.
  ///
  /// In vi, this message translates to:
  /// **'Xóa thiết bị sync?'**
  String get removeSyncDeviceTitle;

  /// No description provided for @removeSyncDeviceBodyPrefix.
  ///
  /// In vi, this message translates to:
  /// **'Thiết bị'**
  String get removeSyncDeviceBodyPrefix;

  /// No description provided for @removeSyncDeviceBodySuffix.
  ///
  /// In vi, this message translates to:
  /// **'sẽ bị xóa khỏi danh sách tin cậy. Nếu thiết bị kia đang online, OpenCB cũng sẽ gỡ kết nối ở bên đó.'**
  String get removeSyncDeviceBodySuffix;

  /// No description provided for @connectionSuccess.
  ///
  /// In vi, this message translates to:
  /// **'Kết nối thành công.'**
  String get connectionSuccess;

  /// No description provided for @connectionFailedPrefix.
  ///
  /// In vi, this message translates to:
  /// **'Không kết nối được'**
  String get connectionFailedPrefix;

  /// No description provided for @online.
  ///
  /// In vi, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @recentlySeen.
  ///
  /// In vi, this message translates to:
  /// **'Vừa thấy'**
  String get recentlySeen;

  /// No description provided for @offline.
  ///
  /// In vi, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @justNow.
  ///
  /// In vi, this message translates to:
  /// **'Vừa xong'**
  String get justNow;

  /// No description provided for @minuteAgo.
  ///
  /// In vi, this message translates to:
  /// **'phút trước'**
  String get minuteAgo;

  /// No description provided for @hourAgo.
  ///
  /// In vi, this message translates to:
  /// **'giờ trước'**
  String get hourAgo;

  /// No description provided for @dayAgo.
  ///
  /// In vi, this message translates to:
  /// **'ngày trước'**
  String get dayAgo;

  /// No description provided for @lastSyncPrefix.
  ///
  /// In vi, this message translates to:
  /// **'Sync lần cuối'**
  String get lastSyncPrefix;

  /// No description provided for @neverSynced.
  ///
  /// In vi, this message translates to:
  /// **'Chưa từng sync'**
  String get neverSynced;

  /// No description provided for @captureClipboard.
  ///
  /// In vi, this message translates to:
  /// **'Bắt clipboard'**
  String get captureClipboard;

  /// No description provided for @capturePausedSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Tạm dừng toàn bộ việc lưu clipboard mới.'**
  String get capturePausedSubtitle;

  /// No description provided for @captureEnabledSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Theo dõi clipboard trong nền.'**
  String get captureEnabledSubtitle;

  /// No description provided for @textAndUrl.
  ///
  /// In vi, this message translates to:
  /// **'Văn bản và URL'**
  String get textAndUrl;

  /// No description provided for @textAndUrlSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Lưu text, tự nhận diện URL để mở nhanh.'**
  String get textAndUrlSubtitle;

  /// No description provided for @images.
  ///
  /// In vi, this message translates to:
  /// **'Hình ảnh'**
  String get images;

  /// No description provided for @imagesSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Lưu ảnh clipboard khi app nguồn cung cấp dữ liệu ảnh.'**
  String get imagesSubtitle;

  /// No description provided for @fileFolderPaths.
  ///
  /// In vi, this message translates to:
  /// **'Đường dẫn file/folder'**
  String get fileFolderPaths;

  /// No description provided for @fileFolderPathsSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Chỉ lưu đường dẫn, không lưu nội dung file thật.'**
  String get fileFolderPathsSubtitle;

  /// No description provided for @autoPasteQuickPicker.
  ///
  /// In vi, this message translates to:
  /// **'Tự dán từ chọn nhanh'**
  String get autoPasteQuickPicker;

  /// No description provided for @autoPasteQuickPickerSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Khi chọn item trong quick picker, tự paste vào ô đang nhập.'**
  String get autoPasteQuickPickerSubtitle;

  /// No description provided for @ignoreBatteryOptimization.
  ///
  /// In vi, this message translates to:
  /// **'Bỏ qua tối ưu pin'**
  String get ignoreBatteryOptimization;

  /// No description provided for @ignoreBatteryOptimizationSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Tùy chọn thêm nếu Sync LAN chưa ổn định.'**
  String get ignoreBatteryOptimizationSubtitle;

  /// No description provided for @notificationSettings.
  ///
  /// In vi, this message translates to:
  /// **'Cài đặt thông báo'**
  String get notificationSettings;

  /// No description provided for @windowsAutoStart.
  ///
  /// In vi, this message translates to:
  /// **'Tự mở cùng Windows'**
  String get windowsAutoStart;

  /// No description provided for @windowsAutoStartSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Đăng ký OpenCB trong Startup của tài khoản hiện tại.'**
  String get windowsAutoStartSubtitle;

  /// No description provided for @quickOpenHotkey.
  ///
  /// In vi, this message translates to:
  /// **'Phím tắt mở chọn nhanh'**
  String get quickOpenHotkey;

  /// No description provided for @disabled.
  ///
  /// In vi, this message translates to:
  /// **'Đang tắt'**
  String get disabled;

  /// No description provided for @changeHotkey.
  ///
  /// In vi, this message translates to:
  /// **'Đổi phím tắt'**
  String get changeHotkey;

  /// No description provided for @storage.
  ///
  /// In vi, this message translates to:
  /// **'Lưu trữ'**
  String get storage;

  /// No description provided for @excludedApps.
  ///
  /// In vi, this message translates to:
  /// **'Ứng dụng loại trừ'**
  String get excludedApps;

  /// No description provided for @excludedAppsSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Không lưu clipboard khi nguồn thuộc danh sách này.'**
  String get excludedAppsSubtitle;

  /// No description provided for @sourceAppName.
  ///
  /// In vi, this message translates to:
  /// **'Tên ứng dụng nguồn'**
  String get sourceAppName;

  /// No description provided for @noExcludedApps.
  ///
  /// In vi, this message translates to:
  /// **'Chưa loại trừ ứng dụng nào.'**
  String get noExcludedApps;

  /// No description provided for @tagLibrary.
  ///
  /// In vi, this message translates to:
  /// **'Thư viện thẻ'**
  String get tagLibrary;

  /// No description provided for @attachTags.
  ///
  /// In vi, this message translates to:
  /// **'Gắn thẻ'**
  String get attachTags;

  /// No description provided for @attachedTags.
  ///
  /// In vi, this message translates to:
  /// **'Đang gắn'**
  String get attachedTags;

  /// No description provided for @noTags.
  ///
  /// In vi, this message translates to:
  /// **'Chưa có thẻ'**
  String get noTags;

  /// No description provided for @createEditTag.
  ///
  /// In vi, this message translates to:
  /// **'Tạo/Sửa thẻ'**
  String get createEditTag;

  /// No description provided for @newTagPreview.
  ///
  /// In vi, this message translates to:
  /// **'thẻ-mới'**
  String get newTagPreview;

  /// No description provided for @tagName.
  ///
  /// In vi, this message translates to:
  /// **'Tên thẻ'**
  String get tagName;

  /// No description provided for @addOrUpdate.
  ///
  /// In vi, this message translates to:
  /// **'Thêm/Cập nhật'**
  String get addOrUpdate;

  /// No description provided for @customColor.
  ///
  /// In vi, this message translates to:
  /// **'Màu tùy chỉnh'**
  String get customColor;

  /// No description provided for @applyColor.
  ///
  /// In vi, this message translates to:
  /// **'Áp dụng màu'**
  String get applyColor;

  /// No description provided for @selectClipboardPreview.
  ///
  /// In vi, this message translates to:
  /// **'Chọn một mục clipboard để xem trước và sao chép lại.'**
  String get selectClipboardPreview;

  /// No description provided for @copyToClipboard.
  ///
  /// In vi, this message translates to:
  /// **'Copy vào clipboard'**
  String get copyToClipboard;

  /// No description provided for @openUrlTooltip.
  ///
  /// In vi, this message translates to:
  /// **'Mở URL bằng trình duyệt mặc định'**
  String get openUrlTooltip;

  /// No description provided for @openFileLocationTooltip.
  ///
  /// In vi, this message translates to:
  /// **'Mở thư mục chứa file'**
  String get openFileLocationTooltip;

  /// No description provided for @deleteClipboard.
  ///
  /// In vi, this message translates to:
  /// **'Xóa clipboard'**
  String get deleteClipboard;

  /// No description provided for @deletedClipboard.
  ///
  /// In vi, this message translates to:
  /// **'Đã xóa clipboard.'**
  String get deletedClipboard;

  /// No description provided for @deletedClipboardPrefix.
  ///
  /// In vi, this message translates to:
  /// **'Đã xóa'**
  String get deletedClipboardPrefix;

  /// No description provided for @deletedClipboardSuffix.
  ///
  /// In vi, this message translates to:
  /// **'clipboard.'**
  String get deletedClipboardSuffix;

  /// No description provided for @cleanClipboardTitle.
  ///
  /// In vi, this message translates to:
  /// **'Dọn clipboard'**
  String get cleanClipboardTitle;

  /// No description provided for @noUnpinnedClipboardToClean.
  ///
  /// In vi, this message translates to:
  /// **'Không có clipboard chưa ghim để dọn.'**
  String get noUnpinnedClipboardToClean;

  /// No description provided for @cleanClipboardBodyPrefix.
  ///
  /// In vi, this message translates to:
  /// **'Xóa'**
  String get cleanClipboardBodyPrefix;

  /// No description provided for @cleanClipboardBodySuffix.
  ///
  /// In vi, this message translates to:
  /// **'mục chưa ghim khỏi lịch sử.'**
  String get cleanClipboardBodySuffix;

  /// No description provided for @undo.
  ///
  /// In vi, this message translates to:
  /// **'Hoàn tác'**
  String get undo;

  /// No description provided for @clearAllHistoryTitle.
  ///
  /// In vi, this message translates to:
  /// **'Xóa toàn bộ lịch sử?'**
  String get clearAllHistoryTitle;

  /// No description provided for @historyAlreadyEmpty.
  ///
  /// In vi, this message translates to:
  /// **'Lịch sử clipboard đang trống.'**
  String get historyAlreadyEmpty;

  /// No description provided for @clearAllHistoryBodyPrefix.
  ///
  /// In vi, this message translates to:
  /// **'Thao tác này sẽ xóa'**
  String get clearAllHistoryBodyPrefix;

  /// No description provided for @clearAllHistoryBodySuffix.
  ///
  /// In vi, this message translates to:
  /// **'mục clipboard đang lưu. Cài đặt, thẻ và thiết bị sync vẫn được giữ lại.'**
  String get clearAllHistoryBodySuffix;

  /// No description provided for @deleteHistory.
  ///
  /// In vi, this message translates to:
  /// **'Xóa lịch sử'**
  String get deleteHistory;

  /// No description provided for @close.
  ///
  /// In vi, this message translates to:
  /// **'Đóng'**
  String get close;

  /// No description provided for @openMainApp.
  ///
  /// In vi, this message translates to:
  /// **'Mở app chính'**
  String get openMainApp;

  /// No description provided for @pinQuickPicker.
  ///
  /// In vi, this message translates to:
  /// **'Ghim quick picker'**
  String get pinQuickPicker;

  /// No description provided for @quickPickerPinned.
  ///
  /// In vi, this message translates to:
  /// **'Đang ghim quick picker'**
  String get quickPickerPinned;

  /// No description provided for @showAllClipboards.
  ///
  /// In vi, this message translates to:
  /// **'Hiện tất cả clipboard'**
  String get showAllClipboards;

  /// No description provided for @showPinnedOnly.
  ///
  /// In vi, this message translates to:
  /// **'Chỉ hiện mục đã ghim'**
  String get showPinnedOnly;

  /// No description provided for @expandPreview.
  ///
  /// In vi, this message translates to:
  /// **'Phóng to preview'**
  String get expandPreview;

  /// No description provided for @collapsePreview.
  ///
  /// In vi, this message translates to:
  /// **'Thu nhỏ preview'**
  String get collapsePreview;

  /// No description provided for @pinThisItem.
  ///
  /// In vi, this message translates to:
  /// **'Ghim mục này'**
  String get pinThisItem;

  /// No description provided for @unpinThisItem.
  ///
  /// In vi, this message translates to:
  /// **'Bỏ ghim mục này'**
  String get unpinThisItem;

  /// No description provided for @selected.
  ///
  /// In vi, this message translates to:
  /// **'đã chọn'**
  String get selected;

  /// No description provided for @selectVisible.
  ///
  /// In vi, this message translates to:
  /// **'Chọn tất cả đang hiển thị'**
  String get selectVisible;

  /// No description provided for @deselectVisible.
  ///
  /// In vi, this message translates to:
  /// **'Bỏ chọn tất cả đang hiển thị'**
  String get deselectVisible;

  /// No description provided for @exitBulkSelect.
  ///
  /// In vi, this message translates to:
  /// **'Thoát chọn nhiều'**
  String get exitBulkSelect;

  /// No description provided for @createTag.
  ///
  /// In vi, this message translates to:
  /// **'Tạo thẻ'**
  String get createTag;

  /// No description provided for @selectMultiple.
  ///
  /// In vi, this message translates to:
  /// **'Chọn nhiều'**
  String get selectMultiple;

  /// No description provided for @scrollToTop.
  ///
  /// In vi, this message translates to:
  /// **'Lên đầu trang'**
  String get scrollToTop;

  /// No description provided for @selectedItemsAction.
  ///
  /// In vi, this message translates to:
  /// **'Thao tác với mục đã chọn'**
  String get selectedItemsAction;

  /// No description provided for @noSelectedItems.
  ///
  /// In vi, this message translates to:
  /// **'Chưa chọn mục nào'**
  String get noSelectedItems;

  /// No description provided for @done.
  ///
  /// In vi, this message translates to:
  /// **'Xong'**
  String get done;

  /// No description provided for @deleted.
  ///
  /// In vi, this message translates to:
  /// **'Đã xóa'**
  String get deleted;

  /// No description provided for @noMatchingSelectedTags.
  ///
  /// In vi, this message translates to:
  /// **'Không tìm thấy clipboard phù hợp với thẻ đã chọn.'**
  String get noMatchingSelectedTags;

  /// No description provided for @noItemsInSelectedTags.
  ///
  /// In vi, this message translates to:
  /// **'Không có clipboard nào trong thẻ đã chọn.'**
  String get noItemsInSelectedTags;

  /// No description provided for @noMatchingPinned.
  ///
  /// In vi, this message translates to:
  /// **'Không tìm thấy clipboard đã ghim phù hợp.'**
  String get noMatchingPinned;

  /// No description provided for @noMatchingClipboard.
  ///
  /// In vi, this message translates to:
  /// **'Không tìm thấy clipboard phù hợp.'**
  String get noMatchingClipboard;

  /// No description provided for @currentVersion.
  ///
  /// In vi, this message translates to:
  /// **'Phiên bản hiện tại'**
  String get currentVersion;

  /// No description provided for @checking.
  ///
  /// In vi, this message translates to:
  /// **'Đang check'**
  String get checking;

  /// No description provided for @check.
  ///
  /// In vi, this message translates to:
  /// **'Check'**
  String get check;

  /// No description provided for @autoCheckUpdatesEnabled.
  ///
  /// In vi, this message translates to:
  /// **'OpenCB tự kiểm tra khi mở app.'**
  String get autoCheckUpdatesEnabled;

  /// No description provided for @autoCheckUpdatesDisabled.
  ///
  /// In vi, this message translates to:
  /// **'Tắt tự động, vẫn có thể check thủ công.'**
  String get autoCheckUpdatesDisabled;

  /// No description provided for @unsupportedHotkey.
  ///
  /// In vi, this message translates to:
  /// **'Phím này chưa được hỗ trợ.'**
  String get unsupportedHotkey;

  /// No description provided for @hotkeyNeedsModifier.
  ///
  /// In vi, this message translates to:
  /// **'Hãy dùng ít nhất một phím Ctrl, Alt, Shift hoặc Win.'**
  String get hotkeyNeedsModifier;

  /// No description provided for @pressHotkeyInstruction.
  ///
  /// In vi, this message translates to:
  /// **'Nhấn tổ hợp phím muốn dùng để mở chọn nhanh.'**
  String get pressHotkeyInstruction;

  /// No description provided for @latestVersionMessage.
  ///
  /// In vi, this message translates to:
  /// **'Bạn đang dùng bản mới nhất.'**
  String get latestVersionMessage;

  /// No description provided for @newVersionAvailable.
  ///
  /// In vi, this message translates to:
  /// **'Có bản mới'**
  String get newVersionAvailable;

  /// No description provided for @checkingUpdatesMessage.
  ///
  /// In vi, this message translates to:
  /// **'Đang kiểm tra...'**
  String get checkingUpdatesMessage;

  /// No description provided for @cannotCheckUpdatesMessage.
  ///
  /// In vi, this message translates to:
  /// **'Không kiểm tra được. Kiểm tra mạng hoặc quyền truy cập release.'**
  String get cannotCheckUpdatesMessage;

  /// No description provided for @cannotCheckUpdates.
  ///
  /// In vi, this message translates to:
  /// **'Không kiểm tra được cập nhật.'**
  String get cannotCheckUpdates;

  /// No description provided for @later.
  ///
  /// In vi, this message translates to:
  /// **'Để sau'**
  String get later;

  /// No description provided for @updateReadyWindows.
  ///
  /// In vi, this message translates to:
  /// **'OpenCB sẽ tải bộ cài, kiểm tra file rồi tự đóng ứng dụng để cài đè phiên bản mới.'**
  String get updateReadyWindows;

  /// No description provided for @updateReadyAndroid.
  ///
  /// In vi, this message translates to:
  /// **'OpenCB sẽ tải APK, kiểm tra file rồi mở màn hình cài đặt của Android.'**
  String get updateReadyAndroid;

  /// No description provided for @updateAssetUnavailable.
  ///
  /// In vi, this message translates to:
  /// **'Không tìm thấy file cài đặt phù hợp. Bạn có thể mở trang tải xuống.'**
  String get updateAssetUnavailable;

  /// No description provided for @downloadAndInstall.
  ///
  /// In vi, this message translates to:
  /// **'Tải và cài đặt'**
  String get downloadAndInstall;

  /// No description provided for @downloadApk.
  ///
  /// In vi, this message translates to:
  /// **'Tải APK'**
  String get downloadApk;

  /// No description provided for @openDownloadPage.
  ///
  /// In vi, this message translates to:
  /// **'Mở trang tải xuống'**
  String get openDownloadPage;

  /// No description provided for @downloadingUpdate.
  ///
  /// In vi, this message translates to:
  /// **'Đang tải bản cập nhật'**
  String get downloadingUpdate;

  /// No description provided for @cancelingUpdate.
  ///
  /// In vi, this message translates to:
  /// **'Đang hủy...'**
  String get cancelingUpdate;

  /// No description provided for @preparingUpdate.
  ///
  /// In vi, this message translates to:
  /// **'Đang chuẩn bị cài đặt...'**
  String get preparingUpdate;

  /// No description provided for @updateDownloadFailed.
  ///
  /// In vi, this message translates to:
  /// **'Không tải được bản cập nhật. Hãy kiểm tra mạng và thử lại.'**
  String get updateDownloadFailed;

  /// No description provided for @cannotOpenInstaller.
  ///
  /// In vi, this message translates to:
  /// **'Đã tải xong nhưng không mở được trình cài đặt.'**
  String get cannotOpenInstaller;

  /// No description provided for @retentionLimit.
  ///
  /// In vi, this message translates to:
  /// **'Giới hạn lưu'**
  String get retentionLimit;

  /// No description provided for @retentionLimitClipboard.
  ///
  /// In vi, this message translates to:
  /// **'Giới hạn lưu clipboard'**
  String get retentionLimitClipboard;

  /// No description provided for @themeOpenCbTeal.
  ///
  /// In vi, this message translates to:
  /// **'Xanh OpenCB'**
  String get themeOpenCbTeal;

  /// No description provided for @themeForestGreen.
  ///
  /// In vi, this message translates to:
  /// **'Xanh Rừng'**
  String get themeForestGreen;

  /// No description provided for @themeBaselinePurple.
  ///
  /// In vi, this message translates to:
  /// **'Tím'**
  String get themeBaselinePurple;

  /// No description provided for @themeSerenity.
  ///
  /// In vi, this message translates to:
  /// **'Serenity'**
  String get themeSerenity;

  /// No description provided for @themeRoseQuartz.
  ///
  /// In vi, this message translates to:
  /// **'Rose Quartz'**
  String get themeRoseQuartz;

  /// No description provided for @themeSunsetCoral.
  ///
  /// In vi, this message translates to:
  /// **'San Hô Hoàng Hôn'**
  String get themeSunsetCoral;

  /// No description provided for @themeMonoBlackWhite.
  ///
  /// In vi, this message translates to:
  /// **'Đen trắng'**
  String get themeMonoBlackWhite;

  /// No description provided for @themeBlueGrey.
  ///
  /// In vi, this message translates to:
  /// **'Blue Grey'**
  String get themeBlueGrey;

  /// No description provided for @restoreDataTitle.
  ///
  /// In vi, this message translates to:
  /// **'Khôi phục dữ liệu?'**
  String get restoreDataTitle;

  /// No description provided for @restoreDataBodyPrefix.
  ///
  /// In vi, this message translates to:
  /// **'Nhập'**
  String get restoreDataBodyPrefix;

  /// No description provided for @restoreDataBodySuffix.
  ///
  /// In vi, this message translates to:
  /// **'clipboard từ backup. Dữ liệu hiện có sẽ được giữ lại và gộp thêm dữ liệu trong file.'**
  String get restoreDataBodySuffix;

  /// No description provided for @restoreAction.
  ///
  /// In vi, this message translates to:
  /// **'Khôi phục'**
  String get restoreAction;

  /// No description provided for @restoredClipboardPrefix.
  ///
  /// In vi, this message translates to:
  /// **'Đã khôi phục'**
  String get restoredClipboardPrefix;

  /// No description provided for @restoredClipboardSuffix.
  ///
  /// In vi, this message translates to:
  /// **'clipboard.'**
  String get restoredClipboardSuffix;

  /// No description provided for @bulkPinned.
  ///
  /// In vi, this message translates to:
  /// **'Đã ghim các mục đã chọn.'**
  String get bulkPinned;

  /// No description provided for @bulkUnpinned.
  ///
  /// In vi, this message translates to:
  /// **'Đã bỏ ghim.'**
  String get bulkUnpinned;

  /// No description provided for @bulkTaggedPrefix.
  ///
  /// In vi, this message translates to:
  /// **'Đã gắn thẻ cho'**
  String get bulkTaggedPrefix;

  /// No description provided for @bulkTaggedSuffix.
  ///
  /// In vi, this message translates to:
  /// **'.'**
  String get bulkTaggedSuffix;

  /// No description provided for @lanDiagnostics.
  ///
  /// In vi, this message translates to:
  /// **'Chẩn đoán LAN'**
  String get lanDiagnostics;

  /// No description provided for @lanDiagnosticsSubtitle.
  ///
  /// In vi, this message translates to:
  /// **'Trạng thái discovery, server và kết nối thiết bị'**
  String get lanDiagnosticsSubtitle;

  /// No description provided for @refreshDiagnostics.
  ///
  /// In vi, this message translates to:
  /// **'Làm mới'**
  String get refreshDiagnostics;

  /// No description provided for @exportLog.
  ///
  /// In vi, this message translates to:
  /// **'Xuất log'**
  String get exportLog;

  /// No description provided for @localServices.
  ///
  /// In vi, this message translates to:
  /// **'Dịch vụ cục bộ'**
  String get localServices;

  /// No description provided for @syncServer.
  ///
  /// In vi, this message translates to:
  /// **'Sync server'**
  String get syncServer;

  /// No description provided for @fileServer.
  ///
  /// In vi, this message translates to:
  /// **'File server'**
  String get fileServer;

  /// No description provided for @lanDiscovery.
  ///
  /// In vi, this message translates to:
  /// **'LAN discovery'**
  String get lanDiscovery;

  /// No description provided for @running.
  ///
  /// In vi, this message translates to:
  /// **'Đang chạy'**
  String get running;

  /// No description provided for @stopped.
  ///
  /// In vi, this message translates to:
  /// **'Đã dừng'**
  String get stopped;

  /// No description provided for @foreground.
  ///
  /// In vi, this message translates to:
  /// **'Tiền cảnh'**
  String get foreground;

  /// No description provided for @background.
  ///
  /// In vi, this message translates to:
  /// **'Chạy nền'**
  String get background;

  /// No description provided for @screenAwake.
  ///
  /// In vi, this message translates to:
  /// **'Màn hình bật'**
  String get screenAwake;

  /// No description provided for @screenSleeping.
  ///
  /// In vi, this message translates to:
  /// **'Màn hình tắt'**
  String get screenSleeping;

  /// No description provided for @beaconInterval.
  ///
  /// In vi, this message translates to:
  /// **'Nhịp beacon'**
  String get beaconInterval;

  /// No description provided for @connectionDetails.
  ///
  /// In vi, this message translates to:
  /// **'Chi tiết kết nối'**
  String get connectionDetails;

  /// No description provided for @recentEvents.
  ///
  /// In vi, this message translates to:
  /// **'Sự kiện gần đây'**
  String get recentEvents;

  /// No description provided for @noDiagnosticEvents.
  ///
  /// In vi, this message translates to:
  /// **'Chưa có sự kiện chẩn đoán.'**
  String get noDiagnosticEvents;

  /// No description provided for @beaconReceived.
  ///
  /// In vi, this message translates to:
  /// **'Đang nhận beacon'**
  String get beaconReceived;

  /// No description provided for @remoteSleeping.
  ///
  /// In vi, this message translates to:
  /// **'Thiết bị đã báo đang ngủ'**
  String get remoteSleeping;

  /// No description provided for @beaconExpired.
  ///
  /// In vi, this message translates to:
  /// **'Beacon đã hết hạn'**
  String get beaconExpired;

  /// No description provided for @beaconNeverSeen.
  ///
  /// In vi, this message translates to:
  /// **'Chưa nhận được beacon'**
  String get beaconNeverSeen;

  /// No description provided for @lastPing.
  ///
  /// In vi, this message translates to:
  /// **'Ping gần nhất'**
  String get lastPing;

  /// No description provided for @notMeasured.
  ///
  /// In vi, this message translates to:
  /// **'Chưa đo'**
  String get notMeasured;

  /// No description provided for @exportCrashReport.
  ///
  /// In vi, this message translates to:
  /// **'Xuất báo cáo sự cố'**
  String get exportCrashReport;

  /// No description provided for @crashReportExportedPrefix.
  ///
  /// In vi, this message translates to:
  /// **'Đã xuất báo cáo sự cố vào'**
  String get crashReportExportedPrefix;

  /// No description provided for @cannotExportCrashReport.
  ///
  /// In vi, this message translates to:
  /// **'Không xuất được báo cáo sự cố.'**
  String get cannotExportCrashReport;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
