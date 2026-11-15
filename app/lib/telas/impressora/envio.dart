import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/controle.dart';
import '../../widgets/estado_tela.dart';

/// Envio de comando à impressora: direto (nunca pela fila) e um por vez — enquanto o pedido está no ar
/// os botões ficam desabilitados, então o toque duplo não manda duas vezes.
mixin EnvioComando<T extends StatefulWidget> on State<T> {
  bool emVoo = false;

  String get impressoraId;

  /// [acao] null enquanto há comando no ar (desabilita o botão).
  VoidCallback? se(VoidCallback acao) => emVoo ? null : acao;

  Future<bool> enviar(Future<void> Function(ApiCliente api) acao, String feito) async {
    if (emVoo) return false;
    setState(() => emVoo = true);
    try {
      await acao(context.read<ApiCliente>());
      if (mounted) avisar(context, feito);
      return true;
    } on ErroApi catch (e) {
      if (mounted) avisarRecusa(context, e, impressoraId);
      return false;
    } finally {
      if (mounted) setState(() => emVoo = false);
    }
  }

  Future<bool> comando(String acao, String feito, {num? valor, Map<String, Object>? extra}) =>
      enviar((api) => comandar(api, impressoraId, acao, valor: valor, extra: extra), feito);
}

/// Mostra a recusa do Klipper; se ele pede Home ("Must home axis first"), oferece fazer na hora.
void avisarRecusa(BuildContext context, ErroApi e, String impressoraId) {
  final api = context.read<ApiCliente>();
  final mensageiro = ScaffoldMessenger.of(context);
  mensageiro
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(e.mensagem),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      persist: false, // com ação, o padrão do Flutter é ficar na tela até alguém tocar
      showCloseIcon: true,
      action: pedeHome(e.mensagem)
          ? SnackBarAction(
              label: 'Fazer Home',
              onPressed: () => comandar(api, impressoraId, 'home', extra: {'eixos': 'XYZ'}).then(
                  (_) => mensageiro.showSnackBar(
                      const SnackBar(content: Text('Home enviado'), behavior: SnackBarBehavior.floating)),
                  onError: (Object erro) => mensageiro.showSnackBar(
                      SnackBar(content: Text('$erro'), behavior: SnackBarBehavior.floating, showCloseIcon: true))),
            )
          : null,
    ));
}
