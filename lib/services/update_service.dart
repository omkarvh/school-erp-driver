import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';

/// Once-per-run "update available" check against the backend's public
/// /api/v1/app-info endpoint (App Distribution Phase 4). Call
/// [UpdateService.maybePrompt] after the dashboard is up; it is totally
/// silent on any failure — an update prompt is never worth an error.
class UpdateService {
  UpdateService._();

  static bool _checked = false;

  // Mirrors main.dart AppColors (kept local to avoid importing main.dart).
  static const Color _primary = Color(0xFF0D1B2A);
  static const Color _accent = Color(0xFF00C9A7);

  static Future<void> maybePrompt(BuildContext context) async {
    if (_checked) return;
    _checked = true;

    try {
      final info = await PackageInfo.fromPlatform();

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/v1/app-info'
            '?app=driver&platform=android_apk&current=${Uri.encodeComponent(info.version)}'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      if (data is! Map || data['update_available'] != true) return;

      final latest = (data['latest_version'] ?? '').toString();
      final notes = (data['release_notes'] ?? '').toString();
      final playUrl = (data['play_url'] ?? '').toString();
      final downloadUrl = (data['download_url'] ?? '').toString();
      final url = playUrl.isNotEmpty ? playUrl : downloadUrl;
      if (latest.isEmpty || url.isEmpty) return;

      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _UpdateDialog(
          currentVersion: info.version,
          latestVersion: latest,
          releaseNotes: notes,
          url: url,
          viaStore: playUrl.isNotEmpty,
        ),
      );
    } catch (_) {
      // Offline, server old, endpoint missing — all fine, just no prompt.
    }
  }
}

class _UpdateDialog extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String url;
  final bool viaStore;

  const _UpdateDialog({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.url,
    required this.viaStore,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
            color: UpdateService._primary,
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.system_update_rounded,
                      color: UpdateService._primary, size: 36),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Update available',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: UpdateService._accent.withAlpha(28),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: UpdateService._accent.withAlpha(110)),
                  ),
                  child: Text(
                    'v$currentVersion  →  v$latestVersion',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: UpdateService._primary,
                    ),
                  ),
                ),
                if (releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    releaseNotes,
                    textAlign: TextAlign.center,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: UpdateService._accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      launchUrl(Uri.parse(url),
                          mode: LaunchMode.externalApplication);
                    },
                    icon: Icon(
                        viaStore
                            ? Icons.shop_rounded
                            : Icons.download_rounded,
                        size: 19),
                    label: Text(
                      viaStore ? 'Update on Google Play' : 'Download update',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Later',
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
