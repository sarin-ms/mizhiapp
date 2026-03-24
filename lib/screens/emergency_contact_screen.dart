import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mizhi/utils/settings_helper.dart';

class EmergencyContactScreen extends StatefulWidget {
  const EmergencyContactScreen({super.key});

  @override
  State<EmergencyContactScreen> createState() => _EmergencyContactScreenState();
}

class _EmergencyContactScreenState extends State<EmergencyContactScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isSaving = false;

  final FlutterTts _flutterTts = FlutterTts();
  String? _focusedButton;

  Future<void> _handleButtonTap(
    String buttonId,
    String spokenText,
    VoidCallback action,
  ) async {
    if (_focusedButton == buttonId) {
      setState(() => _focusedButton = null);
      await _flutterTts.stop();
      action();
    } else {
      setState(() => _focusedButton = buttonId);
      await _flutterTts.stop();
      await _flutterTts.speak(spokenText);
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _focusedButton == buttonId) {
          setState(() => _focusedButton = null);
        }
      });
    }
  }

  static const _teal = Color(0xFF00D4AA);
  static const _bg = Color(0xFF0A0E21);
  static const _card = Color(0xFF1A1E35);

  @override
  void initState() {
    super.initState();
    _loadSaved();
    applyTtsSettings(_flutterTts);
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    _nameController.text = prefs.getString('mizhi_emergency_contact') ?? '';
    _phoneController.text = prefs.getString('mizhi_emergency_phone') ?? '';
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'mizhi_emergency_contact',
      _nameController.text.trim(),
    );
    await prefs.setString(
      'mizhi_emergency_phone',
      _phoneController.text.trim(),
    );
    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency contact saved'),
          backgroundColor: _teal,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, _nameController.text.trim());
    }
  }

  Future<void> _delete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('mizhi_emergency_contact');
    await prefs.remove('mizhi_emergency_phone');
    _nameController.clear();
    _phoneController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency contact removed'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, '');
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: _focusedButton == 'back_button' ? _teal : Colors.white,
          ),
          onPressed: () => _handleButtonTap(
            'back_button',
            'Go back',
            () => Navigator.pop(context),
          ),
        ),
        title: const Text(
          'EMERGENCY CONTACT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF3A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF4444), width: 1),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFFF4444),
                    size: 32,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This contact will be alerted in emergencies via voice command "Help me call".',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Name field
            const Text(
              'Contact Name',
              style: TextStyle(
                color: _teal,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'e.g. Mom, Dad, Guardian',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  prefixIcon: const Icon(Icons.person, color: _teal),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Phone field
            const Text(
              'Phone Number',
              style: TextStyle(
                color: _teal,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: '+91 98765 43210',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  prefixIcon: const Icon(Icons.phone, color: _teal),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () => _handleButtonTap(
                        'save_contact',
                        'Save contact',
                        _save,
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  side: _focusedButton == 'save_contact'
                      ? const BorderSide(color: Colors.white, width: 2)
                      : BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'SAVE CONTACT',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),

            // Delete button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => _handleButtonTap(
                  'remove_contact',
                  'Remove contact',
                  _delete,
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _focusedButton == 'remove_contact'
                        ? Colors.white
                        : const Color(0xFFFF4444),
                    width: _focusedButton == 'remove_contact' ? 2 : 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'REMOVE CONTACT',
                  style: TextStyle(
                    color: Color(0xFFFF4444),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
