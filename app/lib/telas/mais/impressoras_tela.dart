import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/fila.dart';
import '../../api/modelos.dart';
import '../../util/formatos.dart';
import '../../widgets/campos.dart';
import '../../widgets/estado_tela.dart';
import '../impressoes/cartao_ao_vivo.dart';

/// R$ por hora com 4 casas (como a planilha: R$ 0,3414/h).
String custoHora(num v) => 'R\$ ${v.toStringAsFixed(4).replaceAll('.', ',')}/h';

class ImpressorasTela extends StatefulWidget {
  const ImpressorasTela({super.key});

  @override
  State<ImpressorasTela> createState() => _ImpressorasTelaState();
}

class _ImpressorasTelaState extends State<ImpressorasTela> {
  int _versao = 0;

  Future<void> _abrir(Widget tela) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => tela));
    if (ok == true) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impressoras'), actions: [
        IconButton(icon: const Icon(Icons.add), tooltip: 'Nova impressora', onPressed: () => _abrir(const ImpressoraForm())),
      ]),
      body: EstadoTela<List>(
        key: ValueKey(_versao),
        carregar: () => buscar(context, '/api/impressoras'),
        vazio: (l) => l.isEmpty,
        estadoVazio: EstadoVazio(
          icone: Icons.print_outlined,
          titulo: 'Nenhuma impressora',
          explicacao: 'Cadastre sua impressora: ela entra no custo de cada peça (energia e desgaste) e, com o Klipper, '
              'você acompanha a impressão ao vivo.',
          acao: 'Cadastrar impressora',
          aoTocar: () => _abrir(const ImpressoraForm()),
        ),
        construir: (context, l) => ListView(padding: const EdgeInsets.all(16), children: [
          for (final i in lista(l))
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${i['nome']}'),
                subtitle: Text([custoHora(num0(i['custo_hora'])), if ((i['moonraker_url'] ?? '') != '') '${i['moonraker_url']}']
                    .join(' · ')),
                onTap: () => _abrir(ImpressoraForm(dados: i)),
                trailing: (i['moonraker_url'] ?? '') == ''
                    ? null
                    : IconButton(
                        tooltip: 'Histórico do Klipper',
                        icon: const Icon(Icons.history),
                        onPressed: () => _abrir(HistoricoImpressoraTela(impressora: i)),
                      ),
              ),
            ),
        ]),
      ),
    );
  }
}

class ImpressoraForm extends StatefulWidget {
  const ImpressoraForm({super.key, this.dados});
  final Json? dados;

  @override
  State<ImpressoraForm> createState() => _ImpressoraFormState();
}

class _ImpressoraFormState extends State<ImpressoraForm> {
  final _form = GlobalKey<FormState>();
  late final Json d = widget.dados ?? {};
  late final String _id = d['id'] as String? ?? novoId();
  late String? _versaoBase = d['atualizado_em'] as String?;
  late final _nome = TextEditingController(text: d['nome'] as String?);
  late final _url = TextEditingController(text: d['moonraker_url'] as String?);
  late final _modelo = TextEditingController(text: d['modelo'] as String?);
  late final _preco = ctrlDinheiro(numOu(d['preco']) ?? 1660);
  late final _adicionais = ctrlDinheiro(numOu(d['adicionais']) ?? 0);
  late final _potencia = ctrlNumero(numOu(d['potencia_w']) ?? 150);
  late final _vida = ctrlNumero(numOu(d['vida_anos']) ?? 3);
  late final _uso = ctrlNumero(numOu(d['uso_pct']) ?? 50);
  late final _manutencao = ctrlNumero(numOu(d['manutencao_pct_ano']) ?? 10);
  final _chave = TextEditingController();
  bool _testando = false;
  String? _teste;

  Map<String, Object?> get _corpo => {
        'nome': _nome.text.trim(),
        'moonraker_url': _url.text.trim().isEmpty ? null : _url.text.trim(),
        'modelo': _modelo.text.trim().isEmpty ? null : _modelo.text.trim(),
        'preco': lerNumero(_preco.text) ?? 0,
        'adicionais': lerNumero(_adicionais.text) ?? 0,
        'potencia_w': lerNumero(_potencia.text) ?? 0,
        'vida_anos': lerNumero(_vida.text) ?? 3,
        'uso_pct': lerNumero(_uso.text) ?? 50,
        'manutencao_pct_ano': lerNumero(_manutencao.text) ?? 0,
        if (_chave.text.trim().isNotEmpty) 'api_key': _chave.text.trim(),
      };

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final ok = await salvar(context, 'PUT', '/api/impressoras/$_id', versaoBase: _versaoBase, _corpo);
    if (ok && mounted) Navigator.pop(context, true);
  }

  /// O servidor só conversa com o Klipper de impressora salva: grava e pergunta o estado ao vivo.
  Future<void> _testar() async {
    if (!_form.currentState!.validate()) return;
    final api = context.read<ApiCliente>();
    final fila = context.read<FilaOffline>();
    setState(() {
      _testando = true;
      _teste = null;
    });
    String resultado;
    try {
      final r = await fila.enviarOuGuardar(Operacao.nova('PUT', '/api/impressoras/$_id', _corpo, _versaoBase));
      if (r.recusada != null) {
        resultado = r.recusada!;
      } else if (r.guardada) {
        resultado = 'Sem internet: a impressora ficou salva no aparelho. Teste quando a conexão voltar.';
      } else {
        _versaoBase = mapa(r.resposta)['atualizado_em'] as String? ?? _versaoBase;
        final estado = mapa(await api.get('/api/impressoras/$_id/ao-vivo'))['estado'] as String?;
        resultado = switch (estado) {
          'desconectada' => 'Ainda sem resposta do Klipper. Confira o endereço e se a impressora está ligada, '
              'e tente de novo em alguns segundos.',
          'sem_integracao' => 'Sem endereço do Klipper.',
          _ => 'Conectou! A impressora está: ${nomeEstado(estado)}',
        };
      }
    } on ErroApi catch (e) {
      resultado = e.mensagem;
    }
    if (mounted) {
      setState(() {
        _testando = false;
        _teste = resultado;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget passo(int n, String titulo) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Row(children: [
            CircleAvatar(radius: 12, child: Text('$n', style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 8),
            Expanded(child: Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(widget.dados == null ? 'Nova impressora' : 'Editar impressora')),
      bottomNavigationBar: BotaoSalvarRodape(aoTocar: _salvar),
      body: CorpoFormulario(chave: _form, children: [
        passo(1, 'Nome'),
        CampoTexto(_nome, 'Como você chama esta impressora?',
            key: const Key('nome'), obrigatorio: true, dica: 'Ender 3 da bancada'),
        passo(2, 'Klipper (opcional)'),
        CampoTexto(_url, 'Endereço do Klipper (Moonraker)',
            key: const Key('url'),
            dica: 'http://192.168.1.110:7125',
            teclado: TextInputType.url,
            aoMudar: (_) => setState(() => _teste = null),
            ajuda: 'Ao vivo, câmera e gramas automáticos.'),
        Row(children: [
          OutlinedButton.icon(
            onPressed: _testando || _url.text.trim().isEmpty ? null : _testar,
            icon: _testando
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering),
            label: const Text('Testar conexão'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('O teste já salva a impressora.',
                style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
          ),
        ]),
        if (_teste != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_teste!)),
        passo(3, 'Custos'),
        Text('Valores comuns; ajuste se souber. Entram no custo de máquina de cada peça.',
            style: TextStyle(fontSize: 13, color: t.colorScheme.onSurfaceVariant)),
        CampoDinheiro(_preco, 'Preço da impressora'),
        CampoNumero(_potencia, 'Potência', sufixo: 'W', ajuda: 'Consumo médio imprimindo; 150 W é comum.'),
        MaisDetalhes(children: [
          CampoTexto(_modelo, 'Modelo', dica: 'Ender 3 V3 SE'),
          CampoDinheiro(_adicionais, 'Custos adicionais', ajuda: 'Peças e melhorias que você comprou para ela.'),
          CampoNumero(_vida, 'Vida útil', sufixo: 'anos', minimo: 0.1, ajuda: 'Em quantos anos ela se paga.'),
          CampoNumero(_uso, 'Uso do ano', sufixo: '%', minimo: 1, ajuda: '50% = imprime metade das horas do ano.'),
          CampoNumero(_manutencao, 'Manutenção por ano', sufixo: '% do preço', ajuda: 'Bicos, correias, mesa...'),
          CampoComAjuda(
            rotulo: 'Chave de API do Moonraker',
            ajuda: d['tem_api_key'] == true ? 'Já cadastrada; deixe vazio para manter.' : 'Só se o seu Moonraker pedir.',
            child: TextField(controller: _chave, obscureText: true),
          ),
        ]),
      ]),
    );
  }
}

/// Trabalhos do Klipper: o usuário traz só os que quiser (entram arquivados, nunca viram pendência).
class HistoricoImpressoraTela extends StatefulWidget {
  const HistoricoImpressoraTela({super.key, required this.impressora});
  final Json impressora;

  @override
  State<HistoricoImpressoraTela> createState() => _HistoricoImpressoraTelaState();
}

class _HistoricoImpressoraTelaState extends State<HistoricoImpressoraTela> {
  final _trazendo = <String>{};
  final _trazidos = <String>{};

  Future<void> _trazer(String job) async {
    setState(() => _trazendo.add(job));
    try {
      await context.read<ApiCliente>().post('/api/impressoras/${widget.impressora['id']}/historico/$job/trazer');
      _trazidos.add(job);
    } catch (e) {
      if (mounted) avisarErro(context, e);
    } finally {
      if (mounted) setState(() => _trazendo.remove(job));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Histórico · ${widget.impressora['nome']}')),
      body: EstadoTela<List>(
        carregar: () => buscar(context, '/api/impressoras/${widget.impressora['id']}/historico', query: {'limite': '50'}),
        vazio: (l) => l.isEmpty,
        estadoVazio: const EstadoVazio(
          icone: Icons.history,
          titulo: 'Histórico vazio',
          explicacao: 'O Klipper ainda não tem trabalhos registrados. Depois da primeira impressão eles aparecem aqui.',
        ),
        construir: (context, l) => ListView(padding: const EdgeInsets.all(16), children: [
          for (final j in lista(l))
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${j['arquivo']}', overflow: TextOverflow.ellipsis),
                subtitle: Text([
                  if (lerData(j['fim']) != null) dataHora(lerData(j['fim'])!),
                  duracao(num0(j['duracao_s'])),
                  if (j['gramas_total'] != null) gramas(num0(j['gramas_total'])),
                  '${j['status']}',
                ].join(' · ')),
                trailing: j['ja_trazido'] == true || _trazidos.contains(j['job_id'])
                    ? const Text('Trazido')
                    : TextButton(
                        onPressed: _trazendo.contains(j['job_id']) ? null : () => _trazer('${j['job_id']}'),
                        child: const Text('Trazer'),
                      ),
              ),
            ),
        ]),
      ),
    );
  }
}
