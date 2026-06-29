import 'dart:io';
import 'package:alfred/alfred.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class ServerService {
  final alfred = Alfred();
  bool isRunning = false;
  final String secretToken = "AuthToken_V1_Remon"; 
  
  Future<bool> Function(String filename, String size, String senderIp)? onUploadRequested;
  Function(double percentage)? onTransferProgress;

  // Ashol 'Downloads' folder khuje ber korar Master Logic
  Future<Directory> _getPublicDownloadDir() async {
    Directory? directory;
    
    if (Platform.isAndroid) {
      // Android er ashol public download folder
      directory = Directory('/storage/emulated/0/Download');
    } else {
      // Windows / PC er download folder
      directory = await getDownloadsDirectory();
    }

    // Downloads er vitore amader app er nam e ekta folder toiri kora
    final localDropDir = Directory('${directory!.path}/LocalDrop');
    if (!await localDropDir.exists()) {
      await localDropDir.create(recursive: true);
    }
    
    return localDropDir;
  }

  Future<void> startServer() async {
    if (isRunning) return;

    // Security Gatekeeper (Shob request er jonno)
    alfred.all('*', (req, res) {
      final token = req.headers.value('x-auth-token');
      if (token != secretToken && req.uri.path != '/') {
        res.statusCode = 403;
        return {'error': 'Unauthorized connection attempt'};
      }
    });

    // ==========================================
    // ROUTE 1: HANDSHAKE (Shudhu UI Popup dekhabe)
    // ==========================================
    alfred.post('/request-transfer', (req, res) async {
      final filename = req.headers.value('x-filename') ?? 'transfer_file';
      final fileSizeStr = req.headers.value('x-filesize') ?? '0';
      final totalSize = int.parse(fileSizeStr);
      final fileSizeFormatted = (totalSize / (1024 * 1024)).toStringAsFixed(2);
      
      final senderIp = req.connectionInfo?.remoteAddress.address ?? 'Unknown IP';

      if (onUploadRequested != null) {
        bool isAccepted = await onUploadRequested!(filename, fileSizeFormatted, senderIp);
        
        if (!isAccepted) {
          res.statusCode = 403;
          debugPrint("Transfer rejected by user");
          return {'status': 'rejected', 'message': 'Transfer declined by receiver'};
        }
      }
      
      return {'status': 'accepted', 'message': 'Ready to receive'};
    });

    // ==========================================
    // ROUTE 2: UPLOAD (Actual file stream receive korbe)
    // ==========================================
    alfred.post('/upload', (req, res) async {
      final directory = await _getPublicDownloadDir(); 
      final filename = req.headers.value('x-filename') ?? 'transfer_file';
      final totalSize = int.parse(req.headers.value('x-filesize') ?? '0');
      
      final file = File('${directory.path}/$filename');
      final sink = file.openWrite();

      int downloaded = 0;
      
      await req.forEach((chunk) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (totalSize > 0 && onTransferProgress != null) {
          onTransferProgress!(downloaded / totalSize);
        }
      });

      await sink.close();
      return {'status': 'success', 'path': file.path};
    });

    await alfred.listen(4000, '0.0.0.0'); 
    isRunning = true;
  }

  Future<void> stopServer() async {
    if (!isRunning) return;
    await alfred.close();
    isRunning = false;
  }
}