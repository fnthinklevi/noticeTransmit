import 'package:flutter/material.dart';
import 'pages/main_page.dart';
import 'di/service_locator.dart';

void main() {
  setupLocator();
  runApp(const MyApp());
}
