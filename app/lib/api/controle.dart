import 'api.dart';
import 'modelos.dart';

/// Comandos vão direto à API, nunca pela fila offline: um "cancelar" executado horas depois seria perigoso.
Future<void> comandar(ApiCliente api, String impressoraId, String acao, {String? alvo, num? valor}) =>
    api.post('/api/impressoras/$impressoraId/comando', {'acao': acao, 'alvo': ?alvo, 'valor': ?valor});

/// Ajusta bico e/ou mesa (um pedido por aquecedor; para no primeiro erro).
Future<void> mudarTemperaturas(ApiCliente api, String impressoraId, {num? bico, num? mesa}) async {
  if (bico != null) await comandar(api, impressoraId, 'temperatura', alvo: 'bico', valor: bico);
  if (mesa != null) await comandar(api, impressoraId, 'temperatura', alvo: 'mesa', valor: mesa);
}

const atalhosTemperatura = {
  'PLA': (bico: 200, mesa: 60),
  'PETG': (bico: 235, mesa: 80),
  'Desligar': (bico: 0, mesa: 0),
};

/// Link do vídeo ao vivo; vale 60 s para abrir, então peça um novo a cada abertura.
Future<Uri> linkCamera(ApiCliente api, String impressoraId) async {
  final url = mapa(await api.post('/api/impressoras/$impressoraId/camera/link'))['url'];
  if (url is! String) throw ErroApi(200, 'Câmera indisponível');
  return api.url(url);
}

Future<void> imprimirArquivo(ApiCliente api, String arquivoId, String impressoraId) =>
    api.post('/api/arquivos/$arquivoId/imprimir', {'impressora_id': impressoraId});
