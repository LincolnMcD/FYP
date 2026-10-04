import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'account_management_module/home_page.dart';
import 'account_management_module/services/session_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  final session = await SessionService.getSession();
  final bool isLoggedIn = session.isNotEmpty;
  final String? email = session['email'];
  final String? name = session['name'];

  runApp(MyApp(isLoggedIn: isLoggedIn, email: email, name: name));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  final String? email;
  final String? name;

  const MyApp({super.key, required this.isLoggedIn, this.email, this.name});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReByte',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0C5AD2)),
        useMaterial3: true,
      ),
      home: HomePage(isLoggedIn: isLoggedIn, email: email, name: name),
      debugShowCheckedModeBanner: false,
    );
  }
}

