import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../theme/app_theme.dart';

class PaymentWebViewScreen extends StatefulWidget {
  final String redirectUrl;
  final String title;

  const PaymentWebViewScreen({
    super.key,
    required this.redirectUrl,
    required this.title,
  });

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _webController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            if (url.contains('payment-webhook') && url.contains('mode=return')) {
              Future.delayed(const Duration(milliseconds: 900), () {
                if (mounted) {
                  Navigator.of(context).pop(true);
                }
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.redirectUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webController),
          if (_isLoading)
            const LinearProgressIndicator(color: AppColors.orange),
        ],
      ),
    );
  }
}