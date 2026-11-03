import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api.dart';
import '../api/cache.dart';
import '../api/fila.dart';
import '../util/formatos.dart';

/// Lê um GET pela fila e pelo cache: envia as pendências antes (para a lista já vir com elas)
/// e, sem conexão, devolve a última resposta guardada.
Future<RespostaCache> buscar(BuildContext context, String caminho, {Map<String, String>? query}) async {
  final api = context.read<ApiCliente>();
  final cache = context.read<CacheLeitura>();
  final fila = context.read<FilaOffline>();
  if (fila.pendentes > 0) await fila.esvaziar();
  final chave = '${api.empresaId}|${api.url(caminho, query)}';
  return cache.obter(chave, () => api.get(caminho, query: query));
}

/// Carregando / erro com "Tentar de novo" / vazio / conteúdo (+ faixa "Sem conexão — dados de HH:MM").
/// Para recarregar de fora, troque a `key`.
class EstadoTela<T> extends StatefulWidget {
  const EstadoTela({super.key, required this.carregar, required this.construir, this.vazio, this.mensagemVazio});

  final Future<RespostaCache> Function() carregar;
  final Widget Function(BuildContext context, T dados) construir;
  final bool Function(T dados)? vazio;
  final String? mensagemVazio;

  @override
  State<EstadoTela<T>> createState() => _EstadoTelaState<T>();
}

class _EstadoTelaState<T> extends State<EstadoTela<T>> {
  RespostaCache? _r;
  Object? _erro;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = _r == null;
      _erro = null;
    });
    try {
      final r = await widget.carregar();
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (mounted) setState(() => _erro = e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null && _r == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_erro is ErroApi ? (_erro as ErroApi).mensagem : 'Algo deu errado', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _carregar, child: const Text('Tentar de novo')),
          ]),
        ),
      );
    }
    final dados = _r!.dados as T;
    final Widget conteudo = widget.vazio?.call(dados) == true
        ? ListView(children: [
            Padding(
              padding: const EdgeInsets.all(48),
              child: Text(widget.mensagemVazio ?? 'Nada por aqui ainda',
                  textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            )
          ])
        : widget.construir(context, dados);
    return RefreshIndicator(
      onRefresh: _carregar,
      child: Column(children: [
        if (_r!.deCache) FaixaSemConexao(quando: _r!.quando),
        Expanded(child: conteudo),
      ]),
    );
  }
}

class FaixaSemConexao extends StatelessWidget {
  const FaixaSemConexao({super.key, required this.quando});
  final DateTime quando;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text('Sem conexão — dados de ${hora(quando)}', style: const TextStyle(fontSize: 12)),
      );
}

void avisar(BuildContext context, String mensagem) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));

void avisarErro(BuildContext context, Object erro) =>
    avisar(context, erro is ErroApi ? erro.mensagem : 'Algo deu errado: $erro');

/// Mensagem padrão depois de gravar pela fila.
void avisarEnvio(BuildContext context, ResultadoEnvio r, [String feito = 'Salvo']) =>
    avisar(context, r.guardada ? 'Salvo no aparelho, envia quando tiver internet' : feito);

Future<bool> confirmar(BuildContext context, String titulo, String texto, {String sim = 'Confirmar'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(sim)),
        ],
      ),
    ) ==
    true;
