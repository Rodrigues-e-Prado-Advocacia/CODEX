#!/usr/bin/env python3
"""
diagnostico_modem.py
====================
Analisa a SUA conexão local e recomenda a melhor forma de trocar o IP dinamico
(publico) SEM reiniciar o modem/roteador.

  >>> IMPORTANTE: rode este script na maquina que esta na SUA rede (o seu PC/
      notebook ligado no roteador). NAO rode em nuvem/servidor remoto — de la
      ele analisaria a rede errada.

Uso:
    python3 diagnostico_modem.py

O script e SOMENTE LEITURA: ele inspeciona/consulta, mas nao altera nenhuma
configuracao do modem, roteador ou operadora. Nao precisa de bibliotecas
externas (usa apenas a biblioteca padrao do Python 3).
"""

import ipaddress
import platform
import re
import socket
import struct
import subprocess
import sys
from urllib.request import Request, urlopen

TIMEOUT = 5  # segundos, para operacoes de rede


# --------------------------------------------------------------------------- #
# Utilidades                                                                   #
# --------------------------------------------------------------------------- #
def run(cmd):
    """Executa um comando de SO e devolve a saida (str) ou '' em caso de erro."""
    try:
        out = subprocess.run(
            cmd, capture_output=True, text=True, timeout=TIMEOUT, shell=False
        )
        return (out.stdout or "") + (out.stderr or "")
    except Exception:
        return ""


def secao(titulo):
    print("\n" + "=" * 68)
    print(f"  {titulo}")
    print("=" * 68)


def item(rotulo, valor):
    print(f"  {rotulo:<28} {valor}")


# --------------------------------------------------------------------------- #
# 1. Gateway (IP do roteador) e IP local                                      #
# --------------------------------------------------------------------------- #
def get_local_ip():
    """IP local desta maquina (truque do socket UDP, nao envia pacote real)."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(1)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return None


def get_default_gateway():
    """IP do gateway padrao (o roteador), multiplataforma."""
    system = platform.system()

    # Linux: le direto de /proc/net/route (mais confiavel)
    if system == "Linux":
        try:
            with open("/proc/net/route") as f:
                for line in f.readlines()[1:]:
                    fields = line.strip().split()
                    if len(fields) >= 4 and fields[1] == "00000000" and int(fields[3], 16) & 2:
                        return socket.inet_ntoa(struct.pack("<L", int(fields[2], 16)))
        except Exception:
            pass
        m = re.search(r"default via (\d+\.\d+\.\d+\.\d+)", run(["ip", "route", "show", "default"]))
        if m:
            return m.group(1)

    # macOS / BSD
    if system in ("Darwin", "FreeBSD", "OpenBSD"):
        m = re.search(r"gateway:\s*(\d+\.\d+\.\d+\.\d+)", run(["route", "-n", "get", "default"]))
        if m:
            return m.group(1)

    # Windows
    if system == "Windows":
        out = run(["ipconfig"])
        m = re.search(r"Default Gateway[.\s]*:\s*(\d+\.\d+\.\d+\.\d+)", out)
        if m and m.group(1) != "0.0.0.0":
            return m.group(1)

    # Fallback generico: netstat
    m = re.search(r"(?:default|0\.0\.0\.0)\s+(\d+\.\d+\.\d+\.\d+)", run(["netstat", "-rn"]))
    return m.group(1) if m else None


# --------------------------------------------------------------------------- #
# 2. IP publico (visto pela internet)                                         #
# --------------------------------------------------------------------------- #
def get_public_ip():
    servicos = [
        "https://api.ipify.org",
        "https://checkip.amazonaws.com",
        "https://ifconfig.me/ip",
        "https://icanhazip.com",
    ]
    for url in servicos:
        try:
            req = Request(url, headers={"User-Agent": "curl/8"})
            with urlopen(req, timeout=TIMEOUT) as r:
                ip = r.read().decode().strip()
                if re.match(r"^\d+\.\d+\.\d+\.\d+$", ip):
                    return ip
        except Exception:
            continue
    return None


# --------------------------------------------------------------------------- #
# 3. UPnP / TR-064 — descoberta do roteador e do IP WAN                        #
# --------------------------------------------------------------------------- #
def ssdp_discover():
    """Descobre dispositivos UPnP (roteador) via multicast SSDP. Retorna URLs."""
    locations = set()
    msg = (
        "M-SEARCH * HTTP/1.1\r\n"
        "HOST: 239.255.255.250:1900\r\n"
        'MAN: "ssdp:discover"\r\n'
        "MX: 2\r\n"
        "ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n"
    )
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        s.settimeout(3)
        s.sendto(msg.encode(), ("239.255.255.250", 1900))
        while True:
            try:
                data, _ = s.recvfrom(65507)
                m = re.search(r"LOCATION:\s*(\S+)", data.decode(errors="ignore"), re.I)
                if m:
                    locations.add(m.group(1).strip())
            except socket.timeout:
                break
        s.close()
    except Exception:
        pass
    return list(locations)


def _abs_url(base, path):
    if path.startswith("http"):
        return path
    m = re.match(r"(https?://[^/]+)", base)
    root = m.group(1) if m else base
    if not path.startswith("/"):
        path = "/" + path
    return root + path


def parse_upnp(location):
    """Baixa a descricao UPnP e extrai fabricante, modelo e servicos WAN."""
    info = {"location": location, "fabricante": None, "modelo": None, "servicos": []}
    try:
        with urlopen(location, timeout=TIMEOUT) as r:
            xml = r.read().decode(errors="ignore")
    except Exception:
        return info

    m = re.search(r"<manufacturer>(.*?)</manufacturer>", xml, re.I | re.S)
    info["fabricante"] = m.group(1).strip() if m else None
    m = re.search(r"<modelName>(.*?)</modelName>", xml, re.I | re.S)
    modelo = m.group(1).strip() if m else ""
    m = re.search(r"<modelNumber>(.*?)</modelNumber>", xml, re.I | re.S)
    if m and m.group(1).strip():
        modelo += " " + m.group(1).strip()
    info["modelo"] = modelo.strip() or None

    # Servicos WAN (PPP => PPPoE; IP => DHCP/estatico)
    for st, curl in re.findall(
        r"<serviceType>(.*?)</serviceType>.*?<controlURL>(.*?)</controlURL>", xml, re.I | re.S
    ):
        if "WANPPPConnection" in st or "WANIPConnection" in st:
            info["servicos"].append((st.strip(), _abs_url(location, curl.strip())))
    return info


def upnp_external_ip(service_type, control_url):
    """Chama GetExternalIPAddress via SOAP e devolve o IP WAN do roteador."""
    body = (
        '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        f'<s:Body><u:GetExternalIPAddress xmlns:u="{service_type}"/></s:Body>'
        "</s:Envelope>"
    )
    try:
        req = Request(
            control_url,
            data=body.encode(),
            headers={
                "Content-Type": 'text/xml; charset="utf-8"',
                "SOAPAction": f'"{service_type}#GetExternalIPAddress"',
            },
        )
        with urlopen(req, timeout=TIMEOUT) as r:
            resp = r.read().decode(errors="ignore")
        m = re.search(r"<NewExternalIPAddress>(.*?)</NewExternalIPAddress>", resp)
        return m.group(1).strip() if m else None
    except Exception:
        return None


# --------------------------------------------------------------------------- #
# 4. Portas de gerenciamento do roteador                                      #
# --------------------------------------------------------------------------- #
def scan_ports(host, ports):
    abertas = []
    for p in ports:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(1)
            if s.connect_ex((host, p)) == 0:
                abertas.append(p)
            s.close()
        except Exception:
            pass
    return abertas


def http_banner(host):
    for scheme, port in (("http", 80), ("https", 443)):
        try:
            req = Request(f"{scheme}://{host}:{port}/", headers={"User-Agent": "curl/8"})
            with urlopen(req, timeout=3) as r:
                server = r.headers.get("Server", "")
                html = r.read(2048).decode(errors="ignore")
                t = re.search(r"<title>(.*?)</title>", html, re.I | re.S)
                titulo = t.group(1).strip() if t else ""
                if server or titulo:
                    return f"{server}  |  titulo: {titulo}".strip(" |")
        except Exception:
            continue
    return None


# --------------------------------------------------------------------------- #
# 5. Modem movel (4G/5G) — portas seriais / ModemManager                       #
# --------------------------------------------------------------------------- #
def detect_mobile():
    achados = []
    system = platform.system()
    if system == "Linux":
        import glob
        for dev in sorted(glob.glob("/dev/ttyUSB*") + glob.glob("/dev/ttyACM*") + glob.glob("/dev/cdc-wdm*")):
            achados.append(dev)
        mm = run(["mmcli", "-L"])
        if "Modem" in mm or "/Modem/" in mm:
            achados.append("ModemManager: " + mm.strip().splitlines()[0] if mm.strip() else "ModemManager detectado")
    elif system == "Windows":
        out = run(["wmic", "path", "Win32_POTSModem", "get", "Name"])
        for ln in out.splitlines()[1:]:
            if ln.strip():
                achados.append(ln.strip())
    return achados


# --------------------------------------------------------------------------- #
# 6. Analise de CGNAT / NAT duplo                                             #
# --------------------------------------------------------------------------- #
def classifica_ip(ip):
    if not ip:
        return "desconhecido"
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return "invalido"
    if ipaddress.ip_address("100.64.0.0") <= addr <= ipaddress.ip_address("100.127.255.255"):
        return "CGNAT (100.64.0.0/10)"
    if addr.is_private:
        return "privado (NAT)"
    if addr.is_global:
        return "publico"
    return "outro"


# --------------------------------------------------------------------------- #
# Motor de recomendacao                                                        #
# --------------------------------------------------------------------------- #
def recomendar(dados):
    secao("RECOMENDACAO PERSONALIZADA")

    wan = dados.get("wan_ip")
    pub = dados.get("public_ip")
    servicos = dados.get("servicos", [])
    portas = dados.get("portas", [])
    movel = dados.get("movel", [])
    gw = dados.get("gateway")

    tipo_wan = classifica_ip(wan)
    cgnat = (
        (wan and tipo_wan.startswith("CGNAT"))
        or (wan and pub and wan != pub)  # IP WAN do roteador difere do IP publico => outra camada de NAT (CGNAT)
    )

    # ---- Caso 1: modem movel 4G/5G ----
    if movel:
        print("  CENARIO: Modem movel 4G/5G detectado.")
        print("  MELHOR METODO: comandos AT via pyserial (detach/attach da rede).")
        print("     A operadora quase sempre entrega um IP novo ao reanexar.\n")
        print("     pip install pyserial")
        print("     ------------------------------------------------------------")
        print("     import serial, time")
        porta = next((d for d in movel if d.startswith("/dev/tty") or d.upper().startswith("COM")), "/dev/ttyUSB2")
        print(f"     m = serial.Serial('{porta}', 115200, timeout=2)")
        print("     m.write(b'AT+CFUN=0\\r'); time.sleep(4)   # desliga o radio")
        print("     m.write(b'AT+CFUN=1\\r')                   # reanexa -> novo IP")
        print("     ------------------------------------------------------------")
        print("     (alternativa: AT+CGATT=0 e depois AT+CGATT=1)")
        if cgnat:
            print("\n  ATENCAO: parece haver CGNAT. Em 4G/5G isso e comum e o IP")
            print("  'publico' pode ser compartilhado — a troca pode nao te dar um IP unico.")
        return

    # ---- Alerta de CGNAT (vale para conexao fixa) ----
    if cgnat:
        secao_cg = []
        print("  !!! CGNAT / NAT DUPLO DETECTADO !!!")
        if wan:
            print(f"      IP WAN do roteador : {wan}  ({tipo_wan})")
        if pub:
            print(f"      IP publico real    : {pub}")
        print("""
      Voce esta atras do NAT da operadora. O 'IP publico' e COMPARTILHADO
      com outros clientes, entao trocar a sessao provavelmente NAO muda o
      IP que a internet enxerga — e, mesmo mudando, continua sem ser so seu.

      O que realmente resolve:
        - Pedir a operadora um IP publico dedicado (as vezes ha um plano/opcao,
          por vezes pago) ou saida de CGNAT.
        - Se o objetivo for acesso externo/DDNS: usar tunel reverso
          (Cloudflare Tunnel, Tailscale, ngrok) em vez de depender do IP.
""")
        # ainda assim mostramos o metodo de reconexao, caso a operadora rotacione
        print("  Se quiser tentar mesmo assim, siga o metodo de reconexao abaixo.\n")

    # ---- Caso 2: PPPoE via UPnP/TR-064 (melhor caminho em fibra BR) ----
    ppp = [(st, url) for st, url in servicos if "WANPPPConnection" in st]
    if ppp:
        st, url = ppp[0]
        print("  CENARIO: Conexao PPPoE com UPnP/TR-064 ativo (tipico de fibra no Brasil).")
        print("  MELHOR METODO: 'ForceTermination' via TR-064 — derruba e refaz a sessao")
        print("     PPPoE sem reiniciar o aparelho. Muito provavelmente gera IP novo.\n")
        print("     Se for FRITZ!Box:  pip install fritzconnection")
        print("        from fritzconnection import FritzConnection")
        print(f"        fc = FritzConnection(address='{gw}', password='SUA_SENHA')")
        print("        fc.call_action('WANPPPConnection', 'ForceTermination')\n")
        print("     Generico (qualquer roteador UPnP), usando o endpoint achado agora:")
        print("        POST", url)
        print(f"        SOAPAction: \"{st}#ForceTermination\"")
        print("        (corpo SOAP igual ao GetExternalIPAddress, trocando a acao)")
        return

    # ---- Caso 3: WANIPConnection (DHCP) via UPnP ----
    ipconn = [(st, url) for st, url in servicos if "WANIPConnection" in st]
    if ipconn:
        st, url = ipconn[0]
        print("  CENARIO: Conexao IP/DHCP com UPnP ativo (tipico de cabo/DOCSIS).")
        print("  METODO: 'ForceTermination'/'RequestConnection' via TR-064 no endpoint:")
        print("        POST", url, f"   (serviceType: {st})")
        print("""
     ATENCAO: em DHCP a operadora costuma devolver O MESMO IP para o mesmo MAC.
     Para forcar mudanca, quase sempre e preciso TROCAR O MAC da porta WAN no
     painel do roteador e so entao renovar o DHCP. (Trocar MAC pode ferir o
     contrato com o provedor — confira antes.)
""")
        return

    # ---- Caso 4: sem UPnP, mas SSH aberto (OpenWrt/Linux) ----
    if 22 in portas:
        print("  CENARIO: Sem UPnP, mas porta SSH (22) aberta no roteador.")
        print("     Se for OpenWrt/Linux, o caminho mais limpo e por SSH:\n")
        print("     pip install paramiko   (ou use o cliente ssh do sistema)")
        print("       comando remoto:  ifdown wan && sleep 3 && ifup wan")
        print("       (em alguns: /etc/init.d/network restart, ou 'ifup wan6' etc.)")
        return

    # ---- Caso 5: so painel web ----
    if 80 in portas or 443 in portas or 7547 in portas:
        print("  CENARIO: Sem UPnP/SSH; o roteador expoe painel web (e/ou TR-069 na 7547).")
        print("  METODO: automatizar o painel de admin (login + botao Desconectar/Conectar")
        print("     na WAN) com 'requests' ou Playwright. Precisa ser feito sob medida para")
        print("     o SEU modelo — cada painel tem endpoints/campos diferentes.\n")
        print("     Me diga marca+modelo e usuario/senha do painel que eu escrevo o script.")
        if 7547 in portas:
            print("\n     Obs: porta 7547 (TR-069) aberta = o modem e gerenciado remotamente")
            print("     pela operadora; as vezes ela bloqueia reconexao manual.")
        return

    # ---- Nada conclusivo ----
    print("  Nao consegui identificar automaticamente um metodo (UPnP/SSH/painel).")
    print("  Me passe: marca+modelo do modem, tipo de conexao (fibra PPPoE, cabo ou")
    print("  movel) e se tem acesso ao painel. Com isso eu monto o script certo.")


# --------------------------------------------------------------------------- #
# main                                                                         #
# --------------------------------------------------------------------------- #
def main():
    print("\n" + "#" * 68)
    print("#  DIAGNOSTICO DE TROCA DE IP DINAMICO  (somente leitura)")
    print("#  Rode este script NA SUA REDE (nao em nuvem).")
    print("#" * 68)

    dados = {}

    secao("1) Rede local")
    gw = get_default_gateway()
    local = get_local_ip()
    item("Sistema operacional:", f"{platform.system()} {platform.release()}")
    item("IP desta maquina:", local or "nao detectado")
    item("Gateway (roteador):", gw or "nao detectado")
    dados["gateway"] = gw

    secao("2) IP publico (visto pela internet)")
    pub = get_public_ip()
    item("IP publico:", pub or "nao detectado (sem internet? proxy?)")
    item("Classificacao:", classifica_ip(pub))
    dados["public_ip"] = pub

    secao("3) Roteador via UPnP / TR-064")
    servicos_all = []
    wan_ip = None
    modelo = fabricante = None
    if gw:
        locs = ssdp_discover()
        if not locs:
            print("  Nenhum dispositivo UPnP respondeu (UPnP pode estar desativado).")
        for loc in locs:
            info = parse_upnp(loc)
            if info["servicos"] or info["fabricante"]:
                fabricante = fabricante or info["fabricante"]
                modelo = modelo or info["modelo"]
                for st, url in info["servicos"]:
                    servicos_all.append((st, url))
                    if not wan_ip:
                        wan_ip = upnp_external_ip(st, url)
        item("Fabricante:", fabricante or "desconhecido")
        item("Modelo:", modelo or "desconhecido")
        item("Servicos WAN:", ", ".join(sorted({st.split(":")[-2] if ":" in st else st for st, _ in servicos_all})) or "nenhum")
        item("IP WAN do roteador:", wan_ip or "nao obtido")
        if wan_ip and pub:
            item("WAN == IP publico?", "SIM (IP publico direto)" if wan_ip == pub else "NAO -> indica CGNAT/NAT duplo")
    dados["servicos"] = servicos_all
    dados["wan_ip"] = wan_ip

    secao("4) Portas de gerenciamento do roteador")
    portas = []
    banner = None
    if gw:
        portas = scan_ports(gw, [22, 23, 80, 443, 7547])
        nomes = {22: "SSH", 23: "Telnet", 80: "HTTP", 443: "HTTPS", 7547: "TR-069/CWMP"}
        item("Abertas:", ", ".join(f"{p}/{nomes[p]}" for p in portas) or "nenhuma detectada")
        banner = http_banner(gw)
        if banner:
            item("Banner web:", banner[:60])
    dados["portas"] = portas

    secao("5) Modem movel (4G/5G)")
    movel = detect_mobile()
    item("Detectado:", ", ".join(movel) if movel else "nenhum")
    dados["movel"] = movel

    recomendar(dados)

    print("\n" + "-" * 68)
    print("Observacao: quem decide o IP final e a OPERADORA. O script forca a")
    print("renegociacao; se ela devolve um IP novo ou o mesmo depende da politica")
    print("dela (tempo de lease, vinculo por MAC, CGNAT).")
    print("-" * 68 + "\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(1)
