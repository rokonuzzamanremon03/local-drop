import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:dio/dio.dart';

class AutoUpdaterService {
  // Ekhane apnar ashol GitHub repository deya holo
  static const String repoName = "rokonuzzamanremon03/local-drop";

  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      // 1. App er bortoman version check kora (pubspec.yaml theke)
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version; // Jemon: "1.0.0"

      // 2. GitHub theke latest release check kora
      final response = await http.get(Uri.parse('https://api.github.com/repos/$repoName/releases/latest'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String latestVersionTag = data['tag_name']; // Jemon: "v1.0.1"
        String latestVersion = latestVersionTag.replaceAll('v', ''); // "1.0.1"
        String releaseNotes = data['body'] ?? "Minor bug fixes and improvements.";

        // 3. Version compare kora (Jodi GitHub er ta notun hoy)
        if (latestVersion != currentVersion) {
          String apkUrl = "";
          String windowsUrl = "";

          // GitHub er assets theke APK ar ZIP er link khuje ber kora
          for (var asset in data['assets']) {
            if (asset['name'].endsWith('.apk')) {
              apkUrl = asset['browser_download_url'];
            } else if (asset['name'].endsWith('.zip')) {
              windowsUrl = asset['browser_download_url'];
            }
          }

          // 4. Update Popup show kora
          if (context.mounted) {
            _showUpdateDialog(context, latestVersion, releaseNotes, apkUrl, windowsUrl);
          }
        }
      }
    } catch (e) {
      debugPrint("Auto Updater Error: $e");
    }
  }

  static void _showUpdateDialog(BuildContext context, String newVersion, String releaseNotes, String apkUrl, String windowsUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        bool isDownloading = false;
        double downloadProgress = 0.0;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.system_update_rounded, color: Colors.blue[800], size: 28),
                  SizedBox(width: 10),
                  Text("Update Available!", style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Version $newVersion is now available.", style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 10),
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                    child: Text(releaseNotes, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  ),
                  if (isDownloading) ...[
                    SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: downloadProgress,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
                    ),
                    SizedBox(height: 5),
                    Text("Downloading... ${(downloadProgress * 100).toStringAsFixed(0)}%", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[800])),
                  ]
                ],
              ),
              actions: [
                if (!isDownloading)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text("Later", style: TextStyle(color: Colors.grey[600])),
                  ),
                if (!isDownloading)
                  ElevatedButton(
                    onPressed: () async {
                      if (Platform.isAndroid && apkUrl.isNotEmpty) {
                        setState(() => isDownloading = true);
                        try {
                          final tempDir = await getTemporaryDirectory();
                          final savePath = "${tempDir.path}/localdrop_update.apk";
                          
                          await Dio().download(
                            apkUrl, 
                            savePath,
                            onReceiveProgress: (received, total) {
                              if (total != -1) {
                                setState(() => downloadProgress = received / total);
                              }
                            }
                          );
                          
                          Navigator.pop(dialogContext); // Close dialog
                          await OpenFilex.open(savePath); // Install APK
                        } catch (e) {
                          setState(() => isDownloading = false);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to download update.")));
                        }
                      } else if (Platform.isWindows && windowsUrl.isNotEmpty) {
                        launchUrl(Uri.parse(windowsUrl), mode: LaunchMode.externalApplication);
                        Navigator.pop(dialogContext);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                    ),
                    child: Text("Update Now", style: TextStyle(color: Colors.white)),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}