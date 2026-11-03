import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'tema.dart';
import 'widgets/logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  runApp(const AppCubo3());
}

class AppCubo3 extends StatelessWidget {
  const AppCubo3({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cubo³',
      debugShowCheckedModeBanner: false,
      theme: temaCubo3(Brightness.light),
      darkTheme: temaCubo3(Brightness.dark),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const Scaffold(body: Center(child: LogoCubo3(tamanho: 64, comNome: true))),
    );
  }
}
