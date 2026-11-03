import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/fila.dart';
import '../../api/modelos.dart';
import '../../util/formatos.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';
import 'filamento_form.dart';

/// Cada pesagem é um ajuste novo: movimento_id novo a cada vez (reenviar a mesma não duplica).
Future<ResultadoEnvio> enviarPesagem(FilaOffline fila, String carretelId, double pesoBalancaG) =>
    fila.enviarOuGuardar(Operacao.nova(
        'POST', '/api/carreteis/$carretelId/pesagem', {'movimento_id': novoId(), 'peso_balanca_g': pesoBalancaG}));

/// Pede um ou dois números num diálogo; null se cancelar.
Future<List<double?>?> pedirNumeros(BuildContext context, String titulo, List<(String, String?, bool)> campos,
    {String? texto}) {
  final ctrls = [for (final _ in campos) TextEditingController()];
  final form = GlobalKey<FormState>();
  return showDialog<List<double?>>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (texto != null) Text(texto),
          for (var i = 0; i < campos.length; i++)
            campos[i].$3
                ? CampoDinheiro(ctrls[i], campos[i].$1)
                : CampoNumero(ctrls[i], campos[i].$1, sufixo: campos[i].$2, obrigatorio: i == 0),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(c, [for (final t in ctrls) lerNumero(t.text)]);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// "Pesei o carretel: ___ g". Sem peso do carretel vazio no filamento, explica e oferece cadastrar.
Future<bool> pesarCarretel(BuildContext context, Json carretel) async {
  final fila = context.read<FilaOffline>();
  Json filamento;
  try {
    filamento = mapa((await buscar(context, '/api/filamentos/${carretel['filamento_id']}')).dados);
  } catch (e) {
    if (context.mounted) avisarErro(context, e);
    return false;
  }
  if (!context.mounted) return false;
  if (filamento['peso_carretel_vazio_g'] == null) {
    final cadastrar = await confirmar(
      context,
      'Falta o peso do carretel vazio',
      'Para saber quanto filamento sobrou, o app desconta o peso do carretel vazio. '
          'Cadastre esse peso no filamento (pese um carretel vazio da mesma marca).',
      sim: 'Cadastrar',
    );
    if (cadastrar && context.mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => FilamentoForm(dados: filamento)));
    }
    return false;
  }
  final r = await pedirNumeros(context, 'Pesar carretel', [('Pesei o carretel', 'g', false)],
      texto: 'Coloque o carretel na balança, com o filamento.');
  final peso = r?.first;
  if (peso == null || !context.mounted) return false;
  try {
    final r = await enviarPesagem(fila, carretel['id'] as String, peso);
    if (context.mounted) avisarEnvio(context, r, 'Saldo ajustado');
    return true;
  } catch (e) {
    if (context.mounted) avisarErro(context, e);
    return false;
  }
}

/// Ajuste manual (+ ou −) de carretel, insumo ou peça.
Future<bool> ajustar(BuildContext context, String itemTipo, String itemId, {String sufixo = ''}) async {
  final r = await pedirNumeros(context, 'Ajustar estoque', [('Quantidade (+ entra, − sai)', sufixo, false)]);
  final q = r?.first;
  if (q == null || q == 0 || !context.mounted) return false;
  return salvar(context, 'PUT', '/api/movimentos/${novoId()}',
      {'item_tipo': itemTipo, 'item_id': itemId, 'tipo': 'ajuste', 'quantidade': q, 'data': agoraUtc()});
}

/// Compra de insumo: entra no estoque e no gasto do mês.
Future<bool> comprarInsumo(BuildContext context, Json insumo) async {
  final r = await pedirNumeros(context, 'Compra de ${insumo['nome']}', [('Quantidade', null, false), ('Valor pago', null, true)]);
  if (r == null || r[0] == null || r[0]! <= 0 || !context.mounted) return false;
  return salvar(context, 'PUT', '/api/movimentos/${novoId()}', {
    'item_tipo': 'insumo',
    'item_id': insumo['id'],
    'tipo': 'compra',
    'quantidade': r[0],
    'valor': r[1],
    'data': agoraUtc(),
  });
}

String agoraUtc() => DateTime.now().toUtc().toIso8601String();
