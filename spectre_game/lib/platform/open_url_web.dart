import 'package:web/web.dart' as web;

bool openUrl(String url) {
  final w = web.window.open(url, '_blank');
  return w != null;
}

String? currentQueryParam(String key) => Uri.tryParse(web.window.location.href)?.queryParameters[key];
