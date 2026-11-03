import 'api.dart';
import 'modelos.dart';

/// Comandos vão direto à API, nunca pela fila offline: um "cancelar" executado horas depois seria perigoso.
/// [extra] leva os campos das ações novas (eixos, eixo, distancia, nome).
Future<void> comandar(ApiCliente api, String impressoraId, String acao,
        {String? alvo, num? valor, Map<String, Object>? extra}) =>
    api.post('/api/impressoras/$impressoraId/comando', {'acao': acao, 'alvo': ?alvo, 'valor': ?valor, ...?extra});

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

/// Imprime um G-code que já está na impressora (409 = ocupada).
Future<void> imprimirDaImpressora(ApiCliente api, String impressoraId, String nome) =>
    api.post('/api/impressoras/$impressoraId/arquivos/imprimir', {'nome': nome});

/// G-code livre (até 500 caracteres; o servidor confere).
Future<void> enviarGcode(ApiCliente api, String impressoraId, String script) =>
    api.post('/api/impressoras/$impressoraId/gcode', {'script': script});

/// Caminho da miniatura de um arquivo da impressora (servida pela API).
String miniaturaDaImpressora(String impressoraId, String caminho) =>
    '/api/impressoras/$impressoraId/arquivos/miniatura?caminho=${Uri.encodeQueryComponent(caminho)}';

/// Recusa do Klipper que pede Home antes ("Klipper: Must home axis first...").
bool pedeHome(String mensagem) => mensagem.toLowerCase().contains('must home');
