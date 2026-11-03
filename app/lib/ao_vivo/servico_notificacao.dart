import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';
import 'canal_ao_vivo.dart';

final notificacoes = FlutterLocalNotificationsPlugin();

const _detalhesAlerta = NotificationDetails(
  android: AndroidNotificationDetails(
    'fim_impressao',
    'Fim de impressão',
    channelDescription: 'Avisa quando uma impressão termina ou para',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
  ),
);

const _iniciar = InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  web: WebInitializationSettings(),
);

/// Notificações locais no app (Android e navegador). Tocar num alerta chama [abrir] com o id da impressão,
/// inclusive quando o toque abriu o app.
Future<void> prepararNotificacoes(void Function(String impressaoId) abrir) async {
  try {
    await notificacoes.initialize(
      settings: _iniciar,
      onDidReceiveNotificationResponse: (r) {
        if ((r.payload ?? '').isNotEmpty) abrir(r.payload!);
      },
    );
    final lancamento = await notificacoes.getNotificationAppLaunchDetails();
    final payload = lancamento?.notificationResponse?.payload;
    if (lancamento?.didNotificationLaunchApp == true && (payload ?? '').isNotEmpty) abrir(payload!);
  } catch (e) {
    debugPrint('notificações: $e'); // navegador sem suporte: o aviso na tela continua
  }
  if (!kIsWeb) ServicoNotificacao.configurar();
}

/// Alerta de fim/falha com som; o payload é o id da impressão a confirmar.
Future<void> mostrarAlertaFim(Map evento) async {
  final a = alertaFim(evento);
  final id = '${evento['impressao_id'] ?? ''}';
  await notificacoes.show(
      id: id.hashCode & 0x7fffffff, title: a.titulo, body: a.corpo, notificationDetails: _detalhesAlerta, payload: id);
}

/// Navegador: pede permissão (precisa vir de um toque do usuário).
Future<bool> pedirPermissaoNavegador() async =>
    await notificacoes
        .resolvePlatformSpecificImplementation<WebFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission() ??
    false;

/// Serviço em primeiro plano (só Android) que mantém o WebSocket aberto com o app fechado.
class ServicoNotificacao {
  static const chaveLigado = 'monitorar_v1';
  static const _idServico = 3003;

  static void configurar() => FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'monitor_impressoras',
          channelName: 'Monitor das impressoras',
          channelDescription: 'Progresso da impressão em andamento',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );

  static Future<bool> get ligado async => !kIsWeb && await FlutterForegroundTask.isRunningService;

  /// Liga o monitor. Devolve a mensagem de erro ou null.
  static Future<String?> ligar(ApiCliente api) async {
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    await FlutterForegroundTask.saveData(key: 'base', value: api.base.toString());
    await FlutterForegroundTask.saveData(key: 'empresa', value: api.empresaId ?? '');
    await (await SharedPreferences.getInstance()).setBool(chaveLigado, true);
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    final r = await FlutterForegroundTask.startService(
      serviceId: _idServico,
      serviceTypes: [ForegroundServiceTypes.specialUse],
      notificationTitle: 'Cubo³ monitorando',
      notificationText: 'Nenhuma impressão agora',
      callback: iniciarServicoMonitor,
    );
    return r is ServiceRequestFailure ? 'Não foi possível ligar o monitor: ${r.error}' : null;
  }

  static Future<void> desligar({bool lembrar = true}) async {
    if (kIsWeb) return;
    if (lembrar) await (await SharedPreferences.getInstance()).setBool(chaveLigado, false);
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
  }

  /// Ao abrir o app: se o usuário deixou ligado e o sistema matou o serviço, liga de novo.
  static Future<void> religarSePreciso(ApiCliente api) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(chaveLigado) == true && !await FlutterForegroundTask.isRunningService) await ligar(api);
  }
}

@pragma('vm:entry-point')
void iniciarServicoMonitor() => FlutterForegroundTask.setTaskHandler(TarefaMonitor());

/// Roda no isolate do serviço: mesma conexão ao vivo do app, renovando o acesso sozinha.
class TarefaMonitor extends TaskHandler {
  CanalAoVivo? _canal;
  StreamSubscription<Map>? _eventos;
  String _ultimo = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final base = await FlutterForegroundTask.getData<String>(key: 'base');
    final empresa = await FlutterForegroundTask.getData<String>(key: 'empresa');
    if (base == null || empresa == null) return;
    final api = ApiCliente(http.Client(), Uri.parse(base), ArmazemSeguro())..empresaId = empresa;
    try {
      await notificacoes.initialize(settings: _iniciar);
    } catch (_) {}
    try {
      await api.renovar();
    } catch (_) {
      // Sem rede agora: o canal tenta de novo com espera crescente.
    }
    _canal = CanalAoVivo(api)
      ..addListener(_atualizar)
      ..iniciar();
    _eventos = _canal!.eventos.listen((e) {
      if (e['tipo'] == 'impressao_terminou') mostrarAlertaFim(e);
    });
  }

  void _atualizar() {
    final estados = _canal?.estados.values.toList() ?? const <EstadoImpressora>[];
    final e = estados.where((x) => x.imprimindo).firstOrNull ?? estados.firstOrNull;
    final titulo = textoProgresso(e);
    final temperaturas = textoTemperaturas(e);
    final texto = e != null && e.imprimindo
        ? [barraTexto(e.progresso ?? 0), temperaturas].where((s) => s.isNotEmpty).join('  ')
        : (temperaturas.isEmpty ? 'Nenhuma impressão agora' : temperaturas);
    if ('$titulo|$texto' == _ultimo) return;
    _ultimo = '$titulo|$texto';
    FlutterForegroundTask.updateService(notificationTitle: titulo, notificationText: texto);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _eventos?.cancel();
    _canal?.parar();
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}
