import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

class AuthService {
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
        return {'success': true, 'message': body['message']};
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
          'role': body['role']
        };
      }
      return {'success': false, 'error': body['error'] ?? 'OAuth Login failed'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed.'};
    }
  }

  static Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      
      final GoogleSignInAccount? gUser = await googleSignIn.signIn();
      if (gUser == null) return {'success': false, 'error': 'Google sign in cancelled'};
      final GoogleSignInAuthentication gAuth = await gUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(accessToken: gAuth.accessToken, idToken: gAuth.idToken);
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final token = await userCredential.user?.getIdToken();
      if (token == null) return {'success': false, 'error': 'Failed to retrieve auth token'};
      return await oauthLogin(token, 'Google');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') return {'success': false, 'error': 'Email registered across a different provider. Use Email/Password.'};
      return {'success': false, 'error': e.message ?? 'Authentication failed'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> signInWithFacebook() async {
    try {
      await FacebookAuth.instance.logOut();
      final LoginResult result = await FacebookAuth.instance.login(permissions: ['email', 'public_profile']);
      if (result.status == LoginStatus.cancelled) return {'success': false, 'error': 'Facebook sign in cancelled'};
      if (result.status != LoginStatus.success) return {'success': false, 'error': result.message ?? 'Facebook sign in failed'};
      final OAuthCredential credential = FacebookAuthProvider.credential(result.accessToken!.tokenString);
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      
      final token = await userCredential.user?.getIdToken();
      if (token == null) return {'success': false, 'error': 'Failed to retrieve auth token'};
      return await oauthLogin(token, 'Facebook');
    } on FirebaseAuthException catch (e) {
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

  static Future<Map<String, dynamic>> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/change-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'currentPassword': currentPassword,
          'newPassword': newPassword,
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
        return {'success': true, 'message': body['message'], 'name': body['name'] ?? 'ReByte User', 'role': body['role']};
      } else {
        return {'success': false, 'error': body['error'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Connection failed. Ensure backend is running.'};
    }
  }
}
