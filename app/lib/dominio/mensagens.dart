/// Mensagens prontas para o WhatsApp e formato de telefone.
library;

import '../util/formatos.dart';

String primeiroNome(String nome) => nome.trim().split(RegExp(r'\s+')).first;

/// "54999998888" → "(54) 99999-8888"; o que não for celular/fixo brasileiro fica como veio.
String formatarTelefone(String telefone) {
  var d = telefone.replaceAll(RegExp(r'\D'), '');
  if (d.length == 13 && d.startsWith('55')) d = d.substring(2);
  if (d.length == 11) return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
  if (d.length == 10) return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
  return telefone.trim();
}

/// Abertura de conversa com o cliente.
String mensagemCliente(String nome) => 'Olá, ${primeiroNome(nome)}! Tudo bem? Aqui é da Cubo³.';

/// Mensagem do pedido conforme a etapa: orçamento com itens e total, produção, pronto ou agradecimento.
String mensagemPedido({required String nome, required String status, required List<String> itens, required double total}) {
  final oi = 'Olá, ${primeiroNome(nome)}!';
  final lista = itens.map((i) => '• $i').join('\n');
  return switch (status) {
    'orcamento' => '$oi Segue o orçamento do seu pedido:\n$lista\n\nTotal: ${moeda(total)}\n\nPosso confirmar?',
    'aprovado' || 'produzindo' => '$oi Seu pedido já está em produção:\n$lista\n\nTe aviso assim que ficar pronto.',
    'pronto' => '$oi Seu pedido está pronto:\n$lista\n\nQual o melhor horário para entregar ou retirar?',
    'entregue' => '$oi Obrigado pela compra! Qualquer coisa com as peças, é só chamar.',
    _ => mensagemCliente(nome),
  };
}
