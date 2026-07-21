# Trocar o IP dinâmico sem reiniciar o modem

Guia + ferramenta de diagnóstico para forçar a renegociação do IP público
**sem dar reboot** no modem/roteador.

> ⚠️ Quem decide o IP final é a **operadora**. O script apenas força a
> reconexão da sessão WAN; se você recebe um IP novo ou o mesmo depende da
> política da operadora (tempo de *lease*, vínculo por MAC, CGNAT).

## Já quer trocar o IP? (caso confirmado: ZTE F6600P, fibra, sem CGNAT)

Se o seu roteador expõe UPnP/TR-064 (o ZTE F6600P expõe), use um dos scripts
prontos — eles descobrem o roteador sozinhos, derrubam a sessão WAN
(`ForceTermination`) e verificam o IP novo:

- **Windows, sem instalar nada** — `trocar_ip.ps1` (PowerShell):
  ```powershell
  .\trocar_ip.ps1            # mostra o IP e pede confirmação
  .\trocar_ip.ps1 -Sim       # troca direto
  .\trocar_ip.ps1 -Mostrar   # só mostra o IP atual
  ```
- **Python (multiplataforma)** — `trocar_ip.py`:
  ```bash
  python3 trocar_ip.py           # mostra e pede confirmação
  python3 trocar_ip.py --sim     # troca direto
  python3 trocar_ip.py --mostrar # só mostra o IP atual
  ```

Ambos **derrubam a internet por alguns segundos** enquanto o roteador
reconecta. Se o roteador recusar o `ForceTermination` (alguns só permitem
leitura via UPnP), o caminho é o painel `http://192.168.1.1` → Internet/WAN →
Desconectar e Conectar.

## Como usar

Rode **na máquina que está na sua rede** (seu PC/notebook ligado no roteador) —
**não** em um servidor na nuvem, senão ele analisa a rede errada:

```bash
python3 diagnostico_modem.py
```

É **somente leitura**: inspeciona a rede e o roteador, mas **não altera nada**.
Não precisa instalar bibliotecas (usa só a biblioteca padrão do Python 3).

O script detecta automaticamente:

- Gateway (IP do roteador) e IP público;
- **CGNAT / NAT duplo** (compara o IP WAN do roteador com o IP público real);
- Fabricante/modelo e serviços WAN do roteador via **UPnP/TR-064**;
- Portas de gerência abertas (SSH, Telnet, HTTP/HTTPS, TR-069);
- **Modem móvel 4G/5G** (portas seriais / ModemManager).

No fim, imprime a **recomendação personalizada** para o seu caso.

## Métodos, por cenário

| Cenário detectado | Melhor método | Precisa de |
|---|---|---|
| **Fibra PPPoE** com UPnP/TR-064 | `ForceTermination` (derruba e refaz a sessão PPPoE) | UPnP ligado ou senha do painel |
| **Cabo/DHCP** com UPnP | reconexão TR-064; p/ mudar de fato, **trocar o MAC** da WAN e renovar DHCP | acesso ao painel |
| **Roteador OpenWrt/Linux** com SSH | `ifdown wan && ifup wan` via SSH | usuário/senha SSH |
| **Só painel web** | automatizar login + botão *Desconectar/Conectar* (`requests`/Playwright) | marca+modelo e credenciais |
| **Modem móvel 4G/5G** | comandos **AT** (`AT+CFUN=0` / `AT+CFUN=1`) via `pyserial` | porta serial do modem |

## O grande "porém": CGNAT

Muitos provedores no Brasil usam **CGNAT** — seu IP "público" é **compartilhado**.
Nesse caso, trocar a sessão **não** te dá um IP próprio. Sinais de CGNAT:

- IP WAN do roteador na faixa `100.64.0.0`–`100.127.255.255`; ou
- IP WAN do roteador **diferente** do IP público visto na internet.

Se for o seu caso, as saídas reais são:

- **Pedir à operadora** um IP público dedicado / saída de CGNAT (às vezes é
  uma opção do plano, às vezes paga); ou
- Se o objetivo é **acesso externo/DDNS**, usar um **túnel reverso**
  (Cloudflare Tunnel, Tailscale, ngrok) — aí o IP deixa de importar.

## Próximo passo

Rode o diagnóstico e me mande a saída (ou só o bloco *RECOMENDAÇÃO*). Com o
seu cenário em mãos, escrevo o **script de ação** pronto para o seu modelo —
inclusive automatizando o painel web, se for o caso.
