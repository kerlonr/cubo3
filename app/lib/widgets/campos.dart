import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/formatos.dart';

class CampoTexto extends StatelessWidget {
  const CampoTexto(this.controle, this.rotulo,
      {super.key, this.obrigatorio = false, this.teclado, this.linhas = 1, this.aoMudar, this.dica});

  final TextEditingController controle;
  final String rotulo;
  final bool obrigatorio;
  final TextInputType? teclado;
  final int linhas;
  final ValueChanged<String>? aoMudar;
  final String? dica;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          controller: controle,
          keyboardType: teclado,
          maxLines: linhas,
          onChanged: aoMudar,
          textCapitalization: teclado == null ? TextCapitalization.sentences : TextCapitalization.none,
          decoration: InputDecoration(labelText: rotulo, hintText: dica),
          validator: obrigatorio ? (v) => (v ?? '').trim().isEmpty ? 'Preencha $rotulo' : null : null,
        ),
      );
}

/// Número no padrão brasileiro com unidade ("g", "h", "min", "%").
class CampoNumero extends StatelessWidget {
  const CampoNumero(this.controle, this.rotulo,
      {super.key, this.sufixo, this.obrigatorio = false, this.aoMudar, this.minimo});

  final TextEditingController controle;
  final String rotulo;
  final String? sufixo;
  final bool obrigatorio;
  final ValueChanged<String>? aoMudar;
  final double? minimo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          controller: controle,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
          onChanged: aoMudar,
          decoration: InputDecoration(labelText: rotulo, suffixText: sufixo),
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
  const CampoDinheiro(this.controle, this.rotulo, {super.key, this.obrigatorio = false, this.aoMudar});

  final TextEditingController controle;
  final String rotulo;
  final bool obrigatorio;
  final ValueChanged<String>? aoMudar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          controller: controle,
          keyboardType: TextInputType.number,
          inputFormatters: [DinheiroFormatter()],
          onChanged: aoMudar,
          decoration: InputDecoration(labelText: rotulo, prefixText: 'R\$ '),
          validator: obrigatorio ? (v) => lerNumero(v) == null ? 'Preencha $rotulo' : null : null,
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
