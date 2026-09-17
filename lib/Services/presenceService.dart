import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

class PresenceService with WidgetsBindingObserver {
  PresenceService._();

  static final PresenceService instance = PresenceService._();
  final _firestore = FirebaseFirestore.instance;
  String? _uid;

  Future<void> startFor(User? user) async {
    if (user == null || user.isAnonymous) {
      await stop();
      return;
    }

    if (_uid == user.uid) return;
    if (_uid != null) await _setOnline(false);
    _uid = user.uid;
    WidgetsBinding.instance.addObserver(this);
    await _setOnline(true);
  }

  Future<void> stop() async {
    if (_uid == null) return;
    await _setOnline(false);
    WidgetsBinding.instance.removeObserver(this);
    _uid = null;
  }

  Future<void> _setOnline(bool isOnline) async {
    final uid = _uid;
    if (uid == null) return;

    await _firestore.collection("users").doc(uid).set({
      "isOnline": isOnline,
      "lastSeen": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnline(true);
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setOnline(false);
    }
  }
}
