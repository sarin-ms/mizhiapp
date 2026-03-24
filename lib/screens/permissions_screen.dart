import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _cameraGranted = false;
  bool _micGranted = false;
  bool _contactsGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;
    final contactsStatus = await Permission.contacts.status;

    if (mounted) {
      setState(() {
        _cameraGranted = cameraStatus.isGranted;
        _micGranted = micStatus.isGranted;
        _contactsGranted = contactsStatus.isGranted;
      });
    }
  }

  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _cameraGranted = cameraStatus.isGranted;
      });
    }

    final micStatus = await Permission.microphone.request();
    if (mounted) {
      setState(() {
        _micGranted = micStatus.isGranted;
      });
    }

    final contactsStatus = await Permission.contacts.request();
    if (mounted) {
      setState(() {
        _contactsGranted = contactsStatus.isGranted;
      });
    }

    if (_cameraGranted && _micGranted && _contactsGranted) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please allow all permissions for Mizhi to work"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildPermissionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isGranted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),  // Extra padding to match the icon background in the image
            decoration: BoxDecoration(
              color: const Color(0xFF262A3D), // Slightly lighter background for the icon
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF00D4AA),
              size: 36,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (isGranted)
            const Icon(
              Icons.check_circle,
              color: Colors.green,
            )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E21),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              SystemNavigator.pop();
            }
          },
        ),
        title: const Text(
          "MIZHI",
          style: TextStyle(
            color: Color(0xFF00D4AA), // teal center bold 18sp
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0, // slight letter spacing matches overall brand
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                // Large shield icon
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF161A2D), // dark icon background 
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.shield,
                    color: Color(0xFF00D4AA),
                    size: 80,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Before we begin",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Mizhi needs these permissions to guide you safely.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 32),
                
                _buildPermissionRow(
                  icon: Icons.camera_alt,
                  title: "Camera",
                  subtitle: "To see obstacles and read currency",
                  isGranted: _cameraGranted,
                ),
                _buildPermissionRow(
                  icon: Icons.mic,
                  title: "Microphone",
                  subtitle: "For voice commands",
                  isGranted: _micGranted,
                ),
                _buildPermissionRow(
                  icon: Icons.phone_android,
                  title: "Phone & Contacts",
                  subtitle: "For emergency alerts",
                  isGranted: _contactsGranted,
                ),
                
                const SizedBox(height: 32),
                
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: ElevatedButton(
                    onPressed: _requestPermissions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D4AA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Allow All & Continue →",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
