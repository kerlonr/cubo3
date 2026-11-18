import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
final _num2 = NumberFormat.decimalPattern('pt_BR')
  ..minimumFractionDigits = 0
  ..maximumFractionDigits = 2;
final _dataCurta = DateFormat('dd/MM/yyyy');
final _dataHora = DateFormat('dd/MM/yyyy HH:mm');
final _hora = DateFormat('HH:mm');

/// Arredonda para 2 casas com meio para cima (como o `ROUND_HALF_UP` do servidor).
/// Passa por texto com 6 casas para tirar o ruído binário: 2.675 vira "2.675000", não 2.67499…
double arred2(num v) {
  final p = v.abs().toStringAsFixed(6).split('.');
  var centavos = int.parse(p[0]) * 100 + int.parse(p[1].substring(0, 2));
  if (int.parse(p[1][2]) >= 5) centavos++;
  return (v < 0 ? -centavos : centavos) / 100;
}

String moeda(num v) => _moeda.format(arred2(v)).replaceAll(' ', ' ');

String numero(num v) => _num2.format(v);

String gramas(num v) => '${numero(v)} g';

String dataCurta(DateTime d) => _dataCurta.format(d.toLocal());

String dataHora(DateTime d) => _dataHora.format(d.toLocal());

String hora(DateTime d) => _hora.format(d.toLocal());

/// Data do servidor (ISO) ou null.
DateTime? lerData(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// "novembro 2026" → "Novembro 2026" (o intl devolve o mês em minúscula).
String capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "AAAA-MM-DD" do dia local (campos `date` do servidor).
String diaIso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Duração em segundos → "3h05" ou "12 min".
String duracao(num segundos) {
  final m = (segundos / 60).round();
  if (m < 60) return '$m min';
  return '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
}

/// Converte texto digitado no padrão brasileiro ("1.234,56", "33,5 g", "R$ 12,90") em número.
/// Texto vazio ou inválido → null (nunca lança).
double? lerNumero(String? texto) {
  var t = (texto ?? '').replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    t = t.replaceAll('.', ''); // "1.000" no padrão brasileiro é mil
  }
  return double.tryParse(t);
}

/// Número para preencher campo de edição (vírgula decimal, sem milhar).
String paraCampo(double? v) {
  if (v == null) return '';
  return v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '').replaceAll('.', ',');
}

/// Dinheiro como em app de banco: a pessoa só digita números e o valor
/// vai se formando da direita para a esquerda (5 → 0,05 → 50,00 ...).
class DinheiroFormatter extends TextInputFormatter {
  static final _f = NumberFormat.currency(locale: 'pt_BR', symbol: '', decimalDigits: 2);

  static String formatar(double? v) => v == null ? '' : _f.format(v).replaceAll(' ', '').trim();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue antigo, TextEditingValue novo) {
    final digitos = novo.text.replaceAll(RegExp(r'\D'), '');
    if (digitos.isEmpty) return const TextEditingValue();
    final valor = int.parse(digitos.length > 12 ? digitos.substring(0, 12) : digitos) / 100;
    final t = formatar(valor);
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}
