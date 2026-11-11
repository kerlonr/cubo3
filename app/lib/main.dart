import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ao_vivo/canal_ao_vivo.dart';
import 'ao_vivo/servico_notificacao.dart';
import 'api/api.dart';
import 'api/cache.dart';
import 'api/fila.dart';
import 'api/sessao.dart';
import 'config.dart';
import 'tema.dart';
import 'telas/casca.dart';
import 'telas/impressoes/confirmar_tela.dart';
import 'telas/login/escolher_empresa_tela.dart';
import 'telas/login/login_tela.dart';
import 'telas/login/trocar_senha_tela.dart';
import 'widgets/logo.dart';

/// Navegador do app inteiro (a notificação abre a tela de confirmar de fora da árvore).
final navegador = GlobalKey<NavigatorState>();

const chaveServidor = 'servidor_v1';

/// Impressão a confirmar pedida por um toque em notificação (abre quando a sessão estiver pronta).
String? confirmacaoPendente;

void abrirConfirmacao(String impressaoId) {
  final nav = navegador.currentState;
  if (nav == null || nav.context.read<Sessao>().estado != EstadoSessao.pronta) {
    confirmacaoPendente = impressaoId;
    return;
  }
  confirmacaoPendente = null;
  nav.push(MaterialPageRoute(builder: (_) => ConfirmarTela(impressaoId: impressaoId)));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  final prefs = await SharedPreferences.getInstance();
  final api = ApiCliente(http.Client(), baseInicial(prefs.getString(chaveServidor)), ArmazemSeguro());
  final sessao = Sessao(api, prefs);
  final fila = FilaOffline(api, prefs)..iniciarTentativas();
  await prepararNotificacoes(abrirConfirmacao);
  runApp(AppCubo3(api: api, sessao: sessao, fila: fila, cache: CacheLeitura(prefs), canal: CanalAoVivo(api)));
  await sessao.restaurar();
}

List<SingleChildWidget> provedores(
        ApiCliente api, Sessao sessao, FilaOffline fila, CacheLeitura cache, CanalAoVivo canal) =>
    [
      Provider.value(value: api),
      Provider.value(value: cache),
      ChangeNotifierProvider.value(value: sessao),
      ChangeNotifierProvider.value(value: fila),
      ChangeNotifierProvider.value(value: canal),
    ];

class AppCubo3 extends StatefulWidget {
  const AppCubo3(
      {super.key, required this.api, required this.sessao, required this.fila, required this.cache, required this.canal});

  final ApiCliente api;
  final Sessao sessao;
  final FilaOffline fila;
  final CacheLeitura cache;
  final CanalAoVivo canal;

  @override
  State<AppCubo3> createState() => _AppCubo3State();
}

class _AppCubo3State extends State<AppCubo3> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sessao.addListener(_aoMudarSessao);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.sessao.removeListener(_aoMudarSessao);
    widget.canal.parar();
    super.dispose();
  }

  void _aoMudarSessao() {
    switch (widget.sessao.estado) {
      case EstadoSessao.pronta:
        widget.fila.esvaziar();
        widget.canal.iniciar();
        ServicoNotificacao.religarSePreciso(widget.api).catchError((_) {});
        final pendente = confirmacaoPendente;
        if (pendente != null) WidgetsBinding.instance.addPostFrameCallback((_) => abrirConfirmacao(pendente));
      case EstadoSessao.deslogado:
        widget.canal.parar();
        ServicoNotificacao.desligar(lembrar: false).catchError((_) {});
      default:
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed && widget.sessao.estado == EstadoSessao.pronta) widget.fila.esvaziar();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: provedores(widget.api, widget.sessao, widget.fila, widget.cache, widget.canal),
      child: MaterialApp(
        title: 'Cubo³',
        navigatorKey: navegador,
        debugShowCheckedModeBanner: false,
        theme: temaCubo3(Brightness.light),
        darkTheme: temaCubo3(Brightness.dark),
        themeMode: ThemeMode.dark, // pedido do Kerlon: sempre escuro
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Consumer<Sessao>(
          builder: (context, s, _) => switch (s.estado) {
            EstadoSessao.carregando => const Scaffold(body: Center(child: LogoCubo3(tamanho: 72))),
            EstadoSessao.deslogado => const LoginTela(),
            EstadoSessao.trocarSenha => const TrocarSenhaTela(),
            EstadoSessao.escolherEmpresa => const EscolherEmpresaTela(),
            EstadoSessao.pronta => Casca(key: ValueKey(widget.api.empresaId)),
          },
        ),
      ),
    );
  }
}
