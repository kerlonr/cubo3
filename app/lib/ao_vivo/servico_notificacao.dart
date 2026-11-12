import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';
import '../api/controle.dart';
import '../api/modelos.dart';
import '../tema.dart';
import 'canal_ao_vivo.dart';

final notificacoes = FlutterLocalNotificationsPlugin();

/// Ícone minimalista (cubo em traço branco) de res/drawable; o do app colorido vira um borrão na barra.
const iconeNotificacao = 'ic_stat_cubo3';

NotificationDetails _detalhesAlerta(String corpo) => NotificationDetails(
      android: AndroidNotificationDetails(
        'fim_impressao',
        'Fim de impressão',
        channelDescription: 'Avisa quando uma impressão termina ou para',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        icon: iconeNotificacao,
        color: indigo,
        category: AndroidNotificationCategory.status,
        styleInformation: BigTextStyleInformation(corpo),
      ),
    );

const _iniciar = InitializationSettings(
  android: AndroidInitializationSettings(iconeNotificacao),
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
      id: id.hashCode & 0x7fffffff,
      title: a.titulo,
      body: a.corpo,
      notificationDetails: _detalhesAlerta(a.corpo),
      payload: id);
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
  /// A notificação de progresso usa o mesmo id do serviço: ela substitui a notificação simples dele.
  static const idServico = 3003;

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
      serviceId: idServico,
      notificationIcon: const NotificationIcon(metaDataName: 'cubo3.NOTIFICACAO_ICONE', backgroundColor: indigo),
      serviceTypes: [ForegroundServiceTypes.specialUse],
      notificationTitle: 'Cubo³',
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
/// Publica a notificação de progresso no lugar da notificação simples do serviço (mesmo id).
class TarefaMonitor extends TaskHandler {
  CanalAoVivo? _canal;
  ApiCliente? _api;
  StreamSubscription<Map>? _eventos;
  Map<String, String> _nomes = {};
  final _miniaturas = <String, Uint8List?>{};
  String _ultimaChave = '';
  DateTime _ultimaVez = DateTime(2000);

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final base = await FlutterForegroundTask.getData<String>(key: 'base');
    final empresa = await FlutterForegroundTask.getData<String>(key: 'empresa');
    if (base == null || empresa == null) return;
    final api = _api = ApiCliente(http.Client(), Uri.parse(base), ArmazemSeguro())..empresaId = empresa;
    try {
      await notificacoes.initialize(settings: _iniciar);
    } catch (_) {}
    try {
      await api.renovar();
      _nomes = {for (final i in lista(await api.get('/api/impressoras'))) '${i['id']}': '${i['nome']}'};
    } catch (_) {
      // Sem rede agora: o canal tenta de novo com espera crescente; a notificação sai sem o nome da impressora.
    }
    _canal = CanalAoVivo(api)
      ..addListener(_atualizar)
      ..iniciar();
    _eventos = _canal!.eventos.listen((e) {
      if (e['tipo'] == 'impressao_terminou') mostrarAlertaFim(e);
    });
  }

  void _atualizar() {
    final entradas = _canal?.estados.entries.toList() ?? const <MapEntry<String, EstadoImpressora>>[];
    final escolhida = entradas.where((x) => x.value.imprimindo).firstOrNull ?? entradas.firstOrNull;
    final agora = DateTime.now();
    final c = conteudoNotificacao(escolhida?.value, agora);
    // Muda de % ou de estado: publica na hora. Só temperatura mexendo: no máximo a cada 30 s (bateria).
    final chave = '${c.titulo}|${c.corpo}';
    if (chave == _ultimaChave && agora.difference(_ultimaVez) < const Duration(seconds: 30)) return;
    _ultimaChave = chave;
    _ultimaVez = agora;
    _publicar(c, escolhida?.key, escolhida?.value.arquivo);
  }

  Future<void> _publicar(ConteudoNotificacao c, String? impressoraId, String? arquivo) async {
    final mini = c.ativa && impressoraId != null ? await _miniatura(impressoraId, arquivo) : null;
    final nome = impressoraId == null ? null : _nomes[impressoraId];
    try {
      await notificacoes.show(
        id: ServicoNotificacao.idServico,
        title: c.titulo,
        body: c.corpo,
        payload: 'impressora',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'monitor_impressoras',
            'Monitor das impressoras',
            channelDescription: 'Progresso da impressão em andamento',
            importance: Importance.low,
            priority: Priority.low,
            icon: iconeNotificacao,
            color: indigo,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            silent: true,
            category: AndroidNotificationCategory.progress,
            subText: nome,
            showProgress: c.ativa,
            maxProgress: 1000,
            progress: ((c.progresso ?? 0) * 1000).round(),
            indeterminate: c.ativa && c.progresso == null,
            // Contagem regressiva nativa até o fim: anda sozinha a cada segundo, sem gastar bateria.
            usesChronometer: c.terminaEm != null,
            chronometerCountDown: c.terminaEm != null,
            showWhen: c.terminaEm != null,
            when: c.terminaEm?.millisecondsSinceEpoch,
            largeIcon: mini == null ? null : ByteArrayAndroidBitmap(mini),
            styleInformation:
                c.linhas.isEmpty ? null : BigTextStyleInformation(c.linhas.join('\n'), contentTitle: c.titulo, summaryText: nome),
          ),
        ),
      );
    } catch (_) {
      // Notificação recusada pelo sistema: o serviço continua monitorando e o alerta de fim segue valendo.
    }
  }

  /// Miniatura do G-code que está imprimindo (a foto da peça na notificação). Busca uma vez por arquivo.
  Future<Uint8List?> _miniatura(String impressoraId, String? arquivo) async {
    final api = _api;
    if (arquivo == null || api == null) return null;
    final chave = '$impressoraId|$arquivo';
    if (_miniaturas.containsKey(chave)) return _miniaturas[chave];
    _miniaturas[chave] = null; // não tenta de novo a cada atualização se falhar
    try {
      final achado = lista(await api.get('/api/impressoras/$impressoraId/arquivos')).where((a) => a['nome'] == arquivo);
      final caminho = achado.isEmpty ? null : achado.first['miniatura'];
      if (caminho == null) return null;
      final r = await http.get(api.url(miniaturaDaImpressora(impressoraId, '$caminho')), headers: api.cabecalhosAuth);
      if (r.statusCode == 200) _miniaturas[chave] = r.bodyBytes;
    } catch (_) {}
    return _miniaturas[chave];
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
