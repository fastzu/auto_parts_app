import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';
import '../config/env_config.dart';
import '../theme/app_theme.dart';

/// بانر Google AdMob منظّم وذكي (يُعرض بمكان واحد مرتب داخل المتجر ويستهدف السيارات والمال فقط)
class AdMobNativeBanner extends StatefulWidget {
  const AdMobNativeBanner({super.key});

  @override
  State<AdMobNativeBanner> createState() => _AdMobNativeBannerState();
}

class _AdMobNativeBannerState extends State<AdMobNativeBanner> {
  static bool _sdkInitialized = false;
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  bool get _isMobileSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (EnvConfig.adsEnabled.value) {
      _initAndLoad();
    }
    EnvConfig.adsEnabled.addListener(_onToggleChanged);
  }

  void _onToggleChanged() {
    if (EnvConfig.adsEnabled.value) {
      _initAndLoad();
    } else {
      _disposeAd();
    }
  }

  Future<void> _initAndLoad() async {
    if (!_isMobileSupported || _bannerAd != null) return;
    try {
      if (!_sdkInitialized) {
        await MobileAds.instance.initialize();
        _sdkInitialized = true;
      }
      final unitId = defaultTargetPlatform == TargetPlatform.iOS
          ? EnvConfig.admobIosBannerId
          : EnvConfig.admobAndroidBannerId;

      final ad = BannerAd(
        adUnitId: unitId,
        size: AdSize.banner,
        // استهداف إعلانات متعلقة بالسيارات والصيانة والتأمين والتمويل والمال فقط
        request: const AdRequest(
          keywords: [
            'auto parts',
            'car maintenance',
            'car insurance',
            'auto finance',
            'banking',
            'investment',
            'قطع غيار سيارات',
            'صيانة سيارات',
            'تأمين سيارات',
            'تمويل سيارات',
            'بنوك ومال',
          ],
        ),
        listener: BannerAdListener(
          onAdLoaded: (loadedAd) {
            if (!mounted) {
              loadedAd.dispose();
              return;
            }
            setState(() {
              _bannerAd = loadedAd as BannerAd;
              _isLoaded = true;
            });
          },
          onAdFailedToLoad: (failedAd, _) {
            failedAd.dispose();
            if (mounted) {
              setState(() {
                _bannerAd = null;
                _isLoaded = false;
              });
            }
          },
        ),
      );
      await ad.load();
    } catch (_) {}
  }

  void _disposeAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    if (mounted) setState(() => _isLoaded = false);
  }

  @override
  void dispose() {
    EnvConfig.adsEnabled.removeListener(_onToggleChanged);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EnvConfig.adsEnabled,
      builder: (_, enabled, __) {
        if (!enabled || !_isMobileSupported || !_isLoaded || _bannerAd == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.navy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'إعلان مموّل · سيارات وتمويل',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: SizedBox(
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}