import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api.dart';
import '../tema.dart';

/// Total grande com rótulo pequeno acima.
class CartaoValor extends StatelessWidget {
  const CartaoValor(this.titulo, this.valor, {super.key, this.cor, this.icone, this.aoTocar});

  final String titulo;
  final String valor;
  final Color? cor;
  final IconData? icone;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icone != null) ...[Icon(icone, size: 16, color: t.colorScheme.onSurfaceVariant), const SizedBox(width: 6)],
              Expanded(
                child: Text(titulo,
                    style: TextStyle(fontSize: 13, color: t.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
              ),
            ]),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(valor,
                  softWrap: false, // sem quebra: a altura medida é a de uma linha (o FittedBox só encolhe)
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w600, color: cor, fontFeatures: tabular, letterSpacing: -0.5)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Título de seção com espaço generoso.
class Secao extends StatelessWidget {
  const Secao(this.titulo, {super.key, this.acao});
  final String titulo;
  final Widget? acao;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(child: Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
          ?acao,
        ]),
      );
}

/// Selo pequeno colorido ("baixo", "excluído", status).
class Selo extends StatelessWidget {
  const Selo(this.texto, {super.key, this.cor});
  final String texto;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = cor ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(texto, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Estoque baixo: chamada para repor (filamento/insumo).
class ChipRepor extends StatelessWidget {
  const ChipRepor({super.key});

  @override
  Widget build(BuildContext context) => const Selo('Repor', cor: amarelo);
}

/// Cor de lucro/prejuízo.
Color corResultado(num v) => v < 0 ? vermelho : verde;

/// Bolinha com a cor do filamento.
class BolinhaCor extends StatelessWidget {
  const BolinhaCor(this.cor, {super.key, this.tamanho = 18});
  final int cor;
  final double tamanho;

  @override
  Widget build(BuildContext context) => Container(
        width: tamanho,
        height: tamanho,
        decoration: BoxDecoration(
          color: Color(cor),
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      );
}

/// Imagem protegida da API (capa, miniatura): manda o token junto.
class ImagemApi extends StatelessWidget {
  const ImagemApi(this.caminho, {super.key, this.ajuste = BoxFit.cover});
  final String? caminho;
  final BoxFit ajuste;

  @override
  Widget build(BuildContext context) {
    final vazio = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Icon(Icons.view_in_ar_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
    if (caminho == null) return vazio;
    final api = context.read<ApiCliente>();
    return Image.network(api.url(caminho!).toString(),
        headers: api.cabecalhosAuth, fit: ajuste, errorBuilder: (_, _, _) => vazio);
  }
}
