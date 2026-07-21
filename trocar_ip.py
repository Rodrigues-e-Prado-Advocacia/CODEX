#!/usr/bin/env python3
"""
trocar_ip.py
============
Troca o IP publico dinamico SEM reiniciar o modem, via UPnP/TR-064:
derruba a sessao WAN (ForceTermination) e o roteador reconecta sozinho,
normalmente com um IP novo.

Confirmado no cenario: ZTE F6600P (fibra, IP publico direto, SEM CGNAT).
Funciona em qualquer roteador que exponha, por UPnP, os servicos
WANPPPConnection (PPPoE) ou WANIPConnection (IP/DHCP).

Uso:
    python3 trocar_ip.py             # mostra o IP atual e pede confirmacao
    python3 trocar_ip.py --sim       # troca direto, sem perguntar
    python3 trocar_ip.py --mostrar   # SO mostra o IP atual (nao altera nada)

ATENCAO: isso derruba a internet por alguns segundos enquanto reconecta.
Nao requer bibliotecas externas (so a biblioteca padrao do Python 3).

Quem decide o IP final e a OPERADORA. O script forca a renegociacao; se ela
devolve um IP novo ou o mesmo depende da politica dela.
"""

import re
import socket
import sys
import time
from urllib.request import Request, urlopen

MULTICAST = ("239.255.255.250", 1900)
TIMEOUT = 6


# --------------------------------------------------------------------------- #
# Descoberta do roteador (SSDP) e leitura da descricao UPnP                    #
# --------------------------------------------------------------------------- #
def ssdp_locations():
    """Devolve as URLs de descricao (LOCATION) dos gateways UPnP na rede."""
    msg = (
        "M-SEARCH * HTTP/1.1\r\n"
        "HOST: 239.255.255.250:1900\r\n"
        'MAN: "ssdp:discover"\r\n'
        "MX: 2\r\n"
        "ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n"
    )
    locs = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        s.settimeout(3)
        s.sendto(msg.encode(), MULTICAST)
        while True:
            try:
                data, _ = s.recvfrom(65507)
                m = re.search(r"(?im)^LOCATION:\s*(\S+)", data.decode(errors="ignore"))
                if m and m.group(1) not in locs:
                    locs.append(m.group(1).strip())
            except socket.timeout:
                break
        s.close()
    except Exception as e:
        print(f"  (falha no SSDP: {e})")
    return locs


def _abs_url(base_location, url_base, path):
    if path.startswith("http"):
        return path
    root = url_base.rstrip("/") if url_base else re.match(r"(https?://[^/]+)", base_location).group(1)
    if not path.startswith("/"):
        path = "/" + path
    return root + path


def achar_servico_wan():
    """Procura o servico de conexao WAN e devolve (serviceType, controlURL, modelo)."""
    for loc in ssdp_locations():
        try:
            with urlopen(loc, timeout=TIMEOUT) as r:
                xml = r.read().decode(errors="ignore")
        except Exception:
            continue

        mb = re.search(r"<URLBase>(.*?)</URLBase>", xml, re.I | re.S)
        url_base = mb.group(1).strip() if mb else None

        mm = re.search(r"<modelName>(.*?)</modelName>", xml, re.I | re.S)
        modelo = mm.group(1).strip() if mm else "desconhecido"

        servicos = re.findall(
            r"<serviceType>(.*?)</serviceType>.*?<controlURL>(.*?)</controlURL>",
            xml, re.I | re.S,
        )
        # PPPoE tem prioridade (mais comum em fibra no Brasil)
        for chave in ("WANPPPConnection", "WANIPConnection"):
            for st, curl in servicos:
                if chave in st:
                    return st.strip(), _abs_url(loc, url_base, curl.strip()), modelo
    return None, None, None


# --------------------------------------------------------------------------- #
# Chamada SOAP generica                                                        #
# --------------------------------------------------------------------------- #
def soap(service_type, control_url, action, args=None):
    """Executa uma acao SOAP e devolve (ok, dict_de_saida_ou_erro)."""
    corpo_args = "".join(f"<{k}>{v}</{k}>" for k, v in (args or {}).items())
    body = (
        '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        f'<s:Body><u:{action} xmlns:u="{service_type}">{corpo_args}</u:{action}></s:Body>'
        "</s:Envelope>"
    )
    req = Request(
        control_url,
        data=body.encode(),
        headers={
            "Content-Type": 'text/xml; charset="utf-8"',
            "SOAPAction": f'"{service_type}#{action}"',
        },
    )
    try:
        with urlopen(req, timeout=TIMEOUT) as r:
            resp = r.read().decode(errors="ignore")
        saida = dict(re.findall(r"<(New\w+)>(.*?)</\1>", resp))
        return True, saida
    except Exception as e:
        detalhe = ""
        corpo = getattr(e, "file", None)
        try:
            texto = e.read().decode(errors="ignore") if hasattr(e, "read") else ""
            mc = re.search(r"<errorCode>(.*?)</errorCode>", texto)
            md = re.search(r"<errorDescription>(.*?)</errorDescription>", texto)
            if mc or md:
                detalhe = f" (erro {mc.group(1) if mc else '?'}: {md.group(1) if md else ''})"
        except Exception:
            pass
        return False, {"erro": f"{e}{detalhe}"}


def ip_externo(st, url):
    ok, out = soap(st, url, "GetExternalIPAddress")
    ip = out.get("NewExternalIPAddress", "") if ok else ""
    return ip if re.match(r"^\d+\.\d+\.\d+\.\d+$", ip or "") and ip != "0.0.0.0" else None


# --------------------------------------------------------------------------- #
# Fluxo principal de troca                                                     #
# --------------------------------------------------------------------------- #
def trocar(st, url, esperar=90):
    antigo = ip_externo(st, url)
    print(f"  IP atual: {antigo or '(desconectado?)'}")

    print("  Derrubando a sessao WAN (ForceTermination)...")
    ok, out = soap(st, url, "ForceTermination")
    if not ok:
        # alguns roteadores usam RequestTermination
        ok, out = soap(st, url, "RequestTermination")
    if not ok:
        print(f"  !! O roteador recusou o comando de desconexao: {out.get('erro')}")
        print("     Provavelmente o UPnP so permite LEITURA. Veja as alternativas no")
        print("     TROCA_IP.md (reconectar pelo painel http://192.168.1.1).")
        return False

    time.sleep(6)
    # garante a reconexao (se o auto-reconectar estiver desligado)
    soap(st, url, "RequestConnection")

    print("  Aguardando o roteador reconectar...", end="", flush=True)
    inicio = time.time()
    novo = None
    while time.time() - inicio < esperar:
        time.sleep(3)
        print(".", end="", flush=True)
        atual = ip_externo(st, url)
        if atual and atual != antigo:
            novo = atual
            break
    print()

    if novo:
        print(f"  >>> IP TROCADO:  {antigo}  ->  {novo}")
        return True
    if ip_externo(st, url) == antigo:
        print(f"  A conexao voltou, mas com O MESMO IP ({antigo}).")
        print("  A operadora reatribuiu o mesmo IP (lease/vinculo por sessao).")
        print("  Tente de novo mais tarde, ou peca IP dinamico 'rotativo'/fixo a ela.")
    else:
        print("  Nao consegui confirmar o novo IP no tempo esperado. Confira a conexao.")
    return False


def main():
    args = set(sys.argv[1:])
    print("\n=== Troca de IP dinamico via UPnP/TR-064 ===")
    st, url, modelo = achar_servico_wan()
    if not st:
        print("  Nenhum roteador com servico WAN via UPnP foi encontrado.")
        print("  Verifique se o UPnP esta ligado, ou use o painel http://192.168.1.1.")
        sys.exit(1)

    print(f"  Roteador: {modelo}")
    print(f"  Servico : {st.split(':')[-2]}")

    if {"--mostrar", "--show", "-m"} & args:
        print(f"  IP publico atual: {ip_externo(st, url) or '(nao obtido)'}")
        return

    if not ({"--sim", "--yes", "-y", "--force"} & args):
        print("\n  Isto vai DERRUBAR sua internet por alguns segundos para pegar um IP novo.")
        try:
            resp = input("  Continuar? [s/N] ").strip().lower()
        except EOFError:
            resp = "n"
        if resp not in ("s", "sim", "y", "yes"):
            print("  Cancelado.")
            return

    trocar(st, url)
    print("-" * 60)
    print("Obs: o IP final e decidido pela operadora; o script apenas forca a")
    print("renegociacao da sessao. Em CGNAT isso nao daria um IP proprio (nao e")
    print("o seu caso: seu IP publico esta direto na WAN do roteador).")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n  Interrompido.")
        sys.exit(1)
