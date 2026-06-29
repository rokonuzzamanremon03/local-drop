import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:convert';

class ClientService {
  final String secretToken = "AuthToken_V1_Remon";

  Future<void> sendFile({
    required String targetIp,
    required File file,
    required Function(double) onProgress,
    required Function(String) onComplete,
    required Function(String) onError,
  }) async {
    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final fileSize = await file.length();
      
      // ==========================================
      // PHASE 1: STRICT HANDSHAKE (Ask Permission)
      // ==========================================
      final requestUri = Uri.parse('http://$targetIp:4000/request-transfer');
      
      try {
        final askResponse = await http.post(requestUri, headers: {
          'x-auth-token': secretToken,
          'x-filename': fileName,
          'x-filesize': fileSize.toString(),
        }).timeout(Duration(seconds: 30)); // 30 seconds wait korbe user accept korar jonno

        if (askResponse.statusCode == 403) {
          onError("Transfer declined by the receiver.");
          return; // Strictly Stop Here
        } else if (askResponse.statusCode != 200) {
          onError("Handshake failed. Error: ${askResponse.statusCode}");
          return;
        }

        // Response e 'accepted' na thakle jabe na
        final responseBody = jsonDecode(askResponse.body);
        if (responseBody['status'] != 'accepted') {
          onError("Transfer not accepted by receiver.");
          return;
        }
      } catch (e) {
         onError("Receiver did not respond in time or declined.");
         return;
      }

      // ==========================================
      // PHASE 2: ACTUAL TRANSFER (Only if Accepted)
      // ==========================================
      final uploadUri = Uri.parse('http://$targetIp:4000/upload');
      final request = http.StreamedRequest('POST', uploadUri);
      
      request.headers['x-auth-token'] = secretToken;
      request.headers['x-filename'] = fileName;
      request.headers['x-filesize'] = fileSize.toString();

      final responseFuture = request.send();
      final fileStream = file.openRead();
      int bytesSent = 0;

      final mappedStream = fileStream.map((chunk) {
        bytesSent += chunk.length;
        onProgress(bytesSent / fileSize);
        return chunk;
      });

      await request.sink.addStream(mappedStream);
      request.sink.close();

      final response = await responseFuture;
      
      if (response.statusCode == 200) {
        onComplete("Transfer successful");
      } else {
        onError("Transfer failed: Error Code ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Client Error: $e");
      onError("Connection failed. Target device unreachable.");
    }
  }
}