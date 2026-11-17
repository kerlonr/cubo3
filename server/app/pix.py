"""Pix copia e cola: BR Code estático do Banco Central (Manual de Padrões para Iniciação do Pix).

Não usa banco nem PSP: o código leva chave, valor e identificador; o app do cliente paga direto na conta.
"""
import re
import unicodedata
import uuid
from decimal import Decimal

TIPOS = ("cpf", "cnpj", "email", "telefone", "aleatoria")


def _campo(id_: str, valor: str) -> str:
    return f"{id_}{len(valor):02d}{valor}"


def crc16(dados: str) -> str:
    """CRC16-CCITT (polinômio 0x1021, início 0xFFFF), exigido no campo 63."""
    crc = 0xFFFF
    for b in dados.encode("utf-8"):
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else crc << 1
            crc &= 0xFFFF
    return f"{crc:04X}"


def _texto(s: str, maximo: int) -> str:
    """Nome e cidade só com letras sem acento, números e espaço (bancos recusam o resto)."""
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^A-Za-z0-9 .\-]", "", s).strip()[:maximo].strip()


def _digitos_ok(d: str, pesos_1: list[int], pesos_2: list[int]) -> bool:
    def dv(base: str, pesos: list[int]) -> int:
        r = sum(int(x) * p for x, p in zip(base, pesos)) % 11
        return 0 if r < 2 else 11 - r
    n = len(pesos_1)
    return dv(d[:n], pesos_1) == int(d[n]) and dv(d[:n + 1], pesos_2) == int(d[n + 1])


def normalizar_chave(tipo: str, chave: str) -> str:
    """Chave no formato que o Pix espera; ValueError com o motivo se não for válida."""
    c = chave.strip()
    if tipo in ("cpf", "cnpj") and re.search(r"[^\d.\-/ ]", c):
        raise ValueError(f"{tipo.upper()} só tem números")
    if tipo == "cpf":
        d = re.sub(r"\D", "", c)
        if len(d) != 11 or d == d[0] * 11 or not _digitos_ok(d, list(range(10, 1, -1)), list(range(11, 1, -1))):
            raise ValueError("CPF inválido")
        return d
    if tipo == "cnpj":
        d = re.sub(r"\D", "", c)
        p1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        if len(d) != 14 or d == d[0] * 14 or not _digitos_ok(d, p1, [6] + p1):
            raise ValueError("CNPJ inválido")
        return d
    if tipo == "email":
        e = c.lower()
        if len(e) > 77 or not e.isascii() or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", e):
            raise ValueError("E-mail inválido")
        return e
    if tipo == "telefone":
        d = re.sub(r"\D", "", c)
        if len(d) in (10, 11):
            d = "55" + d
        if not (d.startswith("55") and len(d) in (12, 13)):
            raise ValueError("Telefone inválido: use DDD + número")
        return "+" + d
    if tipo == "aleatoria":
        try:
            return str(uuid.UUID(c))
        except ValueError:
            raise ValueError("Chave aleatória inválida") from None
    raise ValueError("Tipo de chave inválido")


def mascarar(tipo: str, chave: str) -> str:
    """Para quem não é dono: dá para conferir qual chave é, sem expor ela inteira."""
    if tipo == "email":
        nome, _, dominio = chave.partition("@")
        return f"{nome[:2]}•••@{dominio}"
    return chave[:3] + "•" * max(len(chave) - 5, 3) + chave[-2:]


def exibir(tipo: str, chave: str) -> str:
    """Chave como a pessoa digita no app do banco: 529.982.247-25, (54) 99999-8888..."""
    if tipo == "cpf" and len(chave) == 11:
        return f"{chave[:3]}.{chave[3:6]}.{chave[6:9]}-{chave[9:]}"
    if tipo == "cnpj" and len(chave) == 14:
        return f"{chave[:2]}.{chave[2:5]}.{chave[5:8]}/{chave[8:12]}-{chave[12:]}"
    if tipo == "telefone" and len(chave) in (13, 14):
        d = chave[3:]
        return f"({d[:2]}) {d[2:-4]}-{d[-4:]}"
    return chave


def txid_de(id_: uuid.UUID | None) -> str:
    """Identificador que aparece no extrato do banco (até 25 letras e números)."""
    return ("CUBO3" + id_.hex[:20]).upper() if id_ else "***"


def copia_e_cola(chave: str, nome: str, cidade: str, valor: Decimal | None = None, txid: str = "***") -> str:
    conta = _campo("00", "br.gov.bcb.pix") + _campo("01", chave)
    p = _campo("00", "01") + _campo("26", conta) + _campo("52", "0000") + _campo("53", "986")
    if valor is not None:
        p += _campo("54", f"{Decimal(valor):.2f}")
    p += _campo("58", "BR") + _campo("59", _texto(nome, 25) or "RECEBEDOR") + _campo("60", _texto(cidade, 15) or "BRASIL")
    p += _campo("62", _campo("05", txid)) + "6304"
    return p + crc16(p)
