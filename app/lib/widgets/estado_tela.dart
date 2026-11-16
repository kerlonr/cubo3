import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api.dart';
import '../api/cache.dart';
import '../api/fila.dart';
import '../tema.dart';
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

/// Vários GETs juntos: dados = {chave: resposta}; deCache se algum veio do cache.
Future<RespostaCache> buscarVarios(BuildContext context, Map<String, String> caminhos) async {
  final chaves = caminhos.keys.toList();
  final rs = await Future.wait([for (final k in chaves) buscar(context, caminhos[k]!)]);
  return RespostaCache({for (var i = 0; i < chaves.length; i++) chaves[i]: rs[i].dados}, rs.any((r) => r.deCache),
      rs.map((r) => r.quando).reduce((a, b) => a.isBefore(b) ? a : b));
}

/// Lista vazia que ensina: para que serve e o botão do próximo passo.
class EstadoVazio extends StatelessWidget {
  const EstadoVazio(
      {super.key, required this.titulo, required this.explicacao, this.icone = Icons.inbox_outlined, this.acao, this.aoTocar});

  final String titulo;
  final String explicacao;
  final IconData icone;
  final String? acao;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icone, size: 48, color: t.colorScheme.primary),
        const SizedBox(height: 12),
        Text(titulo, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        if (explicacao.isNotEmpty) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(explicacao, textAlign: TextAlign.center, style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
          ),
        ],
        if (acao != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: aoTocar, icon: const Icon(Icons.add), label: Text(acao!)),
        ],
      ]),
    );
  }
}

/// Carregando / erro com "Tentar de novo" / vazio / conteúdo (+ faixa "Sem conexão — dados de HH:MM").
/// Recarrega sozinha quando [dadosMudaram] avisa; para recarregar de fora, troque a `key`.
class EstadoTela<T> extends StatefulWidget {
  const EstadoTela({super.key, required this.carregar, required this.construir, this.vazio, this.estadoVazio});

  final Future<RespostaCache> Function() carregar;
  final Widget Function(BuildContext context, T dados) construir;
  final bool Function(T dados)? vazio;
  final EstadoVazio? estadoVazio;

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
    dadosMudaram.addListener(_carregar);
  }

  @override
  void dispose() {
    dadosMudaram.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = _r == null;
      _erro = null;
    });
    try {
      final r = await widget.carregar();
      if (r.dados is! T) throw ErroApi(200, 'Resposta inesperada do servidor');
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
        ? ListView(children: [widget.estadoVazio ?? const EstadoVazio(titulo: 'Nada por aqui ainda', explicacao: '')])
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

/// Aviso curto e flutuante. Tira o anterior da tela (sem fila de avisos esperando a vez);
/// erro fica um pouco mais e tem o "x" para fechar.
void avisar(BuildContext context, String mensagem, {bool erro = false}) => ScaffoldMessenger.of(context)
  ..clearSnackBars()
  ..showSnackBar(SnackBar(
    content: Text(mensagem),
    behavior: SnackBarBehavior.floating,
    duration: Duration(milliseconds: erro ? 4000 : 2500),
    showCloseIcon: erro,
  ));

void avisarErro(BuildContext context, Object erro) =>
    avisar(context, erro is ErroApi ? erro.mensagem : 'Algo deu errado: $erro', erro: true);

/// Mensagem padrão depois de gravar pela fila (ou o motivo da recusa).
void avisarEnvio(BuildContext context, ResultadoEnvio r, [String feito = 'Salvo']) => avisar(
    context, r.recusada ?? (r.guardada ? 'Salvo no aparelho, envia quando tiver internet' : feito),
    erro: r.recusada != null);

/// Grava pela fila offline e avisa. true = aceito (enviado ou guardado no aparelho).
/// Em edição, [versaoBase] = `atualizado_em` do registro carregado (o servidor recusa se outro mudou depois).
Future<bool> salvar(BuildContext context, String metodo, String caminho, Map corpo,
    {String feito = 'Salvo', String? versaoBase}) async {
  try {
    final r = await context.read<FilaOffline>().enviarOuGuardar(Operacao.nova(metodo, caminho, corpo, versaoBase));
    if (context.mounted) avisarEnvio(context, r, feito);
    return r.recusada == null;
  } catch (e) {
    if (context.mounted) avisarErro(context, e);
    return false;
  }
}

Future<bool> confirmar(BuildContext context, String titulo, String texto,
        {String sim = 'Confirmar', String nao = 'Cancelar', Color? cor}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(nao)),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              style: cor == null ? null : FilledButton.styleFrom(backgroundColor: cor, foregroundColor: Colors.white),
              child: Text(sim)),
        ],
      ),
    ) ==
    true;

/// Excluir um cadastro (filamento, insumo) do formulário de edição: confirma, manda o DELETE e fecha.
Future<void> excluirCadastro(BuildContext context, String titulo, String caminho) async {
  if (!await confirmar(context, titulo, 'O que já foi lançado continua mostrando o nome.', sim: 'Excluir', cor: vermelho) ||
      !context.mounted) {
    return;
  }
  if (await salvar(context, 'DELETE', caminho, {}, feito: 'Excluído') && context.mounted) Navigator.pop(context, true);
}
