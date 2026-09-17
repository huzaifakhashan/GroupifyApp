import 'package:flutter/material.dart';
import 'package:groupify_app/Screens/groupChatScreen.dart';
import 'package:groupify_app/Services/groupInviteService.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final TextEditingController _inputController = TextEditingController();
  bool _isJoining = false;
  String? _error;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) {
      setState(() => _error = "أدخل كود المجموعة أو معرفها");
      return;
    }

    setState(() {
      _isJoining = true;
      _error = null;
    });

    try {
      final result = input.startsWith('@')
          ? await GroupInviteService.joinByUsername(input.substring(1))
          : await GroupInviteService.joinByCode(input);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            groupId: result.groupId,
            groupName: result.groupName,
          ),
        ),
      );
    } on GroupJoinException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = "تعذر الانضمام للمجموعة");
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A00E0),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "الانضمام لمجموعة",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Icon(Icons.groups, size: 64, color: Colors.indigo.shade300),
            const SizedBox(height: 16),
            const Text(
              "أدخل كود الدعوة (6 أرقام)، أو معرف المجموعة إذا كان إلها واحد (متل @معرف)",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _inputController,
              autofocus: true,
              textAlign: TextAlign.center,
              onSubmitted: (_) => _join(),
              style: const TextStyle(
                fontSize: 20,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: "123456 أو ‎@اسم_المجموعة",
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isJoining ? null : _join,
              child: _isJoining
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text("انضمام"),
            ),
          ],
        ),
      ),
    );
  }
}
