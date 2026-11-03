# Instalar o launcher e a limpeza em qualquer TV TCL (guia para o Claude)

Este arquivo é para o **Claude Code** executar, de ponta a ponta, num PC Windows na mesma rede Wi-Fi da TV.
Pode ser colado como prompt ou lido pelo agente dentro do repo. Funciona em TCL com **Android TV / Google TV**
(série C, P, S, Q, G). Não serve para TCL com Roku TV nem para as TCL da China que bloqueiam launcher de terceiros
(o cabeçalho da lista do modelo avisa).

Tudo é **reversível**: nada é desinstalado, só desativado com `pm disable-user`.

## Repos

| Repo | Para quê |
|---|---|
| `gustavodvp/cleanyourtv-tcl` | Launcher (estilo tvOS, pt-BR), temas, screensaver e as listas de limpeza em `examples/`. Branch `main`. |
| `gustavodvp/tv-adb` (este) | Scripts PowerShell de apoio: conectar, backup, tocar vídeo, monitorar. |

O launcher é um fork do [Gathin23/cleanyourtv](https://github.com/Gathin23/cleanyourtv) (MIT).

## Pré-requisitos no PC

Instale com `winget` o que faltar:

```powershell
winget install Google.PlatformTools        # adb
winget install EclipseAdoptium.Temurin.21.JDK
winget install Python.Python.3.12
winget install Git.Git
```

Android SDK em `%LOCALAPPDATA%\Android\Sdk` com `platforms;android-34`, `build-tools;34.0.0` e `cmdline-tools`
(via Android Studio ou `sdkmanager`). Defina `JAVA_HOME` apontando para o JDK 21.

```powershell
git clone https://github.com/gustavodvp/cleanyourtv-tcl.git
git clone https://github.com/gustavodvp/tv-adb.git
cd cleanyourtv-tcl
python -m venv tools\venv
tools\venv\Scripts\pip install -r tools\requirements.txt
```

## Passo 1 · Preparar a TV (a pessoa faz no controle)

1. Configurações → Preferências do dispositivo → Sobre → aperte OK **7 vezes** em "Compilação".
2. Voltar → Opções do desenvolvedor → ligar **Depuração USB** (e **Depuração de rede/ADB**, se aparecer).
3. Manter a TV ligada e no mesmo Wi-Fi do PC.

## Passo 2 · Conectar

Descubra o IP em Configurações → Rede, ou pelo roteador. Depois:

```powershell
cd ..\tv-adb
.\connect.ps1 <IP-DA-TV>
```

Peça para a pessoa aceitar "Permitir depuração USB?" na TV (marcar "Sempre permitir"). O script grava o
endereço em `device.txt` e imprime modelo, Android e ABI. **Anote o modelo exato** (`ro.product.model`) e a
arquitetura (`ro.product.cpu.abi`, quase sempre `armeabi-v7a` nas TCL).

> `device.txt` fica fora do git (`.gitignore`). Cada TV tem o seu.

## Passo 3 · Backup antes de mexer

```powershell
.\backup.ps1
```

Gera `backup\<data>\` com pacotes, settings e um `undo.ps1`. Não pule.

## Passo 4 · Escolher a lista de limpeza

Em `cleanyourtv-tcl\examples\` há listas de TCL testadas: `tcl-55c645-google-tv` (a mais completa, QLED 2023 BR),
`tcl-g10-google-tv`, `tcl-g05-google-tv`, `tcl-qm6k-google-tv`, `tcl-q10g-pro`, `tcl-65c725`, `tcl-50ep680`,
`tcl-40s5400a`, `tcl-ak30a5`, `tcl-beyondtv*`.

- Se o modelo estiver lá, copie a pasta mais próxima e renomeie (`examples\tcl-<modelo>\debloat.txt`).
- Se não estiver, pegue `tcl-55c645-google-tv` como base e **confira cada pacote na TV**:

  ```powershell
  adb shell pm list packages | findstr /i "tcl"
  ```

  Remova da lista o que não existir. Pacotes que não existem só dão erro inofensivo, mas a lista fica suja.
- **Mostre a lista final à pessoa e pergunte** antes de aplicar: o que ela usa (Alexa, Chromecast, AirPlay,
  Miracast, assistente de voz, TV aberta interativa).

### Nunca desative (quebra a TV)

`com.tcl.exhibit`, `com.tcl.partnercustomizer` (tecla T e troca de launcher), `com.google.android.videos`,
`com.tcl.tv`, `com.tcl.tvinput` (TV ao vivo e HDMI), `com.google.android.katniss` (microfone do controle),
teclado padrão da TCL, Play Store, Chromecast (`mediashell`), Tailscale se houver.

## Passo 5 · Desativar os pacotes

```powershell
cd ..\cleanyourtv-tcl
powershell -ExecutionPolicy Bypass -File tools\disable.ps1 -TvHost <IP> examples\tcl-<modelo>\debloat.txt
```

## Passo 6 · Tema e dock

Edite `themes\tanjiro\config.json` (ou copie a pasta e renomeie):

- `dock_apps`: pacotes dos apps favoritos, na ordem. Veja os instalados com `adb shell pm list packages -3`.
- `columns`: 5.
- `wallpaper.jpg`: 1920×1080, até ~300 KB, escuro. 4K só gasta memória.
- `screensaver1.jpg`, `screensaver2.jpg`…: mesmas medidas. Cada uma fica 3 min no screensaver.
- Banner de app: `banner-<pacote>.png` na pasta do tema.

Os wallpapers são arte de terceiros; use os seus.

## Passo 7 · Compilar e instalar o launcher

```powershell
powershell -ExecutionPolicy Bypass -File launcher\build-and-install.ps1 -TvHost <IP> -StockLauncher none
```

Se a TV for Google TV, o launcher original é `com.google.android.apps.tv.launcherx`. O script o desativa, e o
`com.google.android.tungsten.setupwraith` também precisa sair da lista de HOME (ele já está na `debloat.txt`
da 55C645). **Sem isso o setupwraith assume a home.**

Depois aplique o tema:

```powershell
powershell -ExecutionPolicy Bypass -File tools\theme.ps1 -TvHost <IP> themes\tanjiro
```

Aperte Home no controle. Se cair no launcher, ok.

## Passo 8 · Verificar

```powershell
adb exec-out screencap -p > tela.png      # Netflix/DRM sai preto; é normal
adb shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME
```

A segunda deve mostrar `com.gathin.tvhome.MainActivity`. Teste TV ao vivo, um HDMI, Netflix e o botão de
microfone. Se algum falhar, reative o pacote (veja Desfazer).

## Desfazer

```powershell
# tudo (pacotes + home do Google TV)
powershell -ExecutionPolicy Bypass -File tools\restore.ps1 -TvHost <IP> examples\tcl-<modelo>\debloat.txt -Stock com.google.android.apps.tv.launcherx

# emergência (TV sem home ou caindo do Wi-Fi)
adb shell pm enable --user 0 com.google.android.apps.tv.launcherx
adb shell pm enable --user 0 com.google.android.tungsten.setupwraith
```

**Antes de um reset de fábrica, sempre rode o "tudo"**: ele reativa o assistente de configuração.

## Armadilhas conhecidas

- **Nunca mande `KEYCODE_SLEEP` por ADB.** A TV sai da rede e só o controle físico a acorda.
- `tools\b64push.py` precisa de blocos múltiplos de 3 bytes (`chunk -= chunk % 3`); o `base64 -d` da TV para no
  primeiro `=`. A correção já está neste fork. Confira depois de qualquer rebase do upstream.
- O launcher segue o idioma da TV. `launcher\app\src\main\res\values-pt\strings.xml` traz o pt-BR.
- Menu de imagem da TCL não expõe estado dos interruptores no `uiautomator`: tire screenshot antes do OK.
- Valores de imagem ficam no banco TVOS da TCL, que o ADB não escreve sem root: só pelo menu do controle.
- Wi-Fi da TV cai ~1 s a cada poucos minutos; cabo de rede resolve se for usar Moonlight.
- Algumas TCL cortam a energia da USB com depuração ligada.
- Não desative o Tailscale nem o `com.pandora.tv` se for uma TV da casa do Gustavo.

## Opcional

- **YouTube sem anúncios**: o ReVanced não serve para TV. Use SmartTube (`yuliskov/SmartTube`, release oficial).
  Confira o SHA-256 do release e o certificado `109735aa24fe85e2e1623ebb3b1ecc4bf4263f4c6374e4411d646bfa2eda482a`
  (`apksigner verify --print-certs`). Versões 30.43/30.47/30.51 traziam `libalphasdk.so` malicioso.
- **Tocar vídeo por link ou título**: `.\play-youtube.ps1 "https://youtu.be/<id>"`.
- **Browser**: `.\install-tvbro.ps1` (TV Bro).
- **DNS sem anúncios**: `adb shell settings put global private_dns_mode hostname` e
  `adb shell settings put global private_dns_specifier dns.adguard-dns.com`.
- **Animações mais rápidas**: `window_animation_scale`, `transition_animation_scale` e `animator_duration_scale` = 0.5.

## Checklist de entrega

- [ ] Backup feito e `undo.ps1` guardado
- [ ] Lista de limpeza revisada pela pessoa
- [ ] Home abre o `com.gathin.tvhome`
- [ ] TV ao vivo, HDMI, Netflix e microfone testados
- [ ] Pessoa sabe o "Desfazer"
