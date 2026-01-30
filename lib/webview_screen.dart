import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewScreen extends StatefulWidget {
  final String url;

  const WebViewScreen({super.key, required this.url});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController controller;
  final Completer<WebViewController> controllerCompleter =
      Completer<WebViewController>();
  bool _isLoading = true;
  bool canGoBack = false;

  @override
  void initState() {
    super.initState();
    preloadWebView();
  }

  void preloadWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {},
          onPageStarted: (String url) async {
            bool backPossible = await controller.canGoBack();
            setState(() {
              canGoBack = backPossible;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onHttpError: (HttpResponseError error) {},
          onWebResourceError: (WebResourceError error) {},
          onNavigationRequest: (NavigationRequest request) async {
            // ✅ Handle intent:// links (Google Maps deep link ka redirect)
            if (request.url.startsWith("intent://")) {
              final newUrl = request.url
                  .replaceFirst("intent://", "https://"); // convert to https
              if (await canLaunchUrl(Uri.parse(newUrl))) {
                await launchUrl(Uri.parse(newUrl),
                    mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            }

            // ✅ Handle google maps normal links
            if (request.url.contains("maps.app.goo.gl") ||
                request.url.contains("maps.google.com")) {
              controller.loadRequest(Uri.parse(request.url));
              return NavigationDecision.navigate;
            }

            // ✅ External schemes
            if (request.url.startsWith('tel:') ||
                request.url.startsWith('whatsapp:')) {
              if (await canLaunchUrl(Uri.parse(request.url))) {
                await launchUrl(Uri.parse(request.url),
                    mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            } else if (request.url.contains("instagram.") ||
                request.url.contains("youtube.") ||
                request.url.contains("mailto:")) {
              openDeepLink(request.url);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    if (!controllerCompleter.isCompleted) {
      controllerCompleter.complete(controller);
    }
  }

  static const platform = MethodChannel('com.example.yourapp/deeplink');

  Future<void> openDeepLink(String url) async {
    try {
      await platform.invokeMethod('openDeepLink', {'url': url});
    } on PlatformException catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !canGoBack,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;

        if (canGoBack) {
          controller.goBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(toolbarHeight: 0),
        body: Stack(
          children: [
            WebViewWidget(controller: controller),
            if (Platform.isIOS && !_isLoading)
              Positioned(
                bottom: 30,
                right: MediaQuery.of(context).size.width * 0.4,
                child: FutureBuilder<WebViewController>(
                  future: controllerCompleter.future,
                  builder: (context, snapshot) {
                    final WebViewController? controller = snapshot.data;
                    if (controller == null) return Container();
                    return GestureDetector(
                      onTap: () async {
                        if (await controller.canGoBack()) {
                          controller.goBack();
                        } else {
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        }
                      },
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.5),
                              spreadRadius: 1,
                              blurRadius: 1,
                              offset: const Offset(1, 1),
                            ),
                          ],
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: 10, horizontal: 20),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.arrow_back_ios),
                              Text(
                                "Back",
                                style: TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
