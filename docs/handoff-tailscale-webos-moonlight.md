# Handoff: Tailscale para LG webOS (Homebrew) — Streaming remoto Moonlight/Sunshine

Documento de handoff técnico. Objetivo: dar ao agente responsável pela implementação todo o
levantamento de tecnologias, links, comandos e decisões de arquitetura necessários para
começar a construir sem pesquisa adicional de viabilidade.

---

## 1. Objetivo do projeto

Empacotar o `tailscaled`/`tailscale` (binários oficiais, open source) como um app do webOS
Homebrew Channel para uma LG TV rooteada, para que a TV entre como nó completo na tailnet
existente do usuário. Caso de uso único e concreto: rodar o Moonlight (já instalado via
Homebrew) na TV e conectar no Sunshine do desktop gamer em casa, enquanto o usuário está
fisicamente em outra rede (ex.: streaming remoto de fora de casa).

Não é necessário nenhum tratamento especial de portas: Tailscale opera na camada IP. Uma vez
que a TV esteja autenticada na tailnet, todo o tráfego entre TV e desktop (as portas do
Sunshine incluídas) passa a fluir normalmente pelo IP Tailscale do desktop, sem qualquer lógica
de forwarding por porta.

Não há requisito de ACL/restrição de acesso — a TV deve se comportar como qualquer outro nó
da tailnet do usuário (mesmo nível de acesso que notebook, PC do escritório etc.).

Projeto será open source, licença permissiva (sugestão: MIT para o código do app, mantendo as
licenças originais dos componentes do Tailscale — ver seção 8).

---

## 2. Ambiente atual do usuário (contexto confirmado em conversa)

- LG TV com webOS, **rooteada** (via RootMyTV) e com **Homebrew Channel** instalado.
- App **Moonlight** já instalado via Homebrew Channel na TV.
- App **WireGuard for webOS** (`com.github.cfernande1470.wireguard`) já instalado/testado na
  TV — prova de conceito de que túnel WireGuard userspace funciona nesse hardware/firmware.
- Desktop gamer, notebook e PC do escritório já são nós de uma tailnet Tailscale existente do
  usuário (contas/infra já em produção).
- Objetivo é reaproveitar essa tailnet, sem depender de app adicional no desktop.

**Dado que falta confirmar com o usuário antes de compilar:** modelo exato da LG TV e saída de
`uname -m` via SSH (Homebrew Channel expõe SSH root — ver seção 6). Isso determina se o build
precisa ser `arm` (32-bit, ARMv7) ou `arm64`/`aarch64`.

---

## 3. Decisão de arquitetura

Não é necessário reimplementar nenhuma lógica de rede, NAT traversal, handshake ou criptografia.
`tailscaled` já embute o `wireguard-go` (motor WireGuard em userspace) e toda a lógica de
coordenação (DERP relay, STUN/hole punching, MagicDNS, etc.) internamente. Como esse mesmo
mecanismo de TUN userspace já roda em produção nessa TV via o app WireGuard existente, o
trabalho aqui é essencialmente de **empacotamento e integração com o modelo de app do
Homebrew Channel**, reaproveitando os padrões já validados pelo projeto `webos-wireguard`.

Modo de operação: **TUN completo** (não `--tun=userspace-networking`). O modo full-TUN cria uma
interface de rede real com rota no kernel, permitindo que o Moonlight na TV conecte direto no
IP Tailscale do desktop sem proxy intermediário. É exatamente o modo que o `webos-wireguard` já
usa com sucesso.

---

## 4. Stack e repositórios de referência

### 4.1 Tailscale (upstream)

- Repositório principal: https://github.com/tailscale/tailscale — licença BSD-3-Clause.
- Guia oficial de build para binário combinado/reduzido (embedded devices):
  https://tailscale.com/docs/how-to/set-up-small-tailscale
- Script de build oficial (recomendado para builds de distribuição, grava versão/commit no
  binário): https://github.com/tailscale/tailscale/blob/main/build_dist.sh
- Documentação de auth keys: https://tailscale.com/docs/features/access-control/auth-keys
- "Run unattended" (comportamento em Linux sem usuário logado):
  https://tailscale.com/docs/how-to/run-unattended
- Referência da CLI (`tailscale up`, flags): https://tailscale.com/docs/reference/tailscale-cli

### 4.2 Referência de empacotamento webOS (reaproveitar como base)

- `webos-wireguard` (WireGuard for LG webOS Homebrew), MIT license:
  https://github.com/cfernande1470/webos-wireguard
  - Prova viva de que `wireguard-go` (mesma tecnologia de base do `tailscaled`) roda em
    produção nessa TV via Homebrew Channel, incluindo TUN userspace, autostart no boot e
    execução como root via serviço do Homebrew.
  - Estrutura de projeto, scripts de start/stop/autostart e o hook de boot devem ser usados
    como ponto de partida (ver seção 6).

### 4.3 webOS Homebrew Channel (mecanismo de root/autostart)

- Projeto/serviço root: https://github.com/webosbrew/webos-homebrew-channel
- Portal de documentação da comunidade: https://www.webosbrew.org
- Especificação do `appinfo.json`: https://www.webosbrew.org/pages/appinfojson
- Cheatsheet de comandos `luna-send`: https://www.webosbrew.org/pages/commands-cheatsheet

### 4.4 Moonlight / Sunshine (só para referência de portas — não é bloqueante, ver seção 1)

- Guia oficial de portas: https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide
- Projeto Sunshine (host): https://github.com/LizardByte/Sunshine

---

## 5. Build do Tailscale — comandos confirmados

Ambiente: Go instalado, `CGO_ENABLED=0` (build puramente Go, sem toolchain C cruzado — mesma
abordagem usada pelo `webos-wireguard` para `wireguard-go`).

### 5.1 Binário combinado (tailscale + tailscaled em um único arquivo)

O Tailscale usa o mesmo truque do busybox: o binário se comporta como `tailscale` ou
`tailscaled` dependendo do nome do arquivo/argv[0]. Isso reduz o app a um único binário +
symlinks.

```bash
git clone https://github.com/tailscale/tailscale
cd tailscale
git checkout v<VERSAO_ESTAVEL_MAIS_RECENTE>   # ver releases no GitHub

CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 \
  go build -o tailscale.combined -tags ts_include_cli -trimpath -ldflags="-s -w" \
  ./cmd/tailscaled
```

Para TVs `aarch64` (64-bit), trocar por `GOARCH=arm64` (sem `GOARM`). Assim como o
`webos-wireguard`, considerar buildar **ambas** as variantes e o script de instalação escolher
a certa com base em `uname -m` lido na própria TV.

Criar os symlinks:

```bash
ln -s tailscale.combined tailscale
ln -s tailscale.combined tailscaled
```

### 5.2 Build "extra small" (recomendado para reduzir tamanho do pacote)

```bash
./build_dist.sh --extra-small tailscale.com/cmd/tailscaled
```

Isso já inclui o stamping de versão/commit (equivalente ao que o `build_dist.sh` faz para
builds de distribuição oficiais) e omite funcionalidades pouco usadas em ambiente embarcado.

### 5.3 Compressão com UPX (opcional, avaliar trade-off)

A documentação oficial reporta redução de ~23 MiB para ~4.5 MiB nesse binário combinado após
UPX. Ressalva da própria documentação: packers alteram como o binário interage com o SO (podem
exigir W^X desabilitado) — validar se isso é aceitável no ambiente restrito do webOS antes de
adotar em produção.

```bash
upx --lzma --best ./tailscale.combined
```

### 5.4 Build tags relevantes

- `ts_include_cli`: inclui a CLI `tailscale` no mesmo binário do `tailscaled` (necessário para
  o truque do binário combinado).
- Existe um projeto comunitário de referência ("Small Tailscale", builds automatizados para
  roteadores/OpenWrt com esse mesmo tag + UPX) que pode servir de inspiração para o pipeline de
  CI: https://github.com/admonstrator/glinet-tailscale-updater — **não oficial da Tailscale
  Inc.**, mas útil como exemplo de pipeline reproduzível.

---

## 6. Integração com o Homebrew Channel (padrão a seguir)

Baseado 1:1 na estrutura já validada do `webos-wireguard`:

### 6.1 Requisitos confirmados

- TV rooteada + Homebrew Channel instalado (já é o caso do usuário).
- Serviço root do Homebrew disponível (`org.webosbrew.hbchannel.service`).
- `/dev/net/tun` presente no kernel da TV (confirmado indiretamente: o app WireGuard já
  depende disso e funciona).
- Arquitetura de CPU compatível — confirmar com `uname -m` via SSH.

### 6.2 Execução privilegiada

Comandos como root são executados via serviço Luna do Homebrew Channel:

```bash
luna-send -n 1 'luna://org.webosbrew.hbchannel.service/exec' '{"command":"<comando>"}'
```

Alternativa para serviços homebrew próprios: `elevate-service`, que remove as restrições de
permissão do Luna bus para um serviço específico do app
(`/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service/elevate-service
<nome-do-servico>`).

### 6.3 Autostart no boot

Scripts executáveis colocados em `/var/lib/webosbrew/init.d/` rodam automaticamente no boot.
O `webos-wireguard` usa um **symlink** para o `boot.sh` empacotado dentro do diretório da
própria app (não uma cópia) — isso garante que, se o app for desinstalado, o link vira
não-executável e o hook runner do Homebrew o ignora automaticamente, sem VPN "fantasma"
tentando subir. Replicar exatamente esse padrão para o `tailscaled`.

### 6.4 Execução como daemon de longa duração

Ponto importante confirmado na documentação oficial do Tailscale: em Linux, `tailscaled` roda
como processo de sistema e continua disponível mesmo sem usuário logado — não existe o
conceito de "modo unattended" que existe no Windows; em Linux esse já é o comportamento padrão.
Isso significa que o mesmo padrão do `webos-wireguard` (o boot hook simplesmente inicia o
processo em background e o deixa rodando) é suficiente — não é necessário nenhum flag especial
além do fluxo normal `tailscaled` + `tailscale up`.

### 6.5 Estrutura de projeto sugerida (espelhando o webos-wireguard)

```
app/com.<usuario>.tailscale-tv/
  appinfo.json
  index.html / css / js          (UI mínima: status da conexão, IP tailnet, logs)
  payload/tailscale/
    bin/
      tailscale.combined         (ou binários separados por arquitetura)
    scripts/
      start.sh
      stop.sh
      status.sh
      autostart.sh
      boot.sh                    (aguarda rota default, chama tailscaled + tailscale up)
      uninstall.sh
```

Estado persistente (statedir, socket, logs) deve seguir o mesmo padrão de
`/var/lib/webosbrew/<nome-do-app>/`, com os binários/scripts permanecendo dentro do diretório
do app e linkados (não copiados) — decisão que o `webos-wireguard` tomou na v1.0.2
especificamente para simplificar updates.

---

## 7. Autenticação — auth key reutilizável

Login interativo via navegador não é viável em controle remoto de TV. Usar **auth key**
(pré-autenticação), gerada no admin console: https://console.tailscale.com/admin/settings/keys

Pontos confirmados na documentação oficial:

- Auth keys podem ser **one-off** (uso único) ou **reusable** (múltiplos usos) — para este
  caso, uma reusable key é a mais prática, mas o próprio Tailscale alerta que reusable keys são
  sensíveis e devem ser tratadas como segredo (não versionar, não expor no `.ipk` publicado).
- Expira em até 90 dias por padrão — considerar gerar uma key com **tag** (para identificar o
  nó da TV separadamente na tailnet) e, se aplicável ao plano do usuário, marcar como
  **pre-approved** caso a tailnet tenha aprovação de dispositivo habilitada.
- Uso: `tailscale up --auth-key=tskey-xxxxxxxx`.

Fluxo sugerido no `boot.sh`: se ainda não autenticado, rodar `tailscale up --auth-key=<key>`
uma única vez (idempotente — Tailscale detecta se já está autenticado); caso contrário, apenas
garantir que `tailscaled` está rodando (o node key já persiste local, sem precisar da auth key
novamente).

---

## 8. Portas do Sunshine/Moonlight (referência, não bloqueante)

Reforçando o ponto da seção 1: com o túnel Tailscale ativo, nenhuma configuração de porta é
necessária no lado da TV. A lista abaixo serve apenas de referência para validar que **o
firewall do desktop Windows** (Sunshine) não está bloqueando tráfego vindo da interface
Tailscale — esse é um ponto de atenção real e recorrente em relatos de outros usuários
combinando Tailscale + Sunshine/Moonlight (regras de firewall às vezes escopadas só para o
perfil de rede "Privada", enquanto a interface virtual do Tailscale pode cair em outro perfil).

Conjunto de portas documentado oficialmente pelo Sunshine/Moonlight:

| Porta | Protocolo | Função |
|---|---|---|
| 47984 | TCP | HTTPS |
| 47989 | TCP | HTTP |
| 47990 | TCP | Web UI |
| 48010 | TCP | RTSP |
| 47998 | UDP | Vídeo |
| 47999 | UDP | Controle |
| 48000 | UDP | Áudio |
| 48002 | UDP | Mic (se habilitado) |
| 48010 | UDP | RTSP (companion) |

(A contagem exata de portas pode variar levemente por versão do Sunshine — confirmar contra a
própria configuração do usuário se necessário, mas repito: irrelevante para o desenho da
solução Tailscale.)

Ação recomendada: garantir que as regras de firewall do Sunshine no Windows valham para
"qualquer perfil de rede" ou, especificamente, que o perfil atribuído à interface Tailscale
esteja coberto.

---

## 9. Riscos e pontos de atenção conhecidos

- **Persistência de estado entre updates de firmware da LG.** Risco já conhecido em qualquer TV
  rooteada (não específico deste projeto) — updates OTA da LG podem reverter root/Homebrew.
- **Tamanho do binário.** `tailscaled` é sensivelmente maior que `wireguard-go` sozinho (dezenas
  de MB mesmo após strip); validar espaço disponível na partição onde apps Homebrew instalam
  (`/media/developer/apps`) antes de comprometer com UPX ou não.
  Nesse caso o build "extra-small" (seção 5.2) provavelmente é suficiente sem precisar de UPX.
- **Chave de auth key exposta.** Se o projeto for realmente publicado open source, o `.ipk` NÃO
  deve conter a auth key do usuário embutida — replicar o padrão de upload de config do
  `webos-wireguard` (endpoint temporário protegido por código de acesso) ou pedir que o usuário
  insira a key manualmente no primeiro setup, análogo ao fluxo de upload do `wg0.conf`.
- **DNS/MagicDNS.** Não é necessário para este caso de uso (conexão por IP direto do Moonlight),
  mas se o app expuser essa opção no futuro, seguir a mesma ressalva que o `webos-wireguard` fez
  para DNS (não implementado na v1.0.2) — implementar apenas se necessário.

---

## 10. Plano de implementação sugerido (fases)

1. **Validação manual via SSH** (sem empacotar app ainda): compilar `tailscale.combined` para a
   arquitetura correta, copiar para a TV via SSH (Homebrew Channel expõe acesso root via SSH),
   rodar `tailscaled` e `tailscale up --auth-key=...` manualmente, e testar o Moonlight
   apontando pro IP Tailscale do desktop. Isso valida a hipótese central (TUN completo funciona
   com `tailscaled`, não só com `wireguard-go`) antes de investir em UI/empacotamento.
2. **Empacotamento como app Homebrew**, reaproveitando a estrutura do `webos-wireguard`
   (`appinfo.json`, scripts, boot hook simbólico).
3. **UI mínima**: status da conexão, IP Tailscale atual, botão de start/stop, log — sem
   necessidade de feature-parity com a UI completa do `webos-wireguard`.
4. **Documentação e release** (`.ipk` + `repo.json` para listagem no Homebrew, se o usuário
   quiser distribuir via um repositório de terceiros do Homebrew Channel).

---

## 11. Licenciamento

- Código do Tailscale: BSD-3-Clause (https://github.com/tailscale/tailscale — ver `LICENSE`).
- "Tailscale" e "WireGuard" são marcas registradas (Tailscale Inc. e Jason A. Donenfeld,
  respectivamente) — evitar nome de pacote que sugira produto oficial da Tailscale Inc.
  (o `webos-wireguard` resolve isso nomeando o pacote como `com.github.<usuario>.<app>`).
- Sugestão de licença para o código específico do app (empacotamento, scripts, UI): MIT, mesmo
  modelo usado pelo `webos-wireguard`.

---

## 12. Em aberto (confirmar com o usuário antes de iniciar o build)

- Modelo exato da LG TV e saída de `uname -m` (define `arm`/`GOARM=7` vs `arm64`).
- Versão do webOS e ano/geração do TV (referência cruzada de compatibilidade, se necessário).
- Nome de pacote/app desejado (`com.github.<usuario>.<nome>`).
- Confirmar se o usuário quer distribuir publicamente (repo Homebrew de terceiros) ou uso
  estritamente pessoal para efeito de decisões de segurança em torno da auth key (seção 9).
