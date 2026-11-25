import 'package:material_ui/material_ui.dart';

class AppLocaleService {
  AppLocaleService._();
  static final AppLocaleService instance = AppLocaleService._();

  /// 'ar' للعربية | 'en' للإنجليزية
  final ValueNotifier<String> langCode = ValueNotifier<String>('ar');

  bool get isEnglish => langCode.value == 'en';
  bool get isArabic => !isEnglish;

  TextDirection get textDirection =>
      isEnglish ? TextDirection.ltr : TextDirection.rtl;

  Locale get locale => Locale(langCode.value);

  void toggleLanguage() {
    langCode.value = isEnglish ? 'ar' : 'en';
  }

  void setLanguage(String code) {
    if (code == 'ar' || code == 'en') {
      langCode.value = code;
    }
  }

  String tr(String ar, String en) => isEnglish ? en : ar;
}