import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nsd/nsd.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Name save korar jonno

import '../../core/services/permission_service.dart';
import '../../core/services/server_service.dart';
import '../../core/services/discovery_service.dart';
import '../../core/services/client_service.dart';
import '../../core/services/auto_updater_service.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final PermissionService _permissionService = PermissionService();
  final ServerService _serverService = ServerService();
  final DiscoveryService _discoveryService = DiscoveryService();
  final ClientService _clientService = ClientService();
  
  bool _isReady = false;
  String _localIP = "0.0.0.0";
  String _myDeviceName = "Loading..."; // Custom Device Name
  
  // Transfer State Variables
  bool _isTransferring = false;
  double _progressValue = 0.0;
  String _transferStatus = "";
  
  String _debugMessage = "Initializing...";
  List<Service> _discoveredDevices = [];
  
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeSystem();
  }

  Future<void> _initializeSystem() async {
    try {
      if (Platform.isAndroid) {
        if (mounted) setState(() => _debugMessage = "Requesting permissions...");
        await [
          Permission.nearbyWifiDevices,
          Permission.location,
          Permission.storage,
          Permission.manageExternalStorage,
        ].request();
      }

      // ----------------------------------------------------
      // Load Custom Device Name from Memory
      // ----------------------------------------------------
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String defaultName = Platform.isAndroid ? "Android Device" : "Windows PC";
      _myDeviceName = prefs.getString('custom_device_name') ?? defaultName;

      if (mounted) setState(() => _debugMessage = "Locating network...");
      
      String deviceIP = "0.0.0.0";
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            if (!addr.address.startsWith("100.")) {
              deviceIP = addr.address;
              break;
            }
          }
        }
        if (deviceIP != "0.0.0.0") break;
      }

      if (deviceIP == "0.0.0.0") {
        if (mounted) {
          setState(() {
            _isReady = false;
            _debugMessage = "No Local Network Found";
          });
        }
        return; 
      }

      await _serverService.startServer();
      
      _serverService.onUploadRequested = (filename, size, senderIp) async {
        return await showDialog<bool>(
          context: context,
          barrierDismissible: false, 
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.cloud_download_outlined, color: Colors.blue[800], size: 28),
                  SizedBox(width: 12),
                  Text('File Request', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: RichText(
                text: TextSpan(
                  style: TextStyle(color: Colors.black87, fontSize: 15, height: 1.5),
                  children: [
                    TextSpan(text: 'Device '),
                    TextSpan(text: senderIp, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                    TextSpan(text: ' is sending:\n\n'),
                    TextSpan(text: '$filename\n', style: TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: 'Size: $size MB', style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Decline', style: TextStyle(color: Colors.red[400], fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true), 
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text('Accept', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        ) ?? false; 
      };

      _serverService.onTransferProgress = (percentage) {
        if (mounted) {
          setState(() {
            _isTransferring = true;
            _progressValue = percentage;
            _transferStatus = "Receiving...";
          });
          if (percentage >= 1.0) {
            setState(() {
              _transferStatus = "Completed";
              Future.delayed(Duration(seconds: 2), () {
                if (mounted) setState(() => _isTransferring = false);
              });
            });
          }
        }
      };

      // Network Broadcasting starts with Custom Name
      await _discoveryService.startBroadcasting(_myDeviceName, 4000);

      await _discoveryService.startScanning(
        onDeviceFound: (Service service) {
          if (mounted) {
            setState(() {
              if (service.name != _myDeviceName) {
                if (!_discoveredDevices.any((d) => d.name == service.name)) {
                  _discoveredDevices.add(service);
                } else {
                  int index = _discoveredDevices.indexWhere((d) => d.name == service.name);
                  _discoveredDevices[index] = service;
                }
              }
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _localIP = deviceIP;
          _isReady = true; 
        });
        
        // App ready howar sathe sathe chupchap update check korbe
        AutoUpdaterService.checkForUpdates(context);
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _isReady = false;
          _debugMessage = "System Error Occurred";
        });
      }
    }
  }

  // ----------------------------------------------------
  // Device Name Change Logic
  // ----------------------------------------------------
  Future<void> _showEditNameDialog() async {
    _nameController.text = _myDeviceName;
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Edit Device Name', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: "E.g., Rokon's Phone",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.blue[800]!, width: 2)
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () async {
                String newName = _nameController.text.trim();
                if (newName.isNotEmpty) {
                  SharedPreferences prefs = await SharedPreferences.getInstance();
                  await prefs.setString('custom_device_name', newName);
                  
                  setState(() => _myDeviceName = newName);
                  
                  // Restart Broadcast so other devices see the new name instantly
                  await _discoveryService.stopAll();
                  _discoveredDevices.clear();
                  await _discoveryService.startBroadcasting(_myDeviceName, 4000);
                  await _discoveryService.startScanning(
                    onDeviceFound: (Service service) {
                      if (mounted) {
                        setState(() {
                          if (service.name != _myDeviceName) {
                            if (!_discoveredDevices.any((d) => d.name == service.name)) {
                              _discoveredDevices.add(service);
                            } else {
                              int index = _discoveredDevices.indexWhere((d) => d.name == service.name);
                              _discoveredDevices[index] = service;
                            }
                          }
                        });
                      }
                    },
                  );
                  Navigator.of(context).pop();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickAndSendFile(String targetIp) async {
    FilePickerResult? result = await FilePicker.pickFiles();
    
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24, 
                    height: 24, 
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.blue[800])
                  ),
                  SizedBox(width: 16),
                  Text("Preparing secure transfer...", style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        },
      );

      await Future.delayed(Duration(milliseconds: 500));
      Navigator.pop(context);

      setState(() {
        _isTransferring = true;
        _progressValue = 0.0;
        _transferStatus = "Awaiting receiver's approval...";
      });

      await _clientService.sendFile(
        targetIp: targetIp,
        file: file,
        onProgress: (percentage) {
          if (mounted) {
            setState(() {
              _progressValue = percentage;
              _transferStatus = "Sending data...";
            });
          }
        },
        onComplete: (message) {
          if (mounted) {
            setState(() {
              _progressValue = 1.0;
              _transferStatus = "Sent Successfully";
              Future.delayed(Duration(seconds: 2), () {
                if (mounted) setState(() => _isTransferring = false);
              });
            });
          }
        },
        onError: (errorMessage) {
          if (mounted) {
            setState(() {
              _isTransferring = false;
              _progressValue = 0.0;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage, style: TextStyle(color: Colors.white)), 
                backgroundColor: Colors.red[800],
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            );
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _serverService.stopServer();
    _discoveryService.stopAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Row(
          children: [
            // ----------------------------------------------------
            // Custom In-App Logo Section
            // ----------------------------------------------------
            Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8)
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/logo.png', // Apnar custom logo load hocche
                  width: 26, 
                  height: 26, 
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    // Jodi kono karone logo load na hoy, tahole default icon dekhabe
                    return Icon(Icons.water_drop_rounded, color: Colors.blue[800], size: 26);
                  },
                ),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Local Drop', 
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.5)
            ),
          ],
        ),
        actions: [
          Center(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 20.0),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _serverService.isRunning ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: _serverService.isRunning ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    _serverService.isRunning ? "Online" : "Offline",
                    style: TextStyle(
                      color: _serverService.isRunning ? Colors.green[800] : Colors.red[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 12
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ---------------- HEADER & RADAR ----------------
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: Offset(0, 5))
                ]
              ),
              child: Column(
                children: [
                  _isReady 
                    ? PulseRadar() 
                    : Icon(Icons.wifi_off_rounded, size: 60, color: Colors.grey[300]),
                  SizedBox(height: 20),
                  
                  // ----------------------------------------------------
                  // Display Device Name with Edit Option
                  // ----------------------------------------------------
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isReady ? _myDeviceName : 'Awaiting Network',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black87),
                      ),
                      if (_isReady) ...[
                        SizedBox(width: 8),
                        InkWell(
                          onTap: _showEditNameDialog,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.edit_rounded, size: 18, color: Colors.blue[700]),
                          ),
                        )
                      ]
                    ],
                  ),
                  
                  // ----------------------------------------------------
                  // IP Address (Smaller Size)
                  // ----------------------------------------------------
                  if (_isReady) ...[
                    SizedBox(height: 4),
                    Text(
                      'IP: $_localIP:4000',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[500]),
                    ),
                  ],

                  SizedBox(height: 8),
                  Text(
                    _isReady ? "Discoverable on local network" : _debugMessage,
                    style: TextStyle(fontSize: 14, color: _isReady ? Colors.green[600] : Colors.red[400], fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            // ---------------- ACTIVE TRANSFER CARD ----------------
            if (_isTransferring)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.withOpacity(0.1)),
                    boxShadow: [
                      BoxShadow(color: Colors.blue.withOpacity(0.05), blurRadius: 20, spreadRadius: 5)
                    ]
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(Icons.swap_calls_rounded, color: Colors.blue[800]),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _transferStatus, 
                                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "${(_progressValue * 100).toStringAsFixed(0)}%",
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800], fontSize: 16),
                          )
                        ],
                      ),
                      SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: _progressValue,
                          minHeight: 8,
                          backgroundColor: Colors.grey[100],
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            SizedBox(height: 20),
            
            // ---------------- DEVICES LIST ----------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                children: [
                  Text('Nearby Devices', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                  Spacer(),
                  if (_isReady)
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[400])
                    )
                ],
              ),
            ),
            
            SizedBox(height: 10),

            Expanded(
              child: _discoveredDevices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.devices_rounded, size: 48, color: Colors.grey[300]),
                        SizedBox(height: 16),
                        Text(
                          _isReady ? 'Looking for devices...' : 'Offline',
                          style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    itemCount: _discoveredDevices.length,
                    itemBuilder: (context, index) {
                      final device = _discoveredDevices[index];
                      String ip = 'Resolving...';
                      if (device.addresses != null && device.addresses!.isNotEmpty) {
                        ip = device.addresses!.first.address;
                      } else if (device.host != null) {
                        ip = device.host!;
                      }
                      
                      return Container(
                        margin: EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: Offset(0, 2))
                          ]
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(12)
                            ),
                            child: Icon(Icons.laptop_mac_rounded, color: Colors.blue[800]),
                          ),
                          title: Text(device.name ?? 'Unknown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          subtitle: Text(ip, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                          trailing: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue[800],
                              shape: BoxShape.circle
                            ),
                            child: IconButton(
                              icon: Icon(Icons.send_rounded, color: Colors.white, size: 18),
                              onPressed: () {
                                if (ip != 'Resolving...') {
                                  _pickAndSendFile(ip);
                                }
                              },
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

// ==========================================
// PREMIUM PULSE RADAR (Minimalist)
// ==========================================
class PulseRadar extends StatefulWidget {
  @override
  _PulseRadarState createState() => _PulseRadarState();
}

class _PulseRadarState extends State<PulseRadar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          painter: PulsePainter(_controller),
          child: SizedBox(width: 100, height: 100),
        ),
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[800],
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 15, spreadRadius: 2)
            ]
          ),
          child: Icon(Icons.wifi_tethering_rounded, color: Colors.white, size: 32),
        ),
      ],
    );
  }
}

class PulsePainter extends CustomPainter {
  final Animation<double> animation;
  PulsePainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity((1.0 - animation.value).clamp(0.0, 0.2))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(size.center(Offset.zero), (size.width / 2) * animation.value, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}