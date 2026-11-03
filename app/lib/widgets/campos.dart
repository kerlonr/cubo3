import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema.dart';
import '../util/formatos.dart';

/// Rótulo acima do campo e, se houver, uma linha de ajuda em linguagem simples.
class CampoComAjuda extends StatelessWidget {
  const CampoComAjuda({super.key, required this.rotulo, this.ajuda, required this.child});

  final String rotulo;
  final String? ajuda;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(rotulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        if (ajuda != null) Text(ajuda!, style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        child,
      ]),
    );
  }
}

class CampoTexto extends StatelessWidget {
  const CampoTexto(this.controle, this.rotulo,
      {super.key, this.obrigatorio = false, this.teclado, this.linhas = 1, this.aoMudar, this.dica, this.ajuda});

  final TextEditingController controle;
  final String rotulo;
  final bool obrigatorio;
  final TextInputType? teclado;
  final int linhas;
  final ValueChanged<String>? aoMudar;
  final String? dica;
  final String? ajuda;

  @override
  Widget build(BuildContext context) => CampoComAjuda(
        rotulo: rotulo,
        ajuda: ajuda,
        child: TextFormField(
          controller: controle,
          keyboardType: teclado,
          maxLines: linhas,
          onChanged: aoMudar,
          textCapitalization: teclado == null ? TextCapitalization.sentences : TextCapitalization.none,
          decoration: InputDecoration(hintText: dica),
          validator: obrigatorio ? (v) => (v ?? '').trim().isEmpty ? 'Preencha $rotulo' : null : null,
        ),
      );
}

/// Número no padrão brasileiro com unidade ("g", "h", "min", "%").
class CampoNumero extends StatelessWidget {
  const CampoNumero(this.controle, this.rotulo,
      {super.key, this.sufixo, this.obrigatorio = false, this.aoMudar, this.minimo, this.ajuda});

  final TextEditingController controle;
  final String rotulo;
  final String? sufixo;
  final bool obrigatorio;
  final ValueChanged<String>? aoMudar;
  final double? minimo;
  final String? ajuda;

  @override
  Widget build(BuildContext context) => CampoComAjuda(
        rotulo: rotulo,
        ajuda: ajuda,
        child: TextFormField(
          controller: controle,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
          onChanged: aoMudar,
          decoration: InputDecoration(suffixText: sufixo),
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return obrigatorio ? 'Preencha $rotulo' : null;
            final n = lerNumero(v);
            if (n == null) return 'Número inválido';
            if (minimo != null && n < minimo!) return 'Mínimo ${numero(minimo!)}';
            return null;
          },
        ),
      );
}

/// Dinheiro digitado como em app de banco (só números; vírgula automática).
class CampoDinheiro extends StatelessWidget {
  const CampoDinheiro(this.controle, this.rotulo, {super.key, this.obrigatorio = false, this.aoMudar, this.ajuda});

  final TextEditingController controle;
  final String rotulo;
  final bool obrigatorio;
  final ValueChanged<String>? aoMudar;
  final String? ajuda;

  @override
  Widget build(BuildContext context) => CampoComAjuda(
        rotulo: rotulo,
        ajuda: ajuda,
        child: TextFormField(
          controller: controle,
          keyboardType: TextInputType.number,
          inputFormatters: [DinheiroFormatter()],
          onChanged: aoMudar,
          decoration: const InputDecoration(prefixText: 'R\$ '),
          validator: obrigatorio ? (v) => lerNumero(v) == null ? 'Preencha $rotulo' : null : null,
        ),
      );
}

/// Poucas opções: chips em vez de lista suspensa (um toque, tudo à vista).
class SeletorChips<T> extends StatelessWidget {
  const SeletorChips({super.key, required this.opcoes, required this.valor, required this.aoMudar});

  final Map<T, String> opcoes;
  final T? valor;
  final ValueChanged<T> aoMudar;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in opcoes.entries)
          ChoiceChip(label: Text(e.value), selected: e.key == valor, onSelected: (_) => aoMudar(e.key)),
      ]);
}

/// − quantidade + (sem teclado).
class Quantidade extends StatelessWidget {
  const Quantidade({super.key, required this.valor, required this.aoMudar, this.minimo = 1});

  final int valor;
  final ValueChanged<int> aoMudar;
  final int minimo;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton.outlined(
            tooltip: 'Menos', onPressed: valor > minimo ? () => aoMudar(valor - 1) : null, icon: const Icon(Icons.remove)),
        SizedBox(
          width: 44,
          child: Text('$valor',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, fontFeatures: tabular)),
        ),
        IconButton.outlined(tooltip: 'Mais', onPressed: () => aoMudar(valor + 1), icon: const Icon(Icons.add)),
      ]);
}

/// Botão Salvar fixo no rodapé (vai no `bottomNavigationBar` do Scaffold) e acima do teclado.
class BotaoSalvarRodape extends StatelessWidget {
  const BotaoSalvarRodape({super.key, required this.aoTocar, this.rotulo = 'Salvar'});

  final VoidCallback? aoTocar;
  final String rotulo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 608),
                child: FilledButton(
                  onPressed: aoTocar,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(rotulo),
                ),
              ),
            ),
          ),
        ),
      );
}


/// Controle de texto já preenchido com um valor em R$ / número.
TextEditingController ctrlDinheiro(num? v) => TextEditingController(text: DinheiroFormatter.formatar(v?.toDouble()));
TextEditingController ctrlNumero(num? v) => TextEditingController(text: paraCampo(v?.toDouble()));

/// "Mais detalhes": o resto do formulário fica escondido.
class MaisDetalhes extends StatelessWidget {
  const MaisDetalhes({super.key, required this.children, this.titulo = 'Mais detalhes'});
  final List<Widget> children;
  final String titulo;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        title: Text(titulo, style: const TextStyle(fontSize: 14)),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        children: children,
      );
}

/// Corpo de formulário com largura máxima confortável no navegador.
class CorpoFormulario extends StatelessWidget {
  const CorpoFormulario({super.key, required this.children, this.chave});
  final List<Widget> children;
  final GlobalKey<FormState>? chave;

  @override
  Widget build(BuildContext context) => Form(
        key: chave,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.all(16), children: children),
          ),
        ),
      );
}
