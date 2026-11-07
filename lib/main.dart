import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

const String kAppName = 'MVD Supply Chain';
const String kHomeUrl = 'https://mvdsupplychain.com/shop-cart/';
const Color kBrandColor = Color(0xFF123B65);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MvdSupplyChainApp());
}

class MvdSupplyChainApp extends StatelessWidget {
  const MvdSupplyChainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kBrandColor),
        useMaterial3: true,
      ),
      home: const ShopWebView(),
    );
  }
}

class ShopWebView extends StatefulWidget {
  const ShopWebView({super.key});

  @override
  State<ShopWebView> createState() => _ShopWebViewState();
}

class _ShopWebViewState extends State<ShopWebView> {
  static const Set<String> _externalSchemes = <String>{
    'tel',
    'mailto',
    'sms',
    'smsto',
    'whatsapp',
    'upi',
    'geo',
    'maps',
    'market',
    'intent',
  };

  static const Set<String> _downloadExtensions = <String>{
    'pdf',
    'zip',
    'rar',
    '7z',
    'apk',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
  };

  late final WebViewController _controller;

  bool _isLoading = true;
  bool _isFirstLoad = true;
  bool _hasError = false;
  int _progress = 0;
  String? _errorMessage;
  String? _failedUrl;
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onProgress: (int progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (String url) {
            if (!mounted) return;
            _lastBackPress = null;
            setState(() {
              _isLoading = true;
              _hasError = false;
              _errorMessage = null;
              _progress = 0;
            });
          },
          onPageFinished: (String url) async {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _isFirstLoad = false;
              _progress = 100;
            });
            await _injectPageHelpers();
          },
          onWebResourceError: (WebResourceError error) {
            if (_isCancelledError(error)) {
              debugPrint('Navigation cancelled: ${error.description}');
              return;
            }
            if (error.isForMainFrame ?? true) {
              _showError(error.description, error.url);
            } else {
              debugPrint('Sub-resource error: ${error.description}');
            }
          },
        ),
      );

    _configurePlatform();
    _controller.loadRequest(Uri.parse(kHomeUrl));
  }

  Future<void> _configurePlatform() async {
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        _controller.platform is WebKitWebViewController) {
      try {
        await (_controller.platform as WebKitWebViewController)
            .setAllowsBackForwardNavigationGestures(true);
      } catch (error) {
        debugPrint('Could not enable iOS swipe navigation: $error');
      }
    }
  }

  Future<NavigationDecision> _onNavigationRequest(
    NavigationRequest request,
  ) async {
    final Uri? uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      if (request.isMainFrame && _looksLikeDownload(uri)) {
        final bool opened = await _launchExternal(uri);
        if (!opened) _showSnack('Could not open this file.');
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    }

    if (uri.scheme == 'about' ||
        uri.scheme == 'data' ||
        uri.scheme == 'blob' ||
        uri.scheme == 'javascript') {
      return NavigationDecision.navigate;
    }

    if (_externalSchemes.contains(uri.scheme)) {
      final bool opened = await _launchExternal(uri);
      if (!opened) _showSnack('No app found to open this link.');
      return NavigationDecision.prevent;
    }

    return NavigationDecision.prevent;
  }

  bool _isCancelledError(WebResourceError error) {
    // ERR_ABORTED (Android) and NSURLErrorCancelled (iOS) happen when a
    // navigation is replaced by a redirect or a newer request. They are not
    // real failures and must not replace the page with an error screen.
    return error.errorCode == -3 || error.errorCode == -999;
  }

  bool _looksLikeDownload(Uri uri) {
    if (uri.pathSegments.isEmpty) return false;
    final String name = uri.pathSegments.last;
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return false;
    return _downloadExtensions.contains(
      name.substring(dot + 1).toLowerCase(),
    );
  }

  Future<bool> _launchExternal(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('Could not open $uri: $error');
      return false;
    }
  }

  Future<void> _injectPageHelpers() async {
    const String script = r'''
      (function () {
        if (window.__mvdAppReady) { return; }
        window.__mvdAppReady = true;
        window.open = function (url) {
          if (url && typeof url === 'string') { window.location.assign(url); }
          return window;
        };
        document.addEventListener('click', function (event) {
          var node = event.target;
          while (node && node.tagName !== 'A') { node = node.parentElement; }
          if (node && node.tagName === 'A' && node.target === '_blank' && node.href) {
            event.preventDefault();
            window.location.assign(node.href);
          }
        }, true);
      })();
    ''';
    try {
      await _controller.runJavaScript(script);
    } catch (error) {
      debugPrint('JS helper injection failed: $error');
    }
  }

  Future<void> _handleBack() async {
    if (await _controller.canGoBack()) {
      _lastBackPress = null;
      await _controller.goBack();
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) return;

    final DateTime now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) <= const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }

    _lastBackPress = now;
    _showSnack('Press back again to exit');
  }

  void _showError(String message, String? url) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isFirstLoad = false;
      _hasError = true;
      _errorMessage = message;
      _failedUrl = url;
    });
  }

  void _retry() {
    if (!mounted) return;
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _isLoading = true;
      _isFirstLoad = true;
      _progress = 0;
    });
    Uri target;
    try {
      target = Uri.parse(_failedUrl ?? kHomeUrl);
    } catch (_) {
      target = Uri.parse(kHomeUrl);
    }
    _controller.loadRequest(target);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _handleBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: <Widget>[
                if (_isLoading && !_hasError)
                  LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress / 100,
                    minHeight: 3,
                    backgroundColor: Colors.transparent,
                    color: kBrandColor,
                  ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      WebViewWidget(controller: _controller),
                      if (_isFirstLoad && !_hasError) _buildSplash(),
                      if (_hasError) _buildErrorView(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSplash() {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.asset(
              'assets/images/logo/app_logo_new.png',
              width: 110,
              height: 110,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 18),
            const Text(
              kAppName,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kBrandColor,
              ),
            ),
            const SizedBox(height: 22),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Unable to load the page',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Please check your internet connection.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
