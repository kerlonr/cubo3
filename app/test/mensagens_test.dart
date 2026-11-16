import 'package:cubo3/dominio/mensagens.dart';
import 'package:cubo3/telas/vendas/clientes_tela.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('telefone formatado: celular, fixo, com 55 e o que não reconhece', () {
    expect(formatarTelefone('54999998888'), '(54) 99999-8888');
    expect(formatarTelefone('+55 (54) 99999-8888'), '(54) 99999-8888');
    expect(formatarTelefone('5433334444'), '(54) 3333-4444');
    expect(formatarTelefone('123'), '123');
  });

  test('mensagem do pedido muda com a etapa', () {
    String m(String s) => mensagemPedido(nome: 'Ana Souza', status: s, itens: ['Vaso (2 un.)'], total: 45.9);
    expect(m('orcamento'), 'Olá, Ana! Segue o orçamento do seu pedido:\n• Vaso (2 un.)\n\nTotal: R\$ 45,90\n\nPosso confirmar?');
    expect(m('produzindo'), contains('em produção'));
    expect(m('aprovado'), contains('em produção'), reason: 'pedidos antigos');
    expect(m('pronto'), contains('está pronto'));
    expect(m('entregue'), startsWith('Olá, Ana! Obrigado'));
    expect(mensagemCliente(' Ana Souza'), 'Olá, Ana! Tudo bem? Aqui é da Cubo³.');
  });

  test('cobrança no Pix: oi, itens, valor e o copia e cola por último', () {
    expect(mensagemCobranca(nome: 'Ana Souza', itens: ['Vaso (2 un.)'], valor: 45.9, codigo: '000201abc'),
        'Olá, Ana! Segue o Pix do seu pedido:\n• Vaso (2 un.)\n\nValor: R\$ 45,90\n\nPix copia e cola:\n000201abc');
    expect(mensagemCobranca(nome: '', itens: [], valor: 10, codigo: 'x'), startsWith('Olá! Segue o Pix'));
  });

  test('link do WhatsApp leva o DDI e a mensagem pronta', () {
    final u = linkWhatsapp('(54) 99999-8888', texto: 'Olá, Ana!');
    expect(u.toString(), 'https://wa.me/5554999998888?text=Ol%C3%A1%2C+Ana%21');
  });
}
