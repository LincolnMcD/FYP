import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'session_service.dart';

class AuthService {
  // Token revocation happens before this device can reauthenticate with the new
  // password. Pause local session polling during that short transition window.
  static bool passwordChangeInProgress = false;

  static String get baseUrl {
    // 192.168.100.185 explicitly targets the IPv4 host computer over local area network, perfectly unblocking physical devices/emulators natively.
    return 'http://192.168.100.185:3000';
  }

  static Future<Map<String, dynamic>> requestOTP(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/request-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 5));
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'message': body['message']};
      return {'success': false, 'error': body['error'] ?? 'Request failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }

  static Future<Map<String, dynamic>> requestForgotPasswordOtp(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/forgot-password/request-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 5));
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'message': body['message']};
      return {'success': false, 'error': body['error'] ?? 'Request failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }

  static Future<Map<String, dynamic>> verifyForgotPasswordOtp(String email, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/forgot-password/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      ).timeout(const Duration(seconds: 5));
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'message': body['message']};
      return {'success': false, 'error': body['error'] ?? 'Verification failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }

  static Future<Map<String, dynamic>> resetForgotPassword(String email, String newPassword, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/forgot-password/reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'newPassword': newPassword,
          'otp': otp
        }),
      ).timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'message': body['message']};
      return {'success': false, 'error': body['error'] ?? 'Reset failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }

  static Future<Map<String, dynamic>> verifyRegistrationOtp(String email, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/verify-registration-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      ).timeout(const Duration(seconds: 5));
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'message': body['message']};
      return {'success': false, 'error': body['error'] ?? 'Verification failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }

  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String otp,
    required String fullName,
    required String phoneNumber,
    required String gender,
    required String birthDate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'otp': otp,
          'fullName': fullName,
          'phoneNumber': phoneNumber,
          'gender': gender,
          'birthDate': birthDate,
        }),
      ).timeout(const Duration(seconds: 10));
      
      final body = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        String? sessionToken;
        try {
          final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
          sessionToken = await credential.user?.getIdToken();
        } catch (_) {
          // Keep registration successful if Firebase session restoration is unavailable.
        }
        return {'success': true, 'message': body['message'], 'token': sessionToken};
      } else {
        return {'success': false, 'error': body['error'] ?? 'Registration failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }

  static Future<Map<String, dynamic>> oauthLogin(String idToken, String provider) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/oauth-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken, 'loginMethod': provider, 'clientType': 'Mobile'}),
      ).timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true, 
          'message': body['message'],
          'name': body['name'], 
          'email': body['email'], 
          'phone': body['phone'], 
          'requireProfileComplete': body['requireProfileComplete'],
          'role': body['role'],
          'token': idToken,
        };
      }
      return {'success': false, 'error': body['error'] ?? 'OAuth Login failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed.'};
    }
  }

  static Future<String> _disabledOAuthLoginMessage(String? email) async {
    if (email != null && email.trim().isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/account-access-status'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim()}),
        ).timeout(const Duration(seconds: 5));
        final body = jsonDecode(response.body);
        final status = (body['status'] ?? '').toString().toLowerCase();
        if (status == 'suspended') {
          return 'Your account is being suspended. Please view the email for more detail.';
        }
        if (status == 'banned') {
          return 'Your account is being banned. Please view the email for more detail.';
        }
      } catch (_) {
        // Fall back to the archived-account message if status lookup fails.
      }
    }
    return 'This account has been archived. Please contact administrator.';
  }

  static Future<Map<String, dynamic>> signInWithGoogle() async {
    GoogleSignInAccount? googleAccount;
    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      
      final GoogleSignInAccount? gUser = await googleSignIn.signIn();
      if (gUser == null) return {'success': false, 'error': 'Google sign in cancelled'};
      googleAccount = gUser;
      final GoogleSignInAuthentication gAuth = await gUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(accessToken: gAuth.accessToken, idToken: gAuth.idToken);
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final token = await userCredential.user?.getIdToken();
      if (token == null) return {'success': false, 'error': 'Failed to retrieve auth token'};
      return await oauthLogin(token, 'Google');
    } on FirebaseAuthException catch (e) {
      if (e.code.toLowerCase().replaceFirst('auth/', '') == 'user-disabled') {
        return {'success': false, 'error': await _disabledOAuthLoginMessage(googleAccount?.email)};
      }
      if (e.code == 'account-exists-with-different-credential') return {'success': false, 'error': 'Email registered across a different provider. Use Email/Password.'};
      return {'success': false, 'error': e.message ?? 'Authentication failed'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> signInWithFacebook() async {
    String? facebookEmail;
    try {
      await FacebookAuth.instance.logOut();
      final LoginResult result = await FacebookAuth.instance.login(permissions: ['email', 'public_profile']);
      if (result.status == LoginStatus.cancelled) return {'success': false, 'error': 'Facebook sign in cancelled'};
      if (result.status != LoginStatus.success) return {'success': false, 'error': result.message ?? 'Facebook sign in failed'};
      try {
        final accessToken = result.accessToken!.tokenString;
        final profileResponse = await http.get(Uri.https('graph.facebook.com', '/me', {
          'fields': 'email',
          'access_token': accessToken,
        })).timeout(const Duration(seconds: 5));
        if (profileResponse.statusCode == 200) {
          final profile = jsonDecode(profileResponse.body);
          facebookEmail = profile['email']?.toString();
        }
      } catch (_) {
        // The provider may not grant an email; use the generic fallback then.
      }
      final OAuthCredential credential = FacebookAuthProvider.credential(result.accessToken!.tokenString);
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      
      final token = await userCredential.user?.getIdToken();
      if (token == null) return {'success': false, 'error': 'Failed to retrieve auth token'};
      return await oauthLogin(token, 'Facebook');
    } on FirebaseAuthException catch (e) {
      if (e.code.toLowerCase().replaceFirst('auth/', '') == 'user-disabled') {
        return {'success': false, 'error': await _disabledOAuthLoginMessage(facebookEmail)};
      }
      if (e.code == 'account-exists-with-different-credential') return {'success': false, 'error': 'Email registered across a different provider. Use Email/Password.'};
      return {'success': false, 'error': e.message ?? 'Authentication failed'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getProfile(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/get-profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 10));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': body['data']};
      }
      return {'success': false, 'error': body['error'] ?? 'Failed to load profile'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed.'};
    }
  }

  static Future<Map<String, dynamic>> updateProfile({
    required String email,
    required String fullName,
    required String phoneNumber,
    required String birthDate,
    required String gender,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update-profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'fullName': fullName,
          'phoneNumber': phoneNumber,
          'birthDate': birthDate,
          'gender': gender,
        }),
      ).timeout(const Duration(seconds: 5));
      
      final body = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return {'success': true, 'message': body['message']};
      } else {
        return {'success': false, 'error': body['error'] ?? 'Update failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection failed.'};
    }
  }

  static Future<Map<String, dynamic>> updateStaffProfile({
    required String fullName,
    required String phoneNumber,
    required String position,
    required List<String> specialization,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return {'success': false, 'error': 'Your staff session has expired. Please sign in again.'};
      final token = await currentUser.getIdToken(true);
      if (token == null) return {'success': false, 'error': 'Your staff session has expired. Please sign in again.'};
      final response = await http.patch(
        Uri.parse('$baseUrl/staff-profile'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'fullName': fullName,
          'phoneNumber': phoneNumber,
          'position': position,
          'specialization': specialization,
        }),
      ).timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': body['profile'], 'message': body['message']};
      return {'success': false, 'error': body['error'] ?? 'Could not update staff profile.'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }

  static Future<Map<String, dynamic>> getStaffProfile() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return {'success': false, 'error': 'Your staff session has expired. Please sign in again.'};
      final token = await currentUser.getIdToken();
      if (token == null) return {'success': false, 'error': 'Your staff session has expired. Please sign in again.'};
      final response = await http.get(
        Uri.parse('$baseUrl/staff-profile'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': body['profile']};
      return {'success': false, 'error': body['error'] ?? 'Could not load staff profile.'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }

  static Future<Map<String, dynamic>> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    passwordChangeInProgress = true;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/change-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      ).timeout(const Duration(seconds: 20));
      
      final body = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        // The server updates the credential through the Admin SDK. Re-sign in
        // with the new password to replace any revoked ID token on this device.
        try {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email.trim(),
            password: newPassword,
          );
        } catch (_) {
          // The password update already succeeded; keep reporting that result.
        }
        return {'success': true, 'message': body['message']};
      } else {
        return {'success': false, 'error': body['error'] ?? 'Update failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection failed.'};
    } finally {
      passwordChangeInProgress = false;
    }
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'clientType': 'Mobile',
        }),
      ).timeout(const Duration(seconds: 5));
      
      final body = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        final role = (body['role'] ?? 'Customer').toString();
        String? sessionToken;
        if (role.toLowerCase() != 'admin') {
          // Keep customer and staff sessions in Firebase so revoked sessions
          // are detected when a password changes on another device.
          final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
          sessionToken = await credential.user?.getIdToken();
        }
        return {'success': true, 'message': body['message'], 'name': body['name'] ?? 'ReByte User', 'role': role, 'token': sessionToken};
      } else {
        final error = body['error'] ?? 'Login failed';
        final status = (body['status'] ?? '').toString().toLowerCase();
        if (status == 'suspended' || status == 'banned') {
          return {
            'success': false,
            'status': body['status'],
            'error': status == 'suspended'
                ? 'Your account is being suspended. Please view the email for more detail.'
                : 'Your account is being banned. Please view the email for more detail.',
          };
        }
        return {
          'success': false,
          'error': error == 'USER_DISABLED'
              ? 'This account has been archived. Please contact administrator.'
              : error,
        };
      }
    } catch (e) {
      if (e is FirebaseAuthException) {
        final normalizedCode = e.code.toLowerCase().replaceFirst('auth/', '');
        final message = normalizedCode == 'user-disabled'
            ? await _disabledAccountLoginMessage(email, password)
            : (e.message ?? 'Unable to sign in.');
        return {'success': false, 'error': message};
      }
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }

  static Future<String> _disabledAccountLoginMessage(String email, String password) async {
    try {
      // Firebase can disable the account between the backend check and the
      // mobile SDK sign-in. Recheck the backend so a customer restriction is
      // reported as Suspended/Banned instead of exposing Firebase's raw error.
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password, 'clientType': 'Mobile'}),
      ).timeout(const Duration(seconds: 5));
      final body = jsonDecode(response.body);
      final status = (body['status'] ?? '').toString().toLowerCase();
      if (status == 'suspended') {
        return 'Your account is being suspended. Please view the email for more detail.';
      }
      if (status == 'banned') {
        return 'Your account is being banned. Please view the email for more detail.';
      }
    } catch (_) {
      // Use the generic disabled-account notice if the status lookup is unavailable.
    }
    return 'This account has been archived. Please contact administrator.';
  }

  static Future<Map<String, dynamic>> checkStaffSession() async {
    if (passwordChangeInProgress) return {'success': true, 'skipped': true};
    try {
      final auth = FirebaseAuth.instance;
      User? firebaseUser = auth.currentUser;
      // Firebase restores its persisted user asynchronously on cold launch.
      // Wait for the first auth-state event before treating null as signed out.
      if (firebaseUser == null) {
        firebaseUser = await auth.authStateChanges().first.timeout(
          const Duration(seconds: 5),
        );
      }
      if (firebaseUser == null) {
        return {'success': false, 'expired': true, 'error': 'Staff session is missing.'};
      }

      // The server verifies revocation status, so a cached ID token is enough and
      // avoids forcing a Firebase token refresh on every session poll.
      final idToken = await firebaseUser.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return {'success': false, 'expired': true, 'error': 'Staff session has ended.'};
      }

      final response = await http.get(
        Uri.parse('$baseUrl/staff-session'),
        headers: {'Authorization': 'Bearer $idToken'},
      ).timeout(const Duration(seconds: 5));
      if (passwordChangeInProgress) return {'success': true, 'skipped': true};
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'profile': body['profile']};
      if (response.statusCode == 401 || response.statusCode == 403) {
        if (body['archived'] == true) {
          return {
            'success': false,
            'expired': true,
            'archived': true,
            'error': 'This staff account has been archived.',
          };
        }
        return {'success': false, 'expired': true, 'error': 'Session expired. Please log in again.'};
      }
      return {'success': false, 'transient': true, 'error': 'Could not verify staff session.'};
    } on FirebaseAuthException catch (e) {
      if (passwordChangeInProgress) return {'success': true, 'skipped': true};
      if (e.code == 'user-disabled') {
        return {
          'success': false,
          'expired': true,
          'archived': true,
          'error': 'This staff account has been archived.',
        };
      }
      if (e.code == 'user-not-found') {
        return {'success': false, 'expired': true, 'error': 'Session expired. Please log in again.'};
      }
      if (['user-token-expired', 'invalid-user-token'].contains(e.code)) {
        return {'success': false, 'expired': true, 'error': 'Session expired. Please log in again.'};
      }
      return {'success': false, 'transient': true, 'error': e.message ?? 'Could not verify staff session.'};
    } catch (_) {
      if (passwordChangeInProgress) return {'success': true, 'skipped': true};
      return {'success': false, 'transient': true, 'error': 'Could not verify staff session.'};
    }
  }

  static Future<Map<String, dynamic>> checkAccountSession() async {
    if (passwordChangeInProgress) return {'success': true, 'skipped': true};
    try {
      final auth = FirebaseAuth.instance;
      final cachedSession = await SessionService.getSession();
      User? user = auth.currentUser;
      if (user == null) {
        try {
          user = await auth.authStateChanges().first.timeout(const Duration(seconds: 5));
        } on TimeoutException {
          // Continue with the locally cached token if Firebase's persisted
          // user state has not restored yet.
        }
      }
      String? idToken;
      if (user != null) {
        try {
          idToken = await user.getIdToken();
          if (idToken != null && idToken.isNotEmpty && idToken != cachedSession['token']) {
            await SessionService.updateToken(idToken);
          }
        } on FirebaseAuthException catch (e) {
          if (e.code != 'user-disabled') rethrow;
          idToken = cachedSession['token'];
        }
      } else {
        idToken = cachedSession['token'];
      }
      if (idToken == null || idToken.isEmpty) {
        return {'success': false, 'expired': true, 'error': 'Session expired. Please log in again.'};
      }
      final response = await http.get(
        Uri.parse('$baseUrl/account-session'),
        headers: {'Authorization': 'Bearer $idToken'},
      ).timeout(const Duration(seconds: 5));
      if (passwordChangeInProgress) return {'success': true, 'skipped': true};
      if (response.statusCode == 200) return {'success': true};
      final body = jsonDecode(response.body);
      if (response.statusCode == 401 || response.statusCode == 403) {
        return {
          'success': false,
          'expired': true,
          'archived': body['archived'] == true,
          'status': body['status'],
          'error': body['error'] ?? 'Session expired. Please log in again.',
        };
      }
      return {'success': false, 'transient': true, 'error': 'Could not verify account session.'};
    } on FirebaseAuthException catch (e) {
      if (passwordChangeInProgress) return {'success': true, 'skipped': true};
      if (e.code == 'user-disabled') {
        return {'success': false, 'expired': true, 'error': 'Session expired. Please log in again.'};
      }
      if (['user-not-found', 'user-token-expired', 'invalid-user-token'].contains(e.code)) {
        return {'success': false, 'expired': true, 'error': 'Session expired. Please log in again.'};
      }
      return {'success': false, 'transient': true, 'error': e.message ?? 'Could not verify account session.'};
    } catch (_) {
      if (passwordChangeInProgress) return {'success': true, 'skipped': true};
      return {'success': false, 'transient': true, 'error': 'Could not verify account session.'};
    }
  }
}
