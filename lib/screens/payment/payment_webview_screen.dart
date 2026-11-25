import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../theme/app_theme.dart';

class PaymentWebViewScreen extends StatefulWidget {
  final String redirectUrl;
  final String title;

  /// دالة التحقق السيرفري من تأكيد بوابة الدفع (Webhook) قبل إرجاع true
  final Future<bool> Function()? onVerifyServer;

  const PaymentWebViewScreen({
    super.key,
    required this.redirectUrl,
    required this.title,
    this.onVerifyServer,
  });

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _webController;
  bool _isLoading = true;
  bool _verifying = false;
  bool _finished = false;
  String _verifyStatusText = 'جاري التحقق من تأكيد البنك...';

  bool _isFailureOrCancelUrl(String url) {
    final lower = url.toLowerCase();
    final uri = Uri.tryParse(url);
    final qp = uri?.queryParameters ?? const <String, String>{};

    final statusVal = (qp['status'] ??
            qp['result'] ??
            qp['respStatus'] ??
            qp['payment_status'] ??
            '')
        .toLowerCase();

    const failTokens = [
      'cancel',
      'cancelled',
      'canceled',
      'fail',
      'failed',
      'failure',
      'declin',
      'declined',
      'reject',
      'rejected',
      'abort',
      'aborted',
      'error',
      'void',
      'expired',
    ];

    if (statusVal == 'e' || statusVal == 'd' || statusVal == 'c') {
      return true;
    }
    for (final token in failTokens) {
      if (statusVal.contains(token) || lower.contains('status=$token') || lower.contains('result=$token')) {
        return true;
      }
    }
    return false;
  }

  bool _isReturnWebhookUrl(String url) {
    final lower = url.toLowerCase();
    return (lower.contains('payment-webhook') && lower.contains('mode=return')) ||
        lower.contains('payment-return') ||
        lower.contains('meps-return');
  }

  Future<void> _handleReturnUrl(String url) async {
    if (_finished || _verifying || !mounted) return;

    // 1) رفض فوري إذا رابط الرجوع فيه فشل أو إلغاء
    if (_isFailureOrCancelUrl(url)) {
      _finished = true;
      if (mounted) Navigator.of(context).pop(false);
      return;
    }

    // 2) التحقق الإجباري من السيرفر (Webhook) قبل أي تأكيد
    setState(() {
      _verifying = true;
      _verifyStatusText = 'جاري التحقق من تأكيد بوابة الدفع...';
    });

    bool confirmed = false;
    if (widget.onVerifyServer != null) {
      // نعطي Webhook البنك حتى 5 محاولات (7.5 ثانية) لتأكيد القيد في قاعدة البيانات
      for (int attempt = 1; attempt <= 5; attempt++) {
        if (!mounted || _finished) return;
        if (attempt > 1) {
          setState(() {
            _verifyStatusText =
                'بانتظار تأكيد البنك ($attempt / 5)... لا تغلق الشاشة';
          });
        }
        try {
          final ok = await widget.onVerifyServer!();
          if (ok) {
            confirmed = true;
            break;
          }
        } catch (_) {}
        if (attempt < 5) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }
    } else {
      // في حال عدم تمرير دالة تحقق، لا يُقبل الدفع إلا بوجود مؤشر نجاح صريح بالرابط
      final lower = url.toLowerCase();
      confirmed = lower.contains('status=paid') ||
          lower.contains('status=success') ||
          lower.contains('status=approved') ||
          lower.contains('result=success');
    }

    if (!mounted || _finished) return;
    _finished = true;
    Navigator.of(context).pop(confirmed);
  }

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() => _isLoading = true);
            if (_isFailureOrCancelUrl(url) && _isReturnWebhookUrl(url)) {
              _handleReturnUrl(url);
            }
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            if (_isReturnWebhookUrl(url)) {
              _handleReturnUrl(url);
            }
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.redirectUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_verifying,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            widget.title,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _verifying
                ? null
                : () {
                    _finished = true;
                    Navigator.of(context).pop(false);
                  },
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _webController),
            if (_isLoading && !_verifying)
              const LinearProgressIndicator(color: AppColors.orange),
            if (_verifying)
              Container(
                color: Colors.black.withValues(alpha: 0.65),
                alignment: Alignment.center,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.orange),
                      const SizedBox(height: 16),
                      Text(
                        _verifyStatusText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'يتم مطابقة العملية مباشرة مع بوابة الدفع لضمان أمان حسابك',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}