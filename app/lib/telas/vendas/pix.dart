import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api.dart';
import '../../api/modelos.dart';
import '../../api/sessao.dart';
import '../../tema.dart';
import '../../util/formatos.dart';
import '../../widgets/campos.dart';
import '../../widgets/cartoes.dart';
import '../../widgets/estado_tela.dart';
import '../mais/empresa_tela.dart';
import 'clientes_tela.dart' show linkWhatsapp;

// O Pix (a chave inteira) e o copia e cola passam só pelo ApiCliente direto: nada de buscar()/fila,
// que guardam as respostas no aparelho sem proteção.

const tiposPix = {'cpf': 'CPF', 'cnpj': 'CNPJ', 'email': 'E-mail', 'telefone': 'Telefone', 'aleatoria': 'Aleatória'};

/// Pix da empresa em Empresa: o dono cadastra, vê a chave (olho) e apaga; o membro só vê que existe.
class SecaoPix extends StatefulWidget {
  const SecaoPix({super.key});

  @override
  State<SecaoPix> createState() => _SecaoPixState();
}

class _SecaoPixState extends State<SecaoPix> {
  Json? _pix;
  Object? _erro;
  bool _ver = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _erro = null);
    try {
      final r = mapa(await context.read<ApiCliente>().get('/api/empresa/pix'));
      if (mounted) setState(() => _pix = r);
    } catch (e) {
      if (mounted) setState(() => _erro = e);
    }
  }

  Future<void> _editar() async {
    final r = await showModalBottomSheet<Json>(
        context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => FormPix(atual: _pix));
    if (r != null && mounted) {
      setState(() => _pix = r);
      avisar(context, 'Pix salvo');
    }
  }

  Future<void> _apagar() async {
    if (!await confirmar(context, 'Apagar o Pix?', 'As cobranças param até cadastrar de novo.', sim: 'Apagar', cor: vermelho) ||
        !mounted) {
      return;
    }
    try {
      await context.read<ApiCliente>().delete('/api/empresa/pix');
      if (mounted) setState(() => _pix = {'configurado': false});
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dono = context.watch<Sessao>().dono;
    final p = _pix;
    final configurado = p?['configurado'] == true;
    final Widget corpo;
    if (_erro != null) {
      corpo = ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cloud_off_outlined),
        title: Text(_erro is ErroApi ? (_erro as ErroApi).mensagem : 'Algo deu errado'),
        subtitle: const Text('O Pix só abre com internet'),
        trailing: IconButton(tooltip: 'Tentar de novo', icon: const Icon(Icons.refresh), onPressed: _carregar),
      );
    } else if (p == null) {
      corpo = const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
    } else if (!configurado) {
      corpo = ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.pix),
        title: const Text('Pix não cadastrado'),
        trailing: dono ? FilledButton.tonal(onPressed: _editar, child: const Text('Cadastrar')) : null,
      );
    } else if (!dono) {
      corpo = ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.pix),
        title: Text('Pix configurado: ${p['chave_mascarada']} (${p['nome']})'),
      );
    } else {
      corpo = ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.pix),
        title: Text(_ver ? '${p['chave'] ?? p['chave_mascarada']}' : '${p['chave_mascarada']}', key: const Key('chave-pix')),
        subtitle: Text('${tiposPix[p['tipo']] ?? p['tipo']} · ${p['nome']} · ${p['cidade']}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: _ver ? 'Esconder chave' : 'Mostrar chave',
            icon: Icon(_ver ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _ver = !_ver),
          ),
          IconButton(tooltip: 'Editar Pix', icon: const Icon(Icons.edit_outlined), onPressed: _editar),
          IconButton(tooltip: 'Apagar Pix', icon: const Icon(Icons.delete_outline), onPressed: _apagar),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Secao('Pix'), corpo]);
  }
}

/// Cadastro do Pix (só o dono). Devolve o que o servidor gravou.
class FormPix extends StatefulWidget {
  const FormPix({super.key, this.atual});
  final Json? atual;

  @override
  State<FormPix> createState() => _FormPixState();
}

class _FormPixState extends State<FormPix> {
  late String _tipo = widget.atual?['tipo'] as String? ?? 'cpf';
  late final _chave = TextEditingController(text: widget.atual?['chave'] as String?);
  late final _nome = TextEditingController(text: widget.atual?['nome'] as String?);
  late final _cidade = TextEditingController(text: widget.atual?['cidade'] as String?);
  String? _erro;
  bool _salvando = false;

  @override
  void dispose() {
    for (final c in [_chave, _nome, _cidade]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final r = await context.read<ApiCliente>().put('/api/empresa/pix',
          {'tipo': _tipo, 'chave': _chave.text.trim(), 'nome': _nome.text.trim(), 'cidade': _cidade.text.trim()});
      if (mounted) Navigator.pop(context, mapa(r));
    } catch (e) {
      // A folha cobre o aviso de baixo: o motivo (chave inválida, sem internet) aparece aqui mesmo.
      if (mounted) setState(() => _erro = e is ErroApi ? e.mensagem : '$e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const Text('Seu Pix', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SeletorChips<String>(opcoes: tiposPix, valor: _tipo, aoMudar: (v) => setState(() => _tipo = v)),
            CampoTexto(_chave, 'Chave',
                teclado: switch (_tipo) {
                  'cpf' || 'cnpj' || 'telefone' => TextInputType.number,
                  'email' => TextInputType.emailAddress,
                  _ => TextInputType.text,
                }),
            CampoTexto(_nome, 'Nome do recebedor', dica: 'Como aparece no banco'),
            CampoTexto(_cidade, 'Cidade'),
            if (_erro != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(_erro!, style: const TextStyle(color: vermelho))),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _salvando ? null : _salvar,
              child: const Text('Salvar'),
            ),
          ]),
        ),
      );
}

/// Pede o copia e cola ao servidor (online). Sem Pix cadastrado, leva o dono ao cadastro.
/// O erro sai em janela, não em aviso de baixo: quem chama pode estar numa folha, que cobriria o aviso.
Future<Json?> gerarCobranca(BuildContext context, Map corpo) async {
  try {
    return mapa(await context.read<ApiCliente>().post('/api/pix/cobranca', corpo));
  } on ErroApi catch (e) {
    if (!context.mounted) return null;
    final semPix = e.status == 409 && e.mensagem.startsWith('Cadastre');
    final dono = context.read<Sessao>().dono;
    final cadastrar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.pix),
        title: Text(semPix ? (dono ? 'Cadastre o seu Pix' : 'O dono ainda não cadastrou o Pix') : e.mensagem),
        content: e.semConexao ? const Text('O Pix precisa de internet.') : null,
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('OK')),
          if (semPix && dono) FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cadastrar')),
        ],
      ),
    );
    if (cadastrar == true && context.mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const EmpresaTela()));
    }
    return null;
  }
}

/// Cobrar um pedido no Pix: gera a cobrança do saldo e abre a folha.
Future<void> cobrarPedido(BuildContext context,
    {required String pedidoId, String? telefone, required String Function(double valor, String codigo) mensagem}) async {
  final r = await gerarCobranca(context, {'pedido_id': pedidoId});
  if (r == null || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FolhaCobranca(pedidoId: pedidoId, inicial: r, telefone: telefone, mensagem: mensagem),
  );
}

/// Valor (editável), o copia e cola com copiar e o envio pronto (WhatsApp do cliente ou compartilhar).
class FolhaCobranca extends StatefulWidget {
  const FolhaCobranca({super.key, this.pedidoId, required this.inicial, this.telefone, required this.mensagem});
  final String? pedidoId;
  final Json inicial;
  final String? telefone;
  final String Function(double valor, String codigo) mensagem;

  @override
  State<FolhaCobranca> createState() => _FolhaCobrancaState();
}

class _FolhaCobrancaState extends State<FolhaCobranca> {
  late final _valor = ctrlDinheiro(num0(widget.inicial['valor']));
  late double _valorCodigo = num0(widget.inicial['valor']);

  /// null = o valor mudou e o código precisa ser gerado de novo.
  late String? _codigo = widget.inicial['copia_e_cola'] as String?;
  bool _copiado = false;
  bool _gerando = false;

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  /// O código sempre com o valor do campo (gera de novo se mudou).
  Future<String?> _garantir() async {
    final v = arred2(lerNumero(_valor.text) ?? 0);
    if (_codigo != null && (v - _valorCodigo).abs() < 0.005) return _codigo;
    if (v <= 0) return null;
    setState(() => _gerando = true);
    final r = await gerarCobranca(context, {'pedido_id': ?widget.pedidoId, 'valor': v});
    if (!mounted) return null;
    setState(() {
      _gerando = false;
      if (r != null) {
        _codigo = r['copia_e_cola'] as String?;
        _valorCodigo = num0(r['valor']);
      }
    });
    return r == null ? null : _codigo;
  }

  Future<void> _copiar() async {
    final c = await _garantir();
    if (c == null) return;
    await Clipboard.setData(ClipboardData(text: c));
    if (mounted) setState(() => _copiado = true);
  }

  Future<void> _enviar() async {
    final c = await _garantir();
    if (c == null) return;
    final texto = widget.mensagem(_valorCodigo, c);
    final tel = widget.telefone ?? '';
    if (tel.isNotEmpty) {
      await launchUrl(linkWhatsapp(tel, texto: texto), mode: LaunchMode.externalApplication);
    } else {
      await SharePlus.instance.share(ShareParams(text: texto));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final atual = _codigo != null && ((lerNumero(_valor.text) ?? 0) - _valorCodigo).abs() < 0.005;
    final whats = (widget.telefone ?? '').isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.pix),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Cobrar no Pix · ${widget.inicial['recebedor'] ?? ''}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ]),
          CampoDinheiro(_valor, 'Valor', key: const Key('valor-cobranca'), aoMudar: (_) => setState(() => _copiado = false)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
            child: _gerando
                ? const LinearProgressIndicator()
                : Text(atual ? _codigo! : 'Valor mudou: o código é gerado de novo ao copiar ou enviar',
                    key: const Key('copia-e-cola'),
                    style: TextStyle(
                        fontFamily: 'monospace', fontSize: 12, color: atual ? null : t.colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _gerando ? null : _copiar,
                icon: Icon(_copiado ? Icons.check : Icons.copy),
                label: Text(_copiado ? 'Copiado' : 'Copiar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: whats ? const Color(0xFF25D366) : null,
                    foregroundColor: whats ? Colors.white : null),
                onPressed: _gerando ? null : _enviar,
                icon: Icon(whats ? Icons.chat_outlined : Icons.share_outlined),
                label: Text(whats ? 'WhatsApp' : 'Enviar'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
