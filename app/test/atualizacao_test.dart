import 'package:cubo3/atualizacao.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio.dart';

void main() {
  test('build do servidor maior que o do app pede atualização', () {
    expect(precisaAtualizar(buildApp: 3, resposta: {'build': 4}), isTrue);
    expect(precisaAtualizar(buildApp: 3, resposta: {'build': 3}), isFalse);
    expect(precisaAtualizar(buildApp: 3, resposta: {'build': '5'}), isTrue);
    expect(precisaAtualizar(buildApp: 3, resposta: null), isFalse);
  });

  test('sem versão publicada (404) não pede atualização', () async {
    final amb = Ambiente({'GET /api/versao': (_) => json({'detail': 'Nenhuma versão do app publicada'}, 404)});
    await amb.preparar();
    expect(await consultarAtualizacao(amb.api, buildApp: 3), isFalse);
    final nova = Ambiente({'GET /api/versao': (_) => {'versao': '1.1.0', 'build': 4, 'apk_url': '/baixar'}});
    await nova.preparar();
    expect(await consultarAtualizacao(nova.api, buildApp: 3), isTrue);
  });
}
