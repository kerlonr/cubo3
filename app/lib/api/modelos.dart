import 'package:uuid/uuid.dart';

/// Helpers para ler o JSON da API sem `as` espalhado pelas telas.
typedef Json = Map<String, dynamic>;

const _uuid = Uuid();

/// Id gerado no aparelho para toda criação (o servidor trata o mesmo id como a mesma operação).
String novoId() => _uuid.v4();

double num0(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0 : 0);

double? numOu(Object? v) => v == null ? null : num0(v);

List<Json> lista(Object? v) => [for (final e in (v as List? ?? const [])) Map<String, dynamic>.from(e as Map)];

Json mapa(Object? v) => v == null ? <String, dynamic>{} : Map<String, dynamic>.from(v as Map);

/// Cor "#RRGGBB" → inteiro ARGB (cinza se vier vazia/inválida).
int corHex(Object? hex) {
  final s = (hex as String? ?? '').replaceFirst('#', '');
  return s.length == 6 ? int.tryParse('FF$s', radix: 16) ?? 0xFF9E9E9E : 0xFF9E9E9E;
}
