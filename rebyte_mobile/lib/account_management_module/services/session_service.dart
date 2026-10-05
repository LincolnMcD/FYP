import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

class SessionService {
  static const String _keyEmail = 'session_email';
  static const String _keyName = 'session_name';
  static const String _keyLoggedIn = 'session_logged_in';

  static Future<void> saveSession({required String email, required String name}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyName, name);
    await prefs.setBool(_keyLoggedIn, true);
  }

  static Future<Map<String, String?>> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_keyLoggedIn) ?? false;
    if (isLoggedIn) {
      return {
        'email': prefs.getString(_keyEmail),
        'name': prefs.getString(_keyName),
      };
    }
    return {};
  }

  static Future<void> clearSession() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    try {
      await FacebookAuth.instance.logOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
