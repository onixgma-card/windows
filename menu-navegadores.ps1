<#
    menu-navegadores.ps1
    ---------------------------------------------------------
    Interface grafica simples (Windows Forms) com um menu
    vertical fixado a esquerda. O menu contem o botao
    "Navegadores", que ao ser clicado exibe, na area de
    conteudo (direita), botoes para abrir os navegadores
    instalados na maquina (Chrome, Edge, Firefox, Brave, Opera).

    Uso:
      - Local:
          powershell -ExecutionPolicy Bypass -File .\menu-navegadores.ps1

      - Direto da URL "raw" do GitHub (sem salvar o arquivo):
          iex (irm "https://raw.githubusercontent.com/usuario/repo/branch/menu-navegadores.ps1")

        ou, em uma linha, via PowerShell:
          powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (irm 'https://raw.githubusercontent.com/usuario/repo/branch/menu-navegadores.ps1')"
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ------------------------------------------------------------------
# Configuracao de cores (tema escuro simples)
# ------------------------------------------------------------------
$corFundoMenu     = [System.Drawing.Color]::FromArgb(30, 30, 30)
$corFundoConteudo = [System.Drawing.Color]::FromArgb(245, 245, 245)
$corBotaoMenu     = [System.Drawing.Color]::FromArgb(45, 45, 45)
$corBotaoMenuHover= [System.Drawing.Color]::FromArgb(0, 120, 215)
$corTextoMenu     = [System.Drawing.Color]::White

# ------------------------------------------------------------------
# Lista de navegadores conhecidos: nome exibido, caminhos possiveis
# ------------------------------------------------------------------
$navegadores = @(
    @{ Nome = "Google Chrome"; Caminhos = @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
        ) },
    @{ Nome = "Microsoft Edge"; Caminhos = @(
            "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
            "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
        ) },
    @{ Nome = "Mozilla Firefox"; Caminhos = @(
            "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
            "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
        ) },
    @{ Nome = "Brave"; Caminhos = @(
            "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
            "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
            "$env:LocalAppData\BraveSoftware\Brave-Browser\Application\brave.exe"
        ) },
    @{ Nome = "Opera"; Caminhos = @(
            "$env:LocalAppData\Programs\Opera\opera.exe",
            "$env:ProgramFiles\Opera\opera.exe"
        ) }
)

function Get-NavegadoresInstalados {
    $encontrados = @()
    foreach ($nav in $navegadores) {
        foreach ($caminho in $nav.Caminhos) {
            if ($caminho -and (Test-Path $caminho)) {
                $encontrados += [PSCustomObject]@{
                    Nome    = $nav.Nome
                    Caminho = $caminho
                }
                break
            }
        }
    }
    return $encontrados
}

# ------------------------------------------------------------------
# Obtem o icone OFICIAL do Firefox. Ordem de preferencia:
#   1) Extrai do proprio executavel instalado na maquina (igual ao que o
#      Explorer do Windows faz) - nao depende de internet.
#   2) Se o Firefox ainda nao estiver instalado, baixa o icone oficial
#      direto do repositorio publico da propria Mozilla no GitHub
#      (mozilla/gecko-dev) - o mesmo codigo-fonte de onde o Firefox e
#      compilado - em vez de usarmos uma copia nossa. Fica em cache na
#      memoria pra nao baixar de novo toda vez que a tela for reaberta.
#   3) Se nao houver instalacao local nem internet disponivel, usa um
#      icone de reserva desenhado, so para o espaco nao ficar vazio.
# ------------------------------------------------------------------
function Get-FirefoxExePath {
    $candidatos = @(
        "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
    )
    foreach ($c in $candidatos) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

# Redimensiona uma imagem/icone de origem para um bitmap quadrado de
# $Tamanho pixels, com boa qualidade (usado tanto para o icone extraido
# do executavel local quanto para o baixado da internet).
function Resize-ImagemParaIcone {
    param($Origem, [int]$Tamanho)

    $bmpFinal = New-Object System.Drawing.Bitmap($Tamanho, $Tamanho)
    $g = [System.Drawing.Graphics]::FromImage($bmpFinal)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($Origem, 0, 0, $Tamanho, $Tamanho)
    $g.Dispose()
    $Origem.Dispose()
    return $bmpFinal
}

# ------------------------------------------------------------------
# Deixa os cantos de um botao arredondados, recortando sua area
# (Region) no formato de um retangulo com cantos em curva. O Windows
# Forms nao tem uma propriedade pronta para "border-radius", entao a
# forma e desenhada manualmente com um GraphicsPath.
# ------------------------------------------------------------------
function Set-BotaoCantosArredondados {
    param(
        [System.Windows.Forms.Button]$Botao,
        [int]$Raio = 8
    )

    $largura = $Botao.Width
    $altura  = $Botao.Height
    $diametro = $Raio * 2

    $caminho = New-Object System.Drawing.Drawing2D.GraphicsPath
    $caminho.AddArc(0, 0, $diametro, $diametro, 180, 90)
    $caminho.AddArc($largura - $diametro, 0, $diametro, $diametro, 270, 90)
    $caminho.AddArc($largura - $diametro, $altura - $diametro, $diametro, $diametro, 0, 90)
    $caminho.AddArc(0, $altura - $diametro, $diametro, $diametro, 90, 90)
    $caminho.CloseFigure()

    $Botao.Region = New-Object System.Drawing.Region($caminho)
}

# ------------------------------------------------------------------
# Extrai o icone OFICIAL de qualquer navegador direto do proprio
# executavel instalado (Chrome, Edge, Firefox, Brave, Opera - todos
# gravam o icone real do programa dentro do .exe). Mesma logica usada
# para o Firefox, generalizada para qualquer caminho de executavel.
# Fica em cache por caminho, para nao reextrair o mesmo icone toda
# vez que a tela de navegadores for reaberta.
# ------------------------------------------------------------------
if (-not $script:cacheIconesExecutaveis) {
    $script:cacheIconesExecutaveis = @{}
}

function Get-IconeExecutavel {
    param([string]$CaminhoExe, [int]$Tamanho = 28)

    if (-not $CaminhoExe -or -not (Test-Path -LiteralPath $CaminhoExe)) {
        return $null
    }

    $chaveCache = "$CaminhoExe|$Tamanho"
    if ($script:cacheIconesExecutaveis.ContainsKey($chaveCache)) {
        return $script:cacheIconesExecutaveis[$chaveCache]
    }

    try {
        $icone = [System.Drawing.Icon]::ExtractAssociatedIcon($CaminhoExe)
        if ($icone) {
            $bmpFinal = Resize-ImagemParaIcone -Origem $icone.ToBitmap() -Tamanho $Tamanho
            $icone.Dispose()
            $script:cacheIconesExecutaveis[$chaveCache] = $bmpFinal
            return $bmpFinal
        }
    } catch {
        # Se a extracao falhar (arquivo sem icone, permissao, etc.), o
        # botao do navegador simplesmente fica sem imagem - nao e critico.
    }

    return $null
}


function Get-FirefoxLogoBitmap {
    param([int]$Tamanho = 72)

    # 1) Firefox ja instalado: usa o icone real do executavel local.
    $caminhoFirefox = Get-FirefoxExePath
    if ($caminhoFirefox) {
        try {
            $icone = [System.Drawing.Icon]::ExtractAssociatedIcon($caminhoFirefox)
            if ($icone) {
                $bmpFinal = Resize-ImagemParaIcone -Origem $icone.ToBitmap() -Tamanho $Tamanho
                $icone.Dispose()
                return $bmpFinal
            }
        } catch {
            # Se por algum motivo a extracao falhar, segue tentando as
            # opcoes abaixo.
        }
    }

    # 2) Firefox ainda nao instalado: busca o icone oficial na internet,
    #    direto do repositorio oficial da Mozilla. So tenta baixar uma vez
    #    por execucao do programa (cache em $script:).
    if (-not $script:iconeFirefoxOnlineCache) {
        try {
            # Necessario em Windows/PowerShell mais antigos, que por padrao
            # nao habilitam TLS 1.2 e derrubam a conexao HTTPS com o GitHub.
            try {
                [System.Net.ServicePointManager]::SecurityProtocol = `
                    [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
            } catch { }

            $urlLogoOficial = "https://raw.githubusercontent.com/mozilla/gecko-dev/master/browser/branding/official/firefox.ico"
            $bytesIcone = (Invoke-WebRequest -Uri $urlLogoOficial -UseBasicParsing -TimeoutSec 6).Content
            $ms = New-Object System.IO.MemoryStream(, $bytesIcone)
            # Pede explicitamente a maior resolucao disponivel dentro do
            # .ico (ele tem varios tamanhos embutidos) para nao ficar
            # borrado ao redimensionar.
            $script:iconeFirefoxOnlineCache = New-Object System.Drawing.Icon($ms, 256, 256)
            $ms.Dispose()
        } catch {
            # Sem internet, GitHub bloqueado, timeout, etc. - fica $null e
            # cai no icone de reserva desenhado la embaixo.
            $script:iconeFirefoxOnlineCache = $null
        }
    }

    if ($script:iconeFirefoxOnlineCache) {
        return Resize-ImagemParaIcone -Origem $script:iconeFirefoxOnlineCache.ToBitmap() -Tamanho $Tamanho
    }

    # 3) Sem instalacao local e sem internet: icone de reserva desenhado.
    return New-FirefoxLogoBitmap -Tamanho $Tamanho
}

# ------------------------------------------------------------------
# Icone de reserva, desenhado em tempo de execucao (usado apenas
# quando o Firefox ainda nao esta instalado nesta maquina e por isso
# nao existe um firefox.exe de onde extrair o icone oficial).
# ------------------------------------------------------------------
function New-FirefoxLogoBitmap {
    param([int]$Tamanho = 72)

    $bmp = New-Object System.Drawing.Bitmap($Tamanho, $Tamanho)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $laranja       = [System.Drawing.Color]::FromArgb(255, 149, 0)
    $laranjaEscuro = [System.Drawing.Color]::FromArgb(214, 82, 0)

    $pincelFundo = New-Object System.Drawing.SolidBrush($laranja)
    $g.FillEllipse($pincelFundo, 2, 2, $Tamanho - 4, $Tamanho - 4)

    $pincelDetalhe = New-Object System.Drawing.SolidBrush($laranjaEscuro)
    $g.FillEllipse($pincelDetalhe, $Tamanho * 0.22, $Tamanho * 0.12, $Tamanho * 0.56, $Tamanho * 0.56)

    $fonte = New-Object System.Drawing.Font("Segoe UI", [Math]::Round($Tamanho / 3.4), [System.Drawing.FontStyle]::Bold)
    $pincelTexto = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $formato = New-Object System.Drawing.StringFormat
    $formato.Alignment = "Center"
    $formato.LineAlignment = "Center"
    $retangulo = New-Object System.Drawing.RectangleF(0, 0, $Tamanho, $Tamanho)
    $g.DrawString("Fx", $fonte, $pincelTexto, $retangulo, $formato)

    $g.Dispose()
    return $bmp
}

# Referencia (scriptblock) para Get-FirefoxLogoBitmap, guardada numa
# variavel de escopo de script. Isso e necessario porque .GetNewClosure()
# - usado mais abaixo para os cliques e o timer de instalacao - isola o
# bloco de codigo num escopo que NAO enxerga funcoes ("function ...")
# definidas no script, soh variaveis capturadas no momento da chamada.
# Guardando a funcao numa variavel, conseguimos chama-la de dentro
# desses blocos com "& $variavel".
$script:refLogoFirefoxOficial = ${function:Get-FirefoxLogoBitmap}

# ------------------------------------------------------------------
# Procura, no registro do Windows, a entrada de desinstalacao do
# Firefox (32 ou 64 bits, usuario atual ou maquina toda)
# ------------------------------------------------------------------
function Get-FirefoxUninstallInfo {
    $caminhosRegistro = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($caminho in $caminhosRegistro) {
        $itens = Get-ItemProperty -Path $caminho -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "Mozilla Firefox*" }
        if ($itens) {
            return $itens | Select-Object -First 1
        }
    }
    return $null
}

# ------------------------------------------------------------------
# Mesma logica do Firefox, agora para o Google Chrome: caminho do
# executavel local, entrada de desinstalacao no registro e icone
# oficial (extraido do exe instalado ou, se ainda nao instalado,
# baixado do cdnjs - espelho publico do repositorio "browser-logos",
# que hospeda os logos oficiais dos navegadores mais usados).
# ------------------------------------------------------------------
function Get-ChromeExePath {
    $candidatos = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )
    foreach ($c in $candidatos) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Get-ChromeUninstallInfo {
    $caminhosRegistro = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($caminho in $caminhosRegistro) {
        $itens = Get-ItemProperty -Path $caminho -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "Google Chrome*" }
        if ($itens) {
            return $itens | Select-Object -First 1
        }
    }
    return $null
}

# Icone de reserva desenhado (usado apenas se o Chrome nao estiver
# instalado e nao houver internet para baixar o icone oficial).
function New-ChromeLogoBitmap {
    param([int]$Tamanho = 72)

    $bmp = New-Object System.Drawing.Bitmap($Tamanho, $Tamanho)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $vermelho = [System.Drawing.Color]::FromArgb(234, 67, 53)
    $amarelo  = [System.Drawing.Color]::FromArgb(251, 188, 5)
    $verde    = [System.Drawing.Color]::FromArgb(52, 168, 83)
    $azul     = [System.Drawing.Color]::FromArgb(66, 133, 244)
    $branco   = [System.Drawing.Color]::White

    $x = 2
    $tam = $Tamanho - 4

    $g.FillPie((New-Object System.Drawing.SolidBrush($vermelho)), $x, $x, $tam, $tam, -90, 120)
    $g.FillPie((New-Object System.Drawing.SolidBrush($verde)), $x, $x, $tam, $tam, 30, 120)
    $g.FillPie((New-Object System.Drawing.SolidBrush($amarelo)), $x, $x, $tam, $tam, 150, 120)

    $miolo = $Tamanho * 0.36
    $offMiolo = ($Tamanho - $miolo) / 2
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($branco)), $offMiolo, $offMiolo, $miolo, $miolo)

    $centro = $Tamanho * 0.22
    $offCentro = ($Tamanho - $centro) / 2
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($azul)), $offCentro, $offCentro, $centro, $centro)

    $g.Dispose()
    return $bmp
}

function Get-ChromeLogoBitmap {
    param([int]$Tamanho = 72)

    # 1) Chrome ja instalado: usa o icone real do executavel local.
    $caminhoChrome = Get-ChromeExePath
    if ($caminhoChrome) {
        try {
            $icone = [System.Drawing.Icon]::ExtractAssociatedIcon($caminhoChrome)
            if ($icone) {
                $bmpFinal = Resize-ImagemParaIcone -Origem $icone.ToBitmap() -Tamanho $Tamanho
                $icone.Dispose()
                return $bmpFinal
            }
        } catch {
            # Segue tentando as opcoes abaixo.
        }
    }

    # 2) Chrome ainda nao instalado: baixa o icone oficial (PNG) do
    #    cdnjs, cache em memoria para nao baixar de novo.
    if (-not $script:iconeChromeOnlineCache) {
        try {
            try {
                [System.Net.ServicePointManager]::SecurityProtocol = `
                    [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
            } catch { }

            $urlLogoOficial = "https://cdnjs.cloudflare.com/ajax/libs/browser-logos/35.0.1/chrome/chrome_256x256.png"
            $bytesImagem = (Invoke-WebRequest -Uri $urlLogoOficial -UseBasicParsing -TimeoutSec 6).Content
            $ms = New-Object System.IO.MemoryStream(, $bytesImagem)
            $script:iconeChromeOnlineCache = [System.Drawing.Image]::FromStream($ms)
        } catch {
            $script:iconeChromeOnlineCache = $null
        }
    }

    if ($script:iconeChromeOnlineCache) {
        return Resize-ImagemParaIcone -Origem ($script:iconeChromeOnlineCache.Clone()) -Tamanho $Tamanho
    }

    # 3) Sem instalacao local e sem internet: icone de reserva desenhado.
    return New-ChromeLogoBitmap -Tamanho $Tamanho
}

$script:refLogoChromeOficial = ${function:Get-ChromeLogoBitmap}

function Get-BraveExePath {
    $candidatos = @(
        "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
        "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
        "$env:LocalAppData\BraveSoftware\Brave-Browser\Application\brave.exe"
    )
    foreach ($c in $candidatos) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Get-BraveUninstallInfo {
    $caminhosRegistro = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($caminho in $caminhosRegistro) {
        $itens = Get-ItemProperty -Path $caminho -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "Brave*" }
        if ($itens) {
            return $itens | Select-Object -First 1
        }
    }
    return $null
}

# ------------------------------------------------------------------
# Traduz os codigos de saida mais comuns do winget para uma mensagem
# legivel. O winget devolve HRESULTs (as vezes como numero enorme
# negativo, as vezes em hexadecimal) que nao dizem nada sozinhos -
# aqui cobrimos os casos que mais aparecem ao instalar/desinstalar
# o Brave silenciosamente.
# ------------------------------------------------------------------
function Get-DescricaoErroWinget {
    param([int]$CodigoSaida)

    # Normaliza para o formato hex de 8 digitos que a documentacao do
    # winget usa, para comparar com a tabela abaixo independente de o
    # .NET ter devolvido o numero como negativo ou como UInt32.
    #
    # IMPORTANTE: nao da para converter direto com [uint32]$CodigoSaida
    # quando o numero e negativo - o PowerShell tenta converter pelo
    # VALOR (ex: -1978335184 nao cabe em UInt32) e estoura com
    # "InvalidCastIConvertible". O que precisamos e REINTERPRETAR os
    # mesmos 32 bits como um numero sem sinal, entao usamos uma
    # mascara de bits (-band) num inteiro de 64 bits antes de converter
    # para UInt32, o que sempre cabe (0 a 4294967295).
    $hex = "0x{0:X8}" -f [uint32]([int64]$CodigoSaida -band 0xFFFFFFFFL)

    # ----------------------------------------------------------
    # Tabela de codigos de erro do winget (App Installer), traduzida
    # e organizada a partir da lista oficial da Microsoft:
    # https://learn.microsoft.com/pt-br/windows/package-manager/winget/returnCodes
    #
    # A tabela anterior tinha alguns codigos mapeados incorretamente
    # (ex: 0x8A150056 nao significa "ja instalado" - isso e o
    # 0x8A150061) e um codigo duplicado (0x8A150109 aparecia duas
    # vezes com descricoes diferentes; a segunda nunca era alcancada
    # pelo switch). Foi corrigido e ampliado abaixo.
    # ----------------------------------------------------------
    switch ($hex) {
        # --- Erros gerais ---
        "0x8A150001" { return "Erro interno do winget." }
        "0x8A150002" { return "Argumentos de linha de comando invalidos." }
        "0x8A150003" { return "Falha ao executar o comando." }
        "0x8A150004" { return "Falha ao abrir o manifesto do pacote." }
        "0x8A150005" { return "Sinal de cancelamento recebido (operacao interrompida pelo usuario ou pelo sistema)." }
        "0x8A150006" { return "Falha ao executar o instalador (ShellExecute)." }
        "0x8A150008" { return "Falha ao baixar o instalador. Verifique a conexao com a internet." }
        "0x8A15000F" { return "Faltam dados necessarios na fonte do winget. Tente rodar 'winget source update' e de novo." }
        "0x8A150010" { return "Nenhum instalador aplicavel foi encontrado para esta arquitetura/versao do Windows." }
        "0x8A150011" { return "O hash do arquivo do instalador nao confere com o manifesto (download corrompido, incompleto ou bloqueado por antivirus/proxy)." }
        "0x8A150012" { return "A fonte do winget informada nao existe." }
        "0x8A150014" { return "Nenhum pacote encontrado com esse identificador." }
        "0x8A150015" { return "Nenhuma fonte do winget esta configurada nesta maquina." }
        "0x8A150016" { return "Mais de um pacote encontrado com esse identificador (identificador ambiguo)." }
        "0x8A150017" { return "Nenhum manifesto encontrado para este pacote." }
        "0x8A150019" { return "Este comando exige privilegios de administrador." }
        "0x8A15001B" { return "A Microsoft Store esta bloqueada por politica do sistema/organizacao." }
        "0x8A150029" { return "A validacao do manifesto do pacote falhou." }
        "0x8A15002B" { return "Nao ha atualizacao aplicavel para este pacote (ja esta na versao mais recente, ou nao foi instalado pela fonte winget)." }
        "0x8A15002D" { return "O instalador falhou na verificacao de seguranca do winget." }
        "0x8A15002E" { return "O tamanho do arquivo baixado nao confere com o esperado. Tente baixar novamente." }
        "0x8A15002F" { return "Nao foi encontrado um comando de desinstalacao para este pacote (ele pode nao ter sido instalado pelo winget, ou ja foi removido parcialmente)." }
        "0x8A150030" { return "A execucao do comando de desinstalacao falhou. As causas mais comuns sao: o programa ainda esta aberto/em uso, o desinstalador exige privilegios de administrador, ou os arquivos/registro de desinstalacao ja foram removidos parcialmente antes. Feche o programa, execute como administrador e tente novamente." }
        "0x8A150049" { return "A instalacao via MSI falhou." }
        "0x8A150056" { return "O instalador nao pode ser executado em um contexto de administrador (precisa rodar como usuario comum)." }
        "0x8A150061" { return "Ja existe pelo menos uma versao deste pacote instalada nesta maquina." }
        "0x8A150065" { return "Um ou mais aplicativos falharam ao instalar." }
        "0x8A150066" { return "Um ou mais aplicativos falharam ao desinstalar." }
        # --- Erros durante a instalacao (instalador em si, nao o winget) ---
        "0x8A150101" { return "O aplicativo esta em execucao. Feche-o e tente novamente." }
        "0x8A150102" { return "Outra instalacao ja esta em andamento. Tente novamente em instantes." }
        "0x8A150103" { return "Um ou mais arquivos estao em uso. Feche o aplicativo e tente novamente." }
        "0x8A150104" { return "Este pacote tem uma dependencia faltando no sistema." }
        "0x8A150105" { return "Nao ha espaco suficiente em disco. Libere espaco e tente novamente." }
        "0x8A150106" { return "Memoria insuficiente para instalar. Feche outros programas e tente novamente." }
        "0x8A150107" { return "Este aplicativo exige conexao com a internet." }
        "0x8A150109" { return "E preciso reiniciar o computador para concluir a instalacao." }
        "0x8A15010C" { return "A instalacao foi cancelada pelo usuario." }
        "0x8A15010D" { return "Outra versao deste aplicativo ja esta instalada." }
        "0x8A15010F" { return "Politicas da organizacao estao impedindo a instalacao. Contate o administrador do sistema." }
        default {
            if ($CodigoSaida -eq 19) { return "Reinicio pendente para concluir a operacao (tratado como sucesso)." }
            return "Codigo nao mapeado ($hex). Veja a saida detalhada do winget abaixo, se disponivel."
        }
    }
}

# Icone de reserva desenhado (usado apenas se o Brave nao estiver
# instalado e nao houver internet para baixar o icone oficial).
function New-BraveLogoBitmap {
    param([int]$Tamanho = 72)

    $bmp = New-Object System.Drawing.Bitmap($Tamanho, $Tamanho)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $laranja = [System.Drawing.Color]::FromArgb(251, 84, 43)
    $branco  = [System.Drawing.Color]::White

    $pontos = @(
        (New-Object System.Drawing.PointF(($Tamanho * 0.5), ($Tamanho * 0.04))),
        (New-Object System.Drawing.PointF(($Tamanho * 0.92), ($Tamanho * 0.22))),
        (New-Object System.Drawing.PointF(($Tamanho * 0.84), ($Tamanho * 0.66))),
        (New-Object System.Drawing.PointF(($Tamanho * 0.5),  ($Tamanho * 0.96))),
        (New-Object System.Drawing.PointF(($Tamanho * 0.16), ($Tamanho * 0.66))),
        (New-Object System.Drawing.PointF(($Tamanho * 0.08), ($Tamanho * 0.22)))
    )
    $g.FillPolygon((New-Object System.Drawing.SolidBrush($laranja)), $pontos)

    $miolo = $Tamanho * 0.34
    $offMiolo = ($Tamanho - $miolo) / 2
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($branco)), $offMiolo, $offMiolo, $miolo, $miolo)

    $g.Dispose()
    return $bmp
}

function Get-BraveLogoBitmap {
    param([int]$Tamanho = 72)

    # 1) Brave ja instalado: usa o icone real do executavel local.
    $caminhoBrave = Get-BraveExePath
    if ($caminhoBrave) {
        try {
            $icone = [System.Drawing.Icon]::ExtractAssociatedIcon($caminhoBrave)
            if ($icone) {
                $bmpFinal = Resize-ImagemParaIcone -Origem $icone.ToBitmap() -Tamanho $Tamanho
                $icone.Dispose()
                return $bmpFinal
            }
        } catch {
            # Segue tentando as opcoes abaixo.
        }
    }

    # 2) Brave ainda nao instalado: baixa o icone oficial (PNG) do
    #    cdnjs, cache em memoria para nao baixar de novo.
    if (-not $script:iconeBraveOnlineCache) {
        try {
            try {
                [System.Net.ServicePointManager]::SecurityProtocol = `
                    [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
            } catch { }

            $urlLogoOficial = "https://cdnjs.cloudflare.com/ajax/libs/browser-logos/58.1.0/brave/brave_256x256.png"
            $bytesImagem = (Invoke-WebRequest -Uri $urlLogoOficial -UseBasicParsing -TimeoutSec 6).Content
            $ms = New-Object System.IO.MemoryStream(, $bytesImagem)
            $script:iconeBraveOnlineCache = [System.Drawing.Image]::FromStream($ms)
        } catch {
            $script:iconeBraveOnlineCache = $null
        }
    }

    if ($script:iconeBraveOnlineCache) {
        return Resize-ImagemParaIcone -Origem ($script:iconeBraveOnlineCache.Clone()) -Tamanho $Tamanho
    }

    # 3) Sem instalacao local e sem internet: icone de reserva desenhado.
    return New-BraveLogoBitmap -Tamanho $Tamanho
}

$script:refLogoBraveOficial = ${function:Get-BraveLogoBitmap}

# ------------------------------------------------------------------
# Java (Oracle JRE): mesmo padrao de icone usado para os navegadores.
# 1) Se ja estiver instalado, extrai o icone real do proprio javaw.exe
#    (fica identico ao que o Explorer do Windows mostra).
# 2) Se ainda nao estiver instalado, usa um icone de reserva desenhado
#    (uma xicara simples) - evitamos baixar a arte oficial da Oracle
#    da internet por causa das restricoes de uso da marca Java.
# ------------------------------------------------------------------
function Get-JavaExePath {
    $candidatos = @(
        "$env:ProgramFiles\Java\*\bin\javaw.exe",
        "${env:ProgramFiles(x86)}\Java\*\bin\javaw.exe",
        "$env:ProgramFiles\Common Files\Oracle\Java\javapath\javaw.exe"
    )
    foreach ($padrao in $candidatos) {
        if (-not $padrao) { continue }
        $achado = Get-ChildItem -Path $padrao -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($achado) { return $achado.FullName }
    }
    $cmd = Get-Command javaw.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function New-JavaLogoBitmap {
    param([int]$Tamanho = 72)

    $bmp = New-Object System.Drawing.Bitmap($Tamanho, $Tamanho)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $marromXicara = [System.Drawing.Color]::FromArgb(120, 76, 40)
    $vaporCinza   = [System.Drawing.Color]::FromArgb(160, 160, 160)

    # Corpo da xicara
    $corpo = New-Object System.Drawing.RectangleF(($Tamanho * 0.18), ($Tamanho * 0.40), ($Tamanho * 0.5), ($Tamanho * 0.42))
    $g.FillRectangle((New-Object System.Drawing.SolidBrush($marromXicara)), $corpo)

    # Alca da xicara
    $alca = New-Object System.Drawing.RectangleF(($Tamanho * 0.66), ($Tamanho * 0.46), ($Tamanho * 0.22), ($Tamanho * 0.28))
    $g.DrawArc((New-Object System.Drawing.Pen($marromXicara, ($Tamanho * 0.07))), $alca, -90, 180)

    # Vapor (duas curvas simples)
    $penVapor = New-Object System.Drawing.Pen($vaporCinza, ($Tamanho * 0.045))
    $g.DrawBezier($penVapor, ($Tamanho * 0.28), ($Tamanho * 0.34), ($Tamanho * 0.20), ($Tamanho * 0.22), ($Tamanho * 0.36), ($Tamanho * 0.14), ($Tamanho * 0.30), ($Tamanho * 0.02))
    $g.DrawBezier($penVapor, ($Tamanho * 0.46), ($Tamanho * 0.34), ($Tamanho * 0.38), ($Tamanho * 0.22), ($Tamanho * 0.54), ($Tamanho * 0.14), ($Tamanho * 0.48), ($Tamanho * 0.02))

    $g.Dispose()
    return $bmp
}

function Get-JavaLogoBitmap {
    param([int]$Tamanho = 28)

    $caminhoJava = Get-JavaExePath
    if ($caminhoJava) {
        try {
            $icone = [System.Drawing.Icon]::ExtractAssociatedIcon($caminhoJava)
            if ($icone) {
                $bmpFinal = Resize-ImagemParaIcone -Origem $icone.ToBitmap() -Tamanho $Tamanho
                $icone.Dispose()
                return $bmpFinal
            }
        } catch {
            # Segue para o icone de reserva.
        }
    }

    return New-JavaLogoBitmap -Tamanho $Tamanho
}

$script:refLogoJavaOficial = ${function:Get-JavaLogoBitmap}

# ------------------------------------------------------------------
# WinRAR: mesma logica ja usada para o Java (icone extraido do proprio
# executavel instalado ou, se ainda nao instalado, um icone de reserva
# desenhado - evitamos baixar a arte oficial da RARLab da internet por
# causa das restricoes de uso da marca).
# ------------------------------------------------------------------
function Get-WinRARExePath {
    $candidatos = @(
        "$env:ProgramFiles\WinRAR\WinRAR.exe",
        "${env:ProgramFiles(x86)}\WinRAR\WinRAR.exe"
    )
    foreach ($c in $candidatos) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Get-WinRARUninstallInfo {
    $caminhosRegistro = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($caminho in $caminhosRegistro) {
        $itens = Get-ItemProperty -Path $caminho -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "WinRAR*" }
        if ($itens) {
            return $itens | Select-Object -First 1
        }
    }
    return $null
}

# Icone de reserva desenhado (usado apenas se o WinRAR ainda nao
# estiver instalado nesta maquina): uma "pasta" vermelha com a faixa
# escura e o texto "RAR", lembrando o visual do icone oficial sem
# reproduzi-lo.
function New-WinRARLogoBitmap {
    param([int]$Tamanho = 72)

    $bmp = New-Object System.Drawing.Bitmap($Tamanho, $Tamanho)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $vermelhoWinRAR = [System.Drawing.Color]::FromArgb(196, 30, 30)
    $vermelhoEscuro = [System.Drawing.Color]::FromArgb(140, 18, 18)
    $branco         = [System.Drawing.Color]::White

    $retanguloFundo = New-Object System.Drawing.Rectangle(2, 2, ($Tamanho - 4), ($Tamanho - 4))
    $raio = $Tamanho * 0.18
    $diametro = $raio * 2

    $caminhoFundo = New-Object System.Drawing.Drawing2D.GraphicsPath
    $caminhoFundo.AddArc($retanguloFundo.X, $retanguloFundo.Y, $diametro, $diametro, 180, 90)
    $caminhoFundo.AddArc(($retanguloFundo.Right - $diametro), $retanguloFundo.Y, $diametro, $diametro, 270, 90)
    $caminhoFundo.AddArc(($retanguloFundo.Right - $diametro), ($retanguloFundo.Bottom - $diametro), $diametro, $diametro, 0, 90)
    $caminhoFundo.AddArc($retanguloFundo.X, ($retanguloFundo.Bottom - $diametro), $diametro, $diametro, 90, 90)
    $caminhoFundo.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush($vermelhoWinRAR)), $caminhoFundo)

    $faixa = New-Object System.Drawing.RectangleF(0, ($Tamanho * 0.38), $Tamanho, ($Tamanho * 0.22))
    $g.FillRectangle((New-Object System.Drawing.SolidBrush($vermelhoEscuro)), $faixa)

    $fonte = New-Object System.Drawing.Font("Segoe UI", [Math]::Round($Tamanho / 4.6), [System.Drawing.FontStyle]::Bold)
    $pincelTexto = New-Object System.Drawing.SolidBrush($branco)
    $formato = New-Object System.Drawing.StringFormat
    $formato.Alignment = "Center"
    $formato.LineAlignment = "Center"
    $retangulo = New-Object System.Drawing.RectangleF(0, 0, $Tamanho, $Tamanho)
    $g.DrawString("RAR", $fonte, $pincelTexto, $retangulo, $formato)

    $g.Dispose()
    return $bmp
}

function Get-WinRARLogoBitmap {
    param([int]$Tamanho = 28)

    $caminhoWinRAR = Get-WinRARExePath
    if ($caminhoWinRAR) {
        try {
            $icone = [System.Drawing.Icon]::ExtractAssociatedIcon($caminhoWinRAR)
            if ($icone) {
                $bmpFinal = Resize-ImagemParaIcone -Origem $icone.ToBitmap() -Tamanho $Tamanho
                $icone.Dispose()
                return $bmpFinal
            }
        } catch {
            # Segue para o icone de reserva.
        }
    }

    return New-WinRARLogoBitmap -Tamanho $Tamanho
}

$script:refLogoWinRAROficial = ${function:Get-WinRARLogoBitmap}

# ------------------------------------------------------------------
# Formulario principal
# ------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Onix Consulting"
$form.Size = New-Object System.Drawing.Size(900, 450)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(800, 400)
$form.BackColor = $corFundoConteudo

# Painel do menu (esquerda)
$painelMenu = New-Object System.Windows.Forms.Panel
$painelMenu.Dock = "Left"
$painelMenu.Width = 200
$painelMenu.BackColor = $corFundoMenu

# Painel de conteudo (direita)
$painelConteudo = New-Object System.Windows.Forms.Panel
$painelConteudo.Dock = "Fill"
$painelConteudo.BackColor = $corFundoConteudo
$painelConteudo.AutoScroll = $true
$painelConteudo.Padding = New-Object System.Windows.Forms.Padding(20)

# ------------------------------------------------------------------
# Painel de rodape (parte inferior da tela). Fica escondido por
# padrao e so aparece na tela "Aplicativos": e nele que moram os
# botoes genericos "Instalar" e "Desinstalar", que agem sobre os
# itens marcados nas caixas de selecao daquela tela (ex.: Java). A
# tela "Navegadores" ja tem seus proprios botoes Instalar/Desinstalar
# por navegador, entao o rodape fica oculto nela.
# ------------------------------------------------------------------
$painelRodape = New-Object System.Windows.Forms.Panel
$painelRodape.Dock = "Bottom"
$painelRodape.Height = 56
$painelRodape.BackColor = $corFundoMenu
$painelRodape.Visible = $false

$labelStatusRodape = New-Object System.Windows.Forms.Label
$labelStatusRodape.Text = ""
$labelStatusRodape.ForeColor = [System.Drawing.Color]::White
$labelStatusRodape.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$labelStatusRodape.AutoSize = $true
$labelStatusRodape.Location = New-Object System.Drawing.Point(20, 19)
$painelRodape.Controls.Add($labelStatusRodape)

$botaoRodapeInstalar = New-Object System.Windows.Forms.Button
$botaoRodapeInstalar.Text = "Instalar"
$botaoRodapeInstalar.FlatStyle = "Flat"
$botaoRodapeInstalar.FlatAppearance.BorderSize = 0
$botaoRodapeInstalar.BackColor = $corBotaoMenuHover
$botaoRodapeInstalar.ForeColor = [System.Drawing.Color]::White
$botaoRodapeInstalar.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$botaoRodapeInstalar.Size = New-Object System.Drawing.Size(110, 32)
$botaoRodapeInstalar.Cursor = "Hand"
$painelRodape.Controls.Add($botaoRodapeInstalar)

$botaoRodapeDesinstalar = New-Object System.Windows.Forms.Button
$botaoRodapeDesinstalar.Text = "Desinstalar"
$botaoRodapeDesinstalar.FlatStyle = "Flat"
$botaoRodapeDesinstalar.FlatAppearance.BorderSize = 0
$botaoRodapeDesinstalar.BackColor = [System.Drawing.Color]::FromArgb(180, 40, 40)
$botaoRodapeDesinstalar.ForeColor = [System.Drawing.Color]::White
$botaoRodapeDesinstalar.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$botaoRodapeDesinstalar.Size = New-Object System.Drawing.Size(110, 32)
$botaoRodapeDesinstalar.Cursor = "Hand"
$painelRodape.Controls.Add($botaoRodapeDesinstalar)

# Mantem os dois botoes colados no canto inferior direito do rodape,
# mesmo que a janela seja redimensionada.
function Reposicionar-BotoesRodape {
    $largura = $painelRodape.ClientSize.Width
    $botaoRodapeDesinstalar.Location = New-Object System.Drawing.Point(($largura - 130), 12)
    $botaoRodapeInstalar.Location    = New-Object System.Drawing.Point(($largura - 250), 12)
}
$painelRodape.Add_Resize({ Reposicionar-BotoesRodape })

# Referencias de script (atualizadas por cada tela que usa o rodape,
# ex.: "Aplicativos") indicando qual caixa de selecao e qual label de
# status o rodape deve usar no momento, para cada item gerenciado por
# ele (Java e WinRAR).
$script:chkJava = $null
$script:labelStatusJava = $null
$script:barraProgressoJava = $null

$script:chkWinRAR = $null
$script:labelStatusWinRAR = $null
$script:barraProgressoWinRAR = $null

# Reavalia, com base em QUAL caixa de selecao esta marcada no momento
# (Java ou WinRAR), se o item correspondente ja esta instalado, e
# ajusta os botoes do rodape de acordo: se ja estiver instalado,
# "Instalar" fica desativado (nao ha o que instalar de novo); se nao
# estiver, quem fica desativado e o "Desinstalar". Se nenhuma caixa
# estiver marcada (ou as duas ao mesmo tempo), os dois botoes ficam
# desativados ate o usuario marcar um unico item. Usada tanto ao
# marcar/desmarcar uma caixa quanto apos qualquer tentativa de
# instalacao/desinstalacao (sucesso, falha ou timeout).
function Atualizar-BotoesRodapeAplicativos {
    $javaMarcado   = [bool]($script:chkJava -and $script:chkJava.Checked)
    $winrarMarcado = [bool]($script:chkWinRAR -and $script:chkWinRAR.Checked)

    if ($javaMarcado -and $winrarMarcado) {
        $botaoRodapeInstalar.Enabled = $false
        $botaoRodapeDesinstalar.Enabled = $false
        return
    }

    if ($winrarMarcado) {
        $jaInstalado = [bool](Get-WinRARExePath)
    } elseif ($javaMarcado) {
        $jaInstalado = [bool](Get-JavaExePath)
    } else {
        $botaoRodapeInstalar.Enabled = $false
        $botaoRodapeDesinstalar.Enabled = $false
        return
    }

    $botaoRodapeInstalar.Enabled = (-not $jaInstalado)
    $botaoRodapeDesinstalar.Enabled = $jaInstalado
}

# Mantido por compatibilidade com o nome usado no restante do fluxo do
# Java: apenas encaminha para a versao generica acima.
function Atualizar-BotoesRodapeJava {
    Atualizar-BotoesRodapeAplicativos
}

# ------------------------------------------------------------------
# Atualiza o Value de uma ProgressBar forcando o redesenho imediato.
#
# Bug conhecido do WinForms: com os Visual Styles do Windows ativos,
# uma ProgressBar "Continuous" que recebe incrementos pequenos e
# frequentes (como aqui, a cada 200ms) muitas vezes NAO repinta o
# preenchimento - o .Value muda internamente, mas visualmente a barra
# fica parada. O truque classico (documentado ha anos para WinForms)
# e forcar o controle a "recuar e avancar": setar um valor vizinho
# antes do valor real faz o Windows tratar como uma mudanca de
# verdade e redesenhar na hora, em vez de tentar (e falhar em)
# animar suavemente entre valores proximos.
# ------------------------------------------------------------------
function Atualizar-ValorBarraProgresso {
    param(
        [System.Windows.Forms.ProgressBar]$Barra,
        [int]$Valor
    )

    if ($Valor -ge $Barra.Maximum) {
        $Barra.Value = $Barra.Maximum - 1
        $Barra.Value = $Barra.Maximum
    } elseif ($Valor -le $Barra.Minimum) {
        $Barra.Value = $Barra.Minimum + 1
        $Barra.Value = $Barra.Minimum
    } else {
        $Barra.Value = $Valor + 1
        $Barra.Value = $Valor
    }
}

# ------------------------------------------------------------------
# Instala o Java (via winget) usando a mesma logica que antes ficava
# no botao "Instalar" de cada linha, agora disparada pelo botao
# generico do rodape.
# ------------------------------------------------------------------
function Invoke-RodapeInstalarJava {
    if (-not $script:chkJava.Checked) {
        [System.Windows.Forms.MessageBox]::Show(
            "Marque a caixa de selecao ao lado do Java antes de clicar em Instalar.",
            "Java",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    $botaoRodapeInstalar.Enabled = $false
    $botaoRodapeDesinstalar.Enabled = $false
    $script:chkJava.Enabled = $false
    $script:labelStatusJava.Text = ""
    $script:barraProgressoJava.Visible = $true
    [System.Windows.Forms.Application]::DoEvents()

    # IMPORTANTE: .GetNewClosure() isola o scriptblock do timer, abaixo,
    # em um escopo que nao enxerga funcoes definidas no script (mesmo
    # problema ja documentado no fluxo de desinstalar Firefox). Por isso
    # capturamos as funcoes que o timer precisa chamar como referencias
    # de scriptblock em variaveis locais ANTES do GetNewClosure() -
    # variaveis (ao contrario de funcoes) SAO capturadas corretamente.
    $refAtualizarValorBarra = ${function:Atualizar-ValorBarraProgresso}
    $refGetDescricaoErroWinget = ${function:Get-DescricaoErroWinget}
    $refAtualizarBotoesRodapeJava = ${function:Atualizar-BotoesRodapeJava}
    $refGetJavaExePath = ${function:Get-JavaExePath}

    # IMPORTANTE (correcao de bug): .GetNewClosure(), usado no timer logo
    # abaixo, "congela" o VALOR de qualquer variavel no momento em que e
    # chamado - inclusive variaveis com o prefixo $script:. Como
    # $script:barraProgressoJava, $script:labelStatusJava e
    # $script:chkJava sao reatribuidas toda vez que a tela "Aplicativos"
    # e reconstruida, e $botaoAplicativos/$labelStatusRodape vivem em
    # outro escopo, referencia-los diretamente dentro do timer pode
    # resultar em $null (gerando os erros "propriedade nao encontrada" /
    # "metodo em uma expressao de valor nulo"). Por isso capturamos aqui,
    # em variaveis locais simples, os mesmos objetos - a captura de
    # variaveis locais por .GetNewClosure() funciona corretamente (e o
    # mesmo motivo pelo qual $refAtualizarValorBarra acima funciona).
    $ctrlBarraJava         = $script:barraProgressoJava
    $ctrlLabelStatusJava   = $script:labelStatusJava
    $ctrlChkJava           = $script:chkJava
    $ctrlBotaoAplicativos  = $botaoAplicativos
    $ctrlLabelStatusRodape = $labelStatusRodape

    try {
        $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
        $caminhoWinget = $null

        if ($wingetCmd) {
            $caminhoWinget = $wingetCmd.Source
        } else {
            $candidato = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
            if (Test-Path $candidato) {
                $caminhoWinget = $candidato
            }
        }

        if (-not $caminhoWinget) {
            throw "winget (App Installer) nao foi encontrado nesta maquina. Instale o 'App Installer' pela Microsoft Store e tente novamente."
        }

        $psiInstalarJava = New-Object System.Diagnostics.ProcessStartInfo
        $psiInstalarJava.FileName = $caminhoWinget
        $psiInstalarJava.Arguments = 'install -e --id "Oracle.JavaRuntimeEnvironment" --silent --accept-package-agreements --accept-source-agreements --disable-interactivity'
        $psiInstalarJava.UseShellExecute = $false
        $psiInstalarJava.CreateNoWindow = $true
        $psiInstalarJava.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

        # NOTA: a captura assincrona de saida (RedirectStandardOutput/Error
        # + Register-ObjectEvent) foi removida daqui de propósito. Esse
        # mecanismo roda em um escopo separado do PowerShell (o scriptblock
        # do evento nao enxerga variaveis locais da funcao sem o mesmo
        # cuidado de captura usado no timer) e podia interferir na deteccao
        # de termino do processo, impedindo o refresh da tela apos a
        # instalacao. O desinstalador nunca usou esse mecanismo e sempre
        # atualizou a tela corretamente - por isso o instalador agora segue
        # exatamente o mesmo padrao simples (sem redirecionar saida).
        $processoInstalarJava = New-Object System.Diagnostics.Process
        $processoInstalarJava.StartInfo = $psiInstalarJava
        $processoInstalarJava.Start() | Out-Null

        # Barra "Continuous" (em vez de indeterminada) para poder ir
        # crescendo aos poucos enquanto o winget roda escondido - como
        # a instalacao silenciosa nao informa progresso real, o avanco
        # e simulado (mesmo truque ja usado no popup de progresso dos
        # navegadores), indo ate praticamente 100% enquanto o processo
        # ainda esta rodando, e so batendo o 100% quando ele realmente
        # termina.
        $script:barraProgressoJava.Style = "Continuous"
        $script:barraProgressoJava.Minimum = 0
        $script:barraProgressoJava.Maximum = 100
        $script:barraProgressoJava.Value = 0

        $estadoInstalacaoJava = @{
            Concluido        = $false
            TicksDecorridos  = 0
            ProcessoSaiu     = $false
            TicksVerificacao = 0
            Finalizando      = $false
            TicksAteFechar   = 0
            TrocouParaTexto  = $false
        }
        # 200ms x 900 = 3 minutos, mesmo limite usado nos navegadores.
        $ticksTimeoutJava = 900
        # O winget pode retornar codigo 0 antes do instalador do Java
        # terminar de fato de gravar o javaw.exe em disco (mesma causa
        # raiz ja corrigida no fluxo dos navegadores). Por isso, depois
        # do ExitCode 0, ainda esperamos ate 5s tentando DETECTAR o Java
        # de verdade antes de considerar a instalacao concluida - e so
        # entao a barra bate 100% e o texto muda para "Instalado".
        $ticksMaxVerificacaoJava = 25   # 25 x 200ms = 5s
        # 200ms x 3 = 0,6s com a barra parada em 100% antes de trocar
        # pelo texto "Instalado".
        $ticksComBarraCheia = 3
        # 200ms x 6 = 1,2s no total (barra cheia + texto "Instalado")
        # antes de atualizar a tela.
        $ticksParaAtualizarTela = 6

        $timerInstalarJava = New-Object System.Windows.Forms.Timer
        $timerInstalarJava.Interval = 200

        $timerInstalarJava.Add_Tick({
            if ($estadoInstalacaoJava.Concluido) { return }

            # Instalacao ja confirmada: mostra a barra cheia (100%) por
            # um instante, depois troca pelo texto "Instalado" e só
            # então atualiza a tela.
            if ($estadoInstalacaoJava.Finalizando) {
                $estadoInstalacaoJava.TicksAteFechar++

                if ((-not $estadoInstalacaoJava.TrocouParaTexto) -and ($estadoInstalacaoJava.TicksAteFechar -ge $ticksComBarraCheia)) {
                    $estadoInstalacaoJava.TrocouParaTexto = $true
                    $ctrlBarraJava.Visible = $false
                    $ctrlLabelStatusJava.Text = "Instalado"
                    $ctrlLabelStatusJava.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 60)
                }

                if ($estadoInstalacaoJava.TicksAteFechar -ge $ticksParaAtualizarTela) {
                    $estadoInstalacaoJava.Concluido = $true
                    $timerInstalarJava.Stop()
                    $timerInstalarJava.Dispose()

                    # Atualiza a tela inteira para refletir o novo estado.
                    # Isso recria o label de status da linha do Java, entao
                    # a mensagem final e escrita no rodape (que nao e
                    # recriado) DEPOIS do refresh, para nao ser descartada
                    # junto com o label antigo.
                    $ctrlBotaoAplicativos.PerformClick()
                    $ctrlLabelStatusRodape.Text = "Java instalado com sucesso."
                }
                return
            }

            if (-not $estadoInstalacaoJava.ProcessoSaiu) {
                $estadoInstalacaoJava.TicksDecorridos++

                if ((-not $processoInstalarJava.HasExited) -and ($estadoInstalacaoJava.TicksDecorridos -ge $ticksTimeoutJava)) {
                    $estadoInstalacaoJava.Concluido = $true
                    try { $processoInstalarJava.Kill($true) } catch { }
                    $timerInstalarJava.Stop()
                    $timerInstalarJava.Dispose()

                    $ctrlBarraJava.Visible = $false
                    $ctrlLabelStatusJava.Text = "A instalacao travou e foi cancelada apos 3 minutos."
                    & $refAtualizarBotoesRodapeJava
                    $ctrlChkJava.Enabled = $true
                    $ctrlBotaoAplicativos.PerformClick()
                    return
                }

                if ($processoInstalarJava.HasExited) {
                    $estadoInstalacaoJava.ProcessoSaiu = $true
                } else {
                    # Ainda rodando: cresce a barra aos poucos ate 99% (o
                    # winget silencioso nao informa progresso real).
                    if ($ctrlBarraJava.Value -lt 99) {
                        $incremento = Get-Random -Minimum 2 -Maximum 6
                        $novoValor = $ctrlBarraJava.Value + $incremento
                        if ($novoValor -gt 99) { $novoValor = 99 }
                        & $refAtualizarValorBarra -Barra $ctrlBarraJava -Valor $novoValor
                    }
                    return
                }
            }

            if ($processoInstalarJava.ExitCode -ne 0) {
                $descricaoErroJava = & $refGetDescricaoErroWinget -CodigoSaida $processoInstalarJava.ExitCode

                $estadoInstalacaoJava.Concluido = $true
                $timerInstalarJava.Stop()
                $timerInstalarJava.Dispose()

                $ctrlBarraJava.Visible = $false
                $ctrlLabelStatusJava.Text = "Falha (codigo $($processoInstalarJava.ExitCode)): $descricaoErroJava"

                [System.Windows.Forms.MessageBox]::Show(
                    "Falha ao instalar o Java.`n`nCodigo: $($processoInstalarJava.ExitCode)`nMotivo provavel: $descricaoErroJava",
                    "Erro na instalacao",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                & $refAtualizarBotoesRodapeJava
                $ctrlChkJava.Enabled = $true
                $ctrlBotaoAplicativos.PerformClick()
                return
            }

            # winget disse que deu certo: so consideramos REALMENTE
            # instalado quando conseguirmos detectar o javaw.exe de
            # verdade, em vez de confiar cegamente no codigo de saida.
            $detectado = [bool](& $refGetJavaExePath)
            $estadoInstalacaoJava.TicksVerificacao++

            if ($detectado -or ($estadoInstalacaoJava.TicksVerificacao -ge $ticksMaxVerificacaoJava)) {
                # Preenche a barra ate 100% e a mantem visivel por um
                # instante antes de trocar pelo texto "Instalado" (feito
                # no proprio timer, logo acima).
                & $refAtualizarValorBarra -Barra $ctrlBarraJava -Valor 100
                $estadoInstalacaoJava.Finalizando = $true
            }
            # senao: ainda esperando o SO confirmar - a barra fica
            # parada em 99% e tentamos de novo no proximo tick (200ms).
        }.GetNewClosure())

        # Guarda o Timer em escopo de script para garantir que ele nao
        # seja coletado pelo garbage collector do .NET enquanto ainda
        # esta rodando (um Timer do WinForms sem nenhuma referencia
        # "viva" fora do proprio evento pode ser descartado no meio da
        # execucao, interrompendo os ticks sem aviso nenhum).
        $script:timerInstalarJava = $timerInstalarJava
        $timerInstalarJava.Start()
    } catch {
        $script:barraProgressoJava.Visible = $false
        $script:labelStatusJava.Text = "Erro ao instalar: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Falha ao instalar o Java:`n`n$($_.Exception.Message)",
            "Erro na instalacao",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        Atualizar-BotoesRodapeJava
        $script:chkJava.Enabled = $true
        $botaoAplicativos.PerformClick()
    }
}

# ------------------------------------------------------------------
# Desinstala o Java (via winget), mesmo padrao usado no botao
# "Desinstalar" dos navegadores (Chrome/Firefox), agora disparado
# pelo botao generico do rodape.
# ------------------------------------------------------------------
function Invoke-RodapeDesinstalarJava {
    if (-not $script:chkJava.Checked) {
        [System.Windows.Forms.MessageBox]::Show(
            "Marque a caixa de selecao ao lado do Java antes de clicar em Desinstalar.",
            "Java",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    if (-not (Get-JavaExePath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "O Java nao esta instalado nesta maquina.",
            "Java",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }

    $botaoRodapeInstalar.Enabled = $false
    $botaoRodapeDesinstalar.Enabled = $false
    $script:chkJava.Enabled = $false
    $script:labelStatusJava.Text = ""
    $script:barraProgressoJava.Visible = $true
    [System.Windows.Forms.Application]::DoEvents()

    # Mesmo motivo do instalador: captura as funcoes como referencias de
    # scriptblock antes do GetNewClosure() do timer, abaixo, poder isola-lo.
    $refAtualizarValorBarra = ${function:Atualizar-ValorBarraProgresso}
    $refGetDescricaoErroWinget = ${function:Get-DescricaoErroWinget}
    $refAtualizarBotoesRodapeJava = ${function:Atualizar-BotoesRodapeJava}

    # Mesma correcao aplicada em Invoke-RodapeInstalarJava: captura em
    # variaveis locais simples para que .GetNewClosure() (no timer logo
    # abaixo) preserve os objetos corretos em vez de congela-los como
    # $null.
    $ctrlBarraJava         = $script:barraProgressoJava
    $ctrlLabelStatusJava   = $script:labelStatusJava
    $ctrlChkJava           = $script:chkJava
    $ctrlBotaoAplicativos  = $botaoAplicativos
    $ctrlLabelStatusRodape = $labelStatusRodape

    try {
        $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
        $caminhoWinget = "winget"

        if ($wingetCmd) {
            $caminhoWinget = $wingetCmd.Source
        } else {
            $candidato = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
            if (Test-Path $candidato) {
                $caminhoWinget = $candidato
            }
        }

        $psiDesinstalarJava = New-Object System.Diagnostics.ProcessStartInfo
        $psiDesinstalarJava.FileName = $caminhoWinget
        $psiDesinstalarJava.Arguments = 'uninstall --id "Oracle.JavaRuntimeEnvironment" -e --silent --accept-source-agreements'
        $psiDesinstalarJava.UseShellExecute = $false
        $psiDesinstalarJava.CreateNoWindow = $true
        $psiDesinstalarJava.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

        # Captura a saida real (stdout/stderr) do winget para, em caso de
        # falha, mostrar ao usuario o motivo verdadeiro (ex: o proprio
        # texto de erro do desinstalador do Java) em vez de so o codigo
        # numerico. Usamos ReadToEndAsync em vez de Register-ObjectEvent
        # (mecanismo usado la no Brave) de proposito: Register-ObjectEvent
        # roda o callback num escopo separado do PowerShell e ja causou
        # problema aqui antes (ver nota no instalador de Java, acima,
        # onde esse mecanismo foi removido). ReadToEndAsync roda no
        # proprio .NET, sem esse problema, e o resultado so e lido depois
        # que o processo ja terminou (HasExited), entao nao ha risco de
        # travar esperando saida que nunca vem.
        $psiDesinstalarJava.RedirectStandardOutput = $true
        $psiDesinstalarJava.RedirectStandardError = $true

        $processoDesinstalarJava = New-Object System.Diagnostics.Process
        $processoDesinstalarJava.StartInfo = $psiDesinstalarJava
        $processoDesinstalarJava.Start() | Out-Null

        $tarefaSaidaPadraoJava = $processoDesinstalarJava.StandardOutput.ReadToEndAsync()
        $tarefaSaidaErroJava   = $processoDesinstalarJava.StandardError.ReadToEndAsync()

        # Mesma logica de barra "Continuous" com crescimento simulado
        # usada no Instalar: cresce ate praticamente 100% enquanto o
        # winget roda escondido, e so bate o 100% quando ele realmente
        # termina.
        $script:barraProgressoJava.Style = "Continuous"
        $script:barraProgressoJava.Minimum = 0
        $script:barraProgressoJava.Maximum = 100
        $script:barraProgressoJava.Value = 0

        $estadoDesinstalacaoJava = @{
            Concluido        = $false
            TicksDecorridos  = 0
            Finalizando      = $false
            TicksAteFechar   = 0
            TrocouParaTexto  = $false
        }
        $ticksTimeoutJava = 900
        # 200ms x 3 = 0,6s com a barra parada em 100% antes de trocar
        # pelo texto "Desinstalado".
        $ticksComBarraCheia = 3
        # 200ms x 6 = 1,2s no total (barra cheia + texto "Desinstalado")
        # antes de atualizar a tela.
        $ticksParaAtualizarTela = 6

        $timerDesinstalarJava = New-Object System.Windows.Forms.Timer
        $timerDesinstalarJava.Interval = 200

        $timerDesinstalarJava.Add_Tick({
            if ($estadoDesinstalacaoJava.Concluido) { return }

            # Desinstalacao ja terminou com sucesso: mostra a barra
            # cheia (100%) por um instante, depois troca pelo texto
            # "Desinstalado" e só então atualiza a tela.
            if ($estadoDesinstalacaoJava.Finalizando) {
                $estadoDesinstalacaoJava.TicksAteFechar++

                if ((-not $estadoDesinstalacaoJava.TrocouParaTexto) -and ($estadoDesinstalacaoJava.TicksAteFechar -ge $ticksComBarraCheia)) {
                    $estadoDesinstalacaoJava.TrocouParaTexto = $true
                    $ctrlBarraJava.Visible = $false
                    $ctrlLabelStatusJava.Text = "Desinstalado"
                    $ctrlLabelStatusJava.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 60)
                }

                if ($estadoDesinstalacaoJava.TicksAteFechar -ge $ticksParaAtualizarTela) {
                    $estadoDesinstalacaoJava.Concluido = $true
                    $timerDesinstalarJava.Stop()
                    $timerDesinstalarJava.Dispose()

                    # Mesmo raciocinio do Instalar: a mensagem vai no
                    # rodape (nao e recriado) e e escrita DEPOIS do
                    # refresh da tela.
                    $ctrlBotaoAplicativos.PerformClick()
                    $ctrlLabelStatusRodape.Text = "Java desinstalado com sucesso."
                }
                return
            }

            $estadoDesinstalacaoJava.TicksDecorridos++

            if ((-not $processoDesinstalarJava.HasExited) -and ($estadoDesinstalacaoJava.TicksDecorridos -ge $ticksTimeoutJava)) {
                $estadoDesinstalacaoJava.Concluido = $true
                try { $processoDesinstalarJava.Kill($true) } catch { }
                $timerDesinstalarJava.Stop()
                $timerDesinstalarJava.Dispose()

                $ctrlBarraJava.Visible = $false
                $ctrlLabelStatusJava.Text = "A desinstalacao travou e foi cancelada apos 3 minutos."
                & $refAtualizarBotoesRodapeJava
                $ctrlChkJava.Enabled = $true
                $ctrlBotaoAplicativos.PerformClick()
                return
            }

            if ($processoDesinstalarJava.HasExited) {
                if ($processoDesinstalarJava.ExitCode -eq 0) {
                    # Preenche a barra ate 100% e a mantem visivel por
                    # um instante antes de trocar pelo texto
                    # "Desinstalado" (feito no proprio timer, logo acima).
                    & $refAtualizarValorBarra -Barra $ctrlBarraJava -Valor 100
                    $estadoDesinstalacaoJava.Finalizando = $true
                } else {
                    $descricaoErroJava = & $refGetDescricaoErroWinget -CodigoSaida $processoDesinstalarJava.ExitCode

                    # Recolhe a saida real que o winget/desinstalador do
                    # Java escreveu (se houver) - essa e a parte que
                    # realmente ajuda a diagnosticar o "motivo provavel"
                    # generico da tabela de codigos. Os .Wait(500) sao so
                    # uma rede de seguranca: neste ponto o processo ja
                    # terminou (HasExited), entao a tarefa assincrona ja
                    # deveria estar concluida ha bastante tempo.
                    $resumoSaidaJava = "(o winget nao devolveu nenhuma saida de texto)"
                    try {
                        $textoSaidaPadrao = ""
                        $textoSaidaErro   = ""
                        if ($tarefaSaidaPadraoJava.Wait(500)) { $textoSaidaPadrao = $tarefaSaidaPadraoJava.Result }
                        if ($tarefaSaidaErroJava.Wait(500))   { $textoSaidaErro   = $tarefaSaidaErroJava.Result }

                        $linhasSaidaJava = @(($textoSaidaPadrao + "`n" + $textoSaidaErro) -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
                        if ($linhasSaidaJava.Count -gt 0) {
                            # So as ultimas linhas: a mensagem de erro do
                            # winget normalmente vem no final da saida, e
                            # isso evita uma caixa de mensagem gigante.
                            $resumoSaidaJava = ($linhasSaidaJava | Select-Object -Last 12) -join "`n"
                        }
                    } catch { }

                    $estadoDesinstalacaoJava.Concluido = $true
                    $timerDesinstalarJava.Stop()
                    $timerDesinstalarJava.Dispose()

                    $ctrlBarraJava.Visible = $false
                    $ctrlLabelStatusJava.Text = "Falha (codigo $($processoDesinstalarJava.ExitCode)): $descricaoErroJava"
                    [System.Windows.Forms.MessageBox]::Show(
                        "Falha ao desinstalar o Java.`n`nCodigo: $($processoDesinstalarJava.ExitCode)`nMotivo provavel: $descricaoErroJava`n`nSaida detalhada do winget:`n$resumoSaidaJava",
                        "Erro na desinstalacao",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    )
                    & $refAtualizarBotoesRodapeJava
                    $ctrlChkJava.Enabled = $true
                    $ctrlBotaoAplicativos.PerformClick()
                }
                return
            }

            # Ainda rodando: cresce a barra aos poucos ate 99%.
            if ($ctrlBarraJava.Value -lt 99) {
                $incremento = Get-Random -Minimum 2 -Maximum 6
                $novoValor = $ctrlBarraJava.Value + $incremento
                if ($novoValor -gt 99) { $novoValor = 99 }
                & $refAtualizarValorBarra -Barra $ctrlBarraJava -Valor $novoValor
            }
        }.GetNewClosure())

        # Mesmo cuidado do instalador: mantem o Timer referenciado em
        # escopo de script para nao ser coletado pelo GC no meio da
        # desinstalacao.
        $script:timerDesinstalarJava = $timerDesinstalarJava
        $timerDesinstalarJava.Start()
    } catch {
        $script:barraProgressoJava.Visible = $false
        $script:labelStatusJava.Text = "Erro ao desinstalar: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Falha ao desinstalar o Java:`n`n$($_.Exception.Message)",
            "Erro na desinstalacao",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        Atualizar-BotoesRodapeJava
        $script:chkJava.Enabled = $true
        $botaoAplicativos.PerformClick()
    }
}

# ------------------------------------------------------------------
# O rodape tem um unico par de botoes "Instalar"/"Desinstalar" para
# toda a tela "Aplicativos", mas agora ela lista dois itens (Java e
# WinRAR). Estas funcoes-despachante decidem, no momento do clique,
# para qual item a acao deve valer, com base em qual caixa de selecao
# esta marcada:
#   - so uma caixa marcada  -> executa a acao para aquele item;
#   - nenhuma marcada       -> avisa para marcar um item primeiro;
#   - as duas marcadas      -> avisa para marcar so um item por vez
#     (a logica de instalar/desinstalar cada item roda isolada, entao
#     nao da para fazer as duas coisas ao mesmo tempo com uma unica
#     barra de progresso/rodape).
# ------------------------------------------------------------------
function Invoke-RodapeInstalarDespachante {
    $javaMarcado   = [bool]($script:chkJava -and $script:chkJava.Checked)
    $winrarMarcado = [bool]($script:chkWinRAR -and $script:chkWinRAR.Checked)

    if ($javaMarcado -and $winrarMarcado) {
        [System.Windows.Forms.MessageBox]::Show(
            "Marque apenas um item por vez antes de clicar em Instalar.",
            "Aplicativos",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    if ($winrarMarcado) {
        Invoke-RodapeInstalarWinRAR
        return
    }

    if ($javaMarcado) {
        Invoke-RodapeInstalarJava
        return
    }

    [System.Windows.Forms.MessageBox]::Show(
        "Marque a caixa de selecao do item desejado antes de clicar em Instalar.",
        "Aplicativos",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
}

function Invoke-RodapeDesinstalarDespachante {
    $javaMarcado   = [bool]($script:chkJava -and $script:chkJava.Checked)
    $winrarMarcado = [bool]($script:chkWinRAR -and $script:chkWinRAR.Checked)

    if ($javaMarcado -and $winrarMarcado) {
        [System.Windows.Forms.MessageBox]::Show(
            "Marque apenas um item por vez antes de clicar em Desinstalar.",
            "Aplicativos",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    if ($winrarMarcado) {
        Invoke-RodapeDesinstalarWinRAR
        return
    }

    if ($javaMarcado) {
        Invoke-RodapeDesinstalarJava
        return
    }

    [System.Windows.Forms.MessageBox]::Show(
        "Marque a caixa de selecao do item desejado antes de clicar em Desinstalar.",
        "Aplicativos",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
}

$botaoRodapeInstalar.Add_Click({ Invoke-RodapeInstalarDespachante })
$botaoRodapeDesinstalar.Add_Click({ Invoke-RodapeDesinstalarDespachante })

# ------------------------------------------------------------------
# WinRAR: agora usa exatamente o mesmo padrao do Java (caixa de
# selecao + botoes genericos do rodape), em vez de botoes proprios na
# linha.
# ------------------------------------------------------------------
function Invoke-RodapeInstalarWinRAR {
    if (-not $script:chkWinRAR.Checked) {
        [System.Windows.Forms.MessageBox]::Show(
            "Marque a caixa de selecao ao lado do WinRAR antes de clicar em Instalar.",
            "WinRAR",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    $botaoRodapeInstalar.Enabled = $false
    $botaoRodapeDesinstalar.Enabled = $false
    $script:chkWinRAR.Enabled = $false
    $script:labelStatusWinRAR.Text = ""
    $script:barraProgressoWinRAR.Visible = $true
    [System.Windows.Forms.Application]::DoEvents()

    # Mesmo cuidado do Java: captura as funcoes como referencias de
    # scriptblock ANTES do .GetNewClosure() do timer, abaixo (closures
    # nao enxergam "function ..."), e os controles $script: em
    # variaveis locais simples (que .GetNewClosure() preserva
    # corretamente, ao contrario de $script:... reatribuidas depois).
    $refAtualizarValorBarra = ${function:Atualizar-ValorBarraProgresso}
    $refGetDescricaoErroWinget = ${function:Get-DescricaoErroWinget}
    $refAtualizarBotoesRodape = ${function:Atualizar-BotoesRodapeAplicativos}
    $refGetWinRARExePath = ${function:Get-WinRARExePath}

    $ctrlBarraWinRAR       = $script:barraProgressoWinRAR
    $ctrlLabelStatusWinRAR = $script:labelStatusWinRAR
    $ctrlChkWinRAR         = $script:chkWinRAR
    $ctrlBotaoAplicativos  = $botaoAplicativos
    $ctrlLabelStatusRodape = $labelStatusRodape

    try {
        $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
        $caminhoWinget = $null

        if ($wingetCmd) {
            $caminhoWinget = $wingetCmd.Source
        } else {
            $candidato = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
            if (Test-Path $candidato) {
                $caminhoWinget = $candidato
            }
        }

        if (-not $caminhoWinget) {
            throw "winget (App Installer) nao foi encontrado nesta maquina. Instale o 'App Installer' pela Microsoft Store e tente novamente."
        }

        $psiInstalarWinRAR = New-Object System.Diagnostics.ProcessStartInfo
        $psiInstalarWinRAR.FileName = $caminhoWinget
        $psiInstalarWinRAR.Arguments = 'install -e --id "RARLab.WinRAR" --silent --accept-package-agreements --accept-source-agreements --disable-interactivity'
        $psiInstalarWinRAR.UseShellExecute = $false
        $psiInstalarWinRAR.CreateNoWindow = $true
        $psiInstalarWinRAR.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

        $processoInstalarWinRAR = New-Object System.Diagnostics.Process
        $processoInstalarWinRAR.StartInfo = $psiInstalarWinRAR
        $processoInstalarWinRAR.Start() | Out-Null

        $script:barraProgressoWinRAR.Style = "Continuous"
        $script:barraProgressoWinRAR.Minimum = 0
        $script:barraProgressoWinRAR.Maximum = 100
        $script:barraProgressoWinRAR.Value = 0

        $estadoInstalacaoWinRAR = @{
            Concluido        = $false
            TicksDecorridos  = 0
            ProcessoSaiu     = $false
            TicksVerificacao = 0
            Finalizando      = $false
            TicksAteFechar   = 0
            TrocouParaTexto  = $false
        }
        $ticksTimeoutWinRAR = 900        # 200ms x 900 = 3 minutos
        $ticksMaxVerificacaoWinRAR = 25  # 25 x 200ms = 5s
        $ticksComBarraCheia = 3
        $ticksParaAtualizarTela = 6

        $timerInstalarWinRAR = New-Object System.Windows.Forms.Timer
        $timerInstalarWinRAR.Interval = 200

        $timerInstalarWinRAR.Add_Tick({
            if ($estadoInstalacaoWinRAR.Concluido) { return }

            if ($estadoInstalacaoWinRAR.Finalizando) {
                $estadoInstalacaoWinRAR.TicksAteFechar++

                if ((-not $estadoInstalacaoWinRAR.TrocouParaTexto) -and ($estadoInstalacaoWinRAR.TicksAteFechar -ge $ticksComBarraCheia)) {
                    $estadoInstalacaoWinRAR.TrocouParaTexto = $true
                    $ctrlBarraWinRAR.Visible = $false
                    $ctrlLabelStatusWinRAR.Text = "Instalado"
                    $ctrlLabelStatusWinRAR.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 60)
                }

                if ($estadoInstalacaoWinRAR.TicksAteFechar -ge $ticksParaAtualizarTela) {
                    $estadoInstalacaoWinRAR.Concluido = $true
                    $timerInstalarWinRAR.Stop()
                    $timerInstalarWinRAR.Dispose()

                    $ctrlBotaoAplicativos.PerformClick()
                    $ctrlLabelStatusRodape.Text = "WinRAR instalado com sucesso."
                }
                return
            }

            if (-not $estadoInstalacaoWinRAR.ProcessoSaiu) {
                $estadoInstalacaoWinRAR.TicksDecorridos++

                if ((-not $processoInstalarWinRAR.HasExited) -and ($estadoInstalacaoWinRAR.TicksDecorridos -ge $ticksTimeoutWinRAR)) {
                    $estadoInstalacaoWinRAR.Concluido = $true
                    try { $processoInstalarWinRAR.Kill($true) } catch { }
                    $timerInstalarWinRAR.Stop()
                    $timerInstalarWinRAR.Dispose()

                    $ctrlBarraWinRAR.Visible = $false
                    $ctrlLabelStatusWinRAR.Text = "A instalacao travou e foi cancelada apos 3 minutos."
                    & $refAtualizarBotoesRodape
                    $ctrlChkWinRAR.Enabled = $true
                    $ctrlBotaoAplicativos.PerformClick()
                    return
                }

                if ($processoInstalarWinRAR.HasExited) {
                    $estadoInstalacaoWinRAR.ProcessoSaiu = $true
                } else {
                    if ($ctrlBarraWinRAR.Value -lt 99) {
                        $incremento = Get-Random -Minimum 2 -Maximum 6
                        $novoValor = $ctrlBarraWinRAR.Value + $incremento
                        if ($novoValor -gt 99) { $novoValor = 99 }
                        & $refAtualizarValorBarra -Barra $ctrlBarraWinRAR -Valor $novoValor
                    }
                    return
                }
            }

            if ($processoInstalarWinRAR.ExitCode -ne 0) {
                $descricaoErroWinRAR = & $refGetDescricaoErroWinget -CodigoSaida $processoInstalarWinRAR.ExitCode

                $estadoInstalacaoWinRAR.Concluido = $true
                $timerInstalarWinRAR.Stop()
                $timerInstalarWinRAR.Dispose()

                $ctrlBarraWinRAR.Visible = $false
                $ctrlLabelStatusWinRAR.Text = "Falha (codigo $($processoInstalarWinRAR.ExitCode)): $descricaoErroWinRAR"

                [System.Windows.Forms.MessageBox]::Show(
                    "Falha ao instalar o WinRAR.`n`nCodigo: $($processoInstalarWinRAR.ExitCode)`nMotivo provavel: $descricaoErroWinRAR",
                    "Erro na instalacao",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                & $refAtualizarBotoesRodape
                $ctrlChkWinRAR.Enabled = $true
                $ctrlBotaoAplicativos.PerformClick()
                return
            }

            # winget disse que deu certo: so consideramos REALMENTE
            # instalado quando conseguirmos detectar o WinRAR.exe de
            # verdade, em vez de confiar cegamente no codigo de saida.
            $detectado = [bool](& $refGetWinRARExePath)
            $estadoInstalacaoWinRAR.TicksVerificacao++

            if ($detectado -or ($estadoInstalacaoWinRAR.TicksVerificacao -ge $ticksMaxVerificacaoWinRAR)) {
                & $refAtualizarValorBarra -Barra $ctrlBarraWinRAR -Valor 100
                $estadoInstalacaoWinRAR.Finalizando = $true
            }
        }.GetNewClosure())

        $script:timerInstalarWinRAR = $timerInstalarWinRAR
        $timerInstalarWinRAR.Start()
    } catch {
        $script:barraProgressoWinRAR.Visible = $false
        $script:labelStatusWinRAR.Text = "Erro ao instalar: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Falha ao instalar o WinRAR:`n`n$($_.Exception.Message)",
            "Erro na instalacao",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        Atualizar-BotoesRodapeAplicativos
        $script:chkWinRAR.Enabled = $true
        $botaoAplicativos.PerformClick()
    }
}

function Invoke-RodapeDesinstalarWinRAR {
    if (-not $script:chkWinRAR.Checked) {
        [System.Windows.Forms.MessageBox]::Show(
            "Marque a caixa de selecao ao lado do WinRAR antes de clicar em Desinstalar.",
            "WinRAR",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    if (-not (Get-WinRARExePath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "O WinRAR nao esta instalado nesta maquina.",
            "WinRAR",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }

    $botaoRodapeInstalar.Enabled = $false
    $botaoRodapeDesinstalar.Enabled = $false
    $script:chkWinRAR.Enabled = $false
    $script:labelStatusWinRAR.Text = ""
    $script:barraProgressoWinRAR.Visible = $true
    [System.Windows.Forms.Application]::DoEvents()

    $refAtualizarValorBarra = ${function:Atualizar-ValorBarraProgresso}
    $refAtualizarBotoesRodape = ${function:Atualizar-BotoesRodapeAplicativos}

    $ctrlBarraWinRAR       = $script:barraProgressoWinRAR
    $ctrlLabelStatusWinRAR = $script:labelStatusWinRAR
    $ctrlChkWinRAR         = $script:chkWinRAR
    $ctrlBotaoAplicativos  = $botaoAplicativos
    $ctrlLabelStatusRodape = $labelStatusRodape

    try {
        # O winget nao consegue desinstalar o WinRAR em silencio: o
        # manifesto oficial do pacote (RARLab.WinRAR) so define switches
        # silenciosos para a INSTALACAO (/S ou -s1/-s2), mas nao define
        # nenhum "UninstallerSwitches" - entao "winget uninstall --silent"
        # roda o uninstall.exe do WinRAR sem nenhum parametro, o
        # instalador fica esperando clique do usuario, o processo nunca
        # termina sozinho e o script so descobre isso 3 minutos depois,
        # no timeout. E o mesmo problema que ja resolvemos para o Brave.
        #
        # A correcao: rodar o proprio uninstall.exe do WinRAR direto,
        # acrescentando o switch silencioso oficial (/S).
        #
        # IMPORTANTE (correcao de bug): a primeira versao pegava o
        # caminho do desinstalador lendo o "UninstallString" do
        # registro. O problema e que esse valor normalmente vem SEM
        # aspas (ex.: C:\Program Files\WinRAR\uninstall.exe) e o codigo
        # cortava a string no primeiro espaco em branco - resultando em
        # "C:\Program" (partido no meio de "Program Files"), que
        # obviamente nao existe no disco. Por isso o erro "O
        # desinstalador do WinRAR (registrado como C:\Program) nao foi
        # encontrado no disco."
        #
        # A correcao evita esse parsing ambiguo por completo: como esta
        # funcao so chega ate aqui depois de confirmar que o WinRAR.exe
        # existe (checagem la em cima, via Get-WinRARExePath), basta
        # pegar a PASTA onde o WinRAR.exe de verdade esta instalado e
        # montar o caminho do uninstall.exe a partir dela - sem depender
        # de nenhuma string do registro.
        $caminhoWinRARExe = Get-WinRARExePath
        if (-not $caminhoWinRARExe) {
            throw "WinRAR nao encontrado nesta maquina."
        }

        $pastaWinRAR = Split-Path -Parent $caminhoWinRARExe
        $caminhoUninstallWinRAR = Join-Path $pastaWinRAR "uninstall.exe"
        $argsRegistroWinRAR = ""

        if (-not (Test-Path -LiteralPath $caminhoUninstallWinRAR)) {
            throw "O desinstalador do WinRAR (`"$caminhoUninstallWinRAR`") nao foi encontrado no disco."
        }

        $psiDesinstalarWinRAR = New-Object System.Diagnostics.ProcessStartInfo
        $psiDesinstalarWinRAR.FileName = $caminhoUninstallWinRAR
        $psiDesinstalarWinRAR.Arguments = ($argsRegistroWinRAR + " /S").Trim()
        $psiDesinstalarWinRAR.UseShellExecute = $false
        $psiDesinstalarWinRAR.CreateNoWindow = $true
        $psiDesinstalarWinRAR.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

        $processoDesinstalarWinRAR = New-Object System.Diagnostics.Process
        $processoDesinstalarWinRAR.StartInfo = $psiDesinstalarWinRAR
        $processoDesinstalarWinRAR.Start() | Out-Null

        $script:barraProgressoWinRAR.Style = "Continuous"
        $script:barraProgressoWinRAR.Minimum = 0
        $script:barraProgressoWinRAR.Maximum = 100
        $script:barraProgressoWinRAR.Value = 0

        $estadoDesinstalacaoWinRAR = @{
            Concluido       = $false
            TicksDecorridos = 0
            Finalizando     = $false
            TicksAteFechar  = 0
            TrocouParaTexto = $false
        }
        $ticksTimeoutWinRAR = 900
        $ticksComBarraCheia = 3
        $ticksParaAtualizarTela = 6

        $timerDesinstalarWinRAR = New-Object System.Windows.Forms.Timer
        $timerDesinstalarWinRAR.Interval = 200

        $timerDesinstalarWinRAR.Add_Tick({
            if ($estadoDesinstalacaoWinRAR.Concluido) { return }

            if ($estadoDesinstalacaoWinRAR.Finalizando) {
                $estadoDesinstalacaoWinRAR.TicksAteFechar++

                if ((-not $estadoDesinstalacaoWinRAR.TrocouParaTexto) -and ($estadoDesinstalacaoWinRAR.TicksAteFechar -ge $ticksComBarraCheia)) {
                    $estadoDesinstalacaoWinRAR.TrocouParaTexto = $true
                    $ctrlBarraWinRAR.Visible = $false
                    $ctrlLabelStatusWinRAR.Text = "Desinstalado"
                    $ctrlLabelStatusWinRAR.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 60)
                }

                if ($estadoDesinstalacaoWinRAR.TicksAteFechar -ge $ticksParaAtualizarTela) {
                    $estadoDesinstalacaoWinRAR.Concluido = $true
                    $timerDesinstalarWinRAR.Stop()
                    $timerDesinstalarWinRAR.Dispose()

                    $ctrlBotaoAplicativos.PerformClick()
                    $ctrlLabelStatusRodape.Text = "WinRAR desinstalado com sucesso."
                }
                return
            }

            $estadoDesinstalacaoWinRAR.TicksDecorridos++

            if ((-not $processoDesinstalarWinRAR.HasExited) -and ($estadoDesinstalacaoWinRAR.TicksDecorridos -ge $ticksTimeoutWinRAR)) {
                $estadoDesinstalacaoWinRAR.Concluido = $true
                try { $processoDesinstalarWinRAR.Kill($true) } catch { }
                $timerDesinstalarWinRAR.Stop()
                $timerDesinstalarWinRAR.Dispose()

                $ctrlBarraWinRAR.Visible = $false
                $ctrlLabelStatusWinRAR.Text = "A desinstalacao travou e foi cancelada apos 3 minutos."
                & $refAtualizarBotoesRodape
                $ctrlChkWinRAR.Enabled = $true
                $ctrlBotaoAplicativos.PerformClick()
                return
            }

            if ($processoDesinstalarWinRAR.HasExited) {
                if ($processoDesinstalarWinRAR.ExitCode -eq 0) {
                    & $refAtualizarValorBarra -Barra $ctrlBarraWinRAR -Valor 100
                    $estadoDesinstalacaoWinRAR.Finalizando = $true
                } else {
                    # Agora rodamos o uninstall.exe do WinRAR diretamente
                    # (nao mais via winget), entao o codigo de saida e do
                    # proprio instalador do WinRAR, e nao um codigo de
                    # erro do winget - por isso nao usamos mais o
                    # Get-DescricaoErroWinget aqui.
                    $estadoDesinstalacaoWinRAR.Concluido = $true
                    $timerDesinstalarWinRAR.Stop()
                    $timerDesinstalarWinRAR.Dispose()

                    $ctrlBarraWinRAR.Visible = $false
                    $ctrlLabelStatusWinRAR.Text = "Falha (codigo $($processoDesinstalarWinRAR.ExitCode))."
                    [System.Windows.Forms.MessageBox]::Show(
                        "Falha ao desinstalar o WinRAR.`n`nCodigo de saida: $($processoDesinstalarWinRAR.ExitCode)",
                        "Erro na desinstalacao",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    )
                    & $refAtualizarBotoesRodape
                    $ctrlChkWinRAR.Enabled = $true
                    $ctrlBotaoAplicativos.PerformClick()
                }
                return
            }

            if ($ctrlBarraWinRAR.Value -lt 99) {
                $incremento = Get-Random -Minimum 2 -Maximum 6
                $novoValor = $ctrlBarraWinRAR.Value + $incremento
                if ($novoValor -gt 99) { $novoValor = 99 }
                & $refAtualizarValorBarra -Barra $ctrlBarraWinRAR -Valor $novoValor
            }
        }.GetNewClosure())

        $script:timerDesinstalarWinRAR = $timerDesinstalarWinRAR
        $timerDesinstalarWinRAR.Start()
    } catch {
        $script:barraProgressoWinRAR.Visible = $false
        $script:labelStatusWinRAR.Text = "Erro ao desinstalar: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Falha ao desinstalar o WinRAR:`n`n$($_.Exception.Message)",
            "Erro na desinstalacao",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        Atualizar-BotoesRodapeAplicativos
        $script:chkWinRAR.Enabled = $true
        $botaoAplicativos.PerformClick()
    }
}

$form.Controls.Add($painelConteudo)
$form.Controls.Add($painelMenu)
$form.Controls.Add($painelRodape)
Reposicionar-BotoesRodape

# Titulo do menu
$labelTitulo = New-Object System.Windows.Forms.Label
$labelTitulo.Text = "MENU"
$labelTitulo.ForeColor = $corTextoMenu
$labelTitulo.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$labelTitulo.Dock = "Top"
$labelTitulo.Height = 50
$labelTitulo.TextAlign = "MiddleCenter"
$painelMenu.Controls.Add($labelTitulo)

# Funcao auxiliar para criar botoes do menu com estilo consistente
function New-BotaoMenu {
    param([string]$Texto)

    $botao = New-Object System.Windows.Forms.Button
    $botao.Text = $Texto
    $botao.Dock = "Top"
    $botao.Height = 50
    $botao.FlatStyle = "Flat"
    $botao.FlatAppearance.BorderSize = 0
    $botao.BackColor = $corBotaoMenu
    $botao.ForeColor = $corTextoMenu
    $botao.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $botao.TextAlign = "MiddleLeft"
    $botao.Padding = New-Object System.Windows.Forms.Padding(15, 0, 0, 0)
    $botao.Cursor = "Hand"

    $botao.Add_MouseEnter({ $this.BackColor = $corBotaoMenuHover })
    $botao.Add_MouseLeave({ $this.BackColor = $corBotaoMenu })

    return $botao
}

# Botao "Navegadores"
$botaoNavegadores = New-BotaoMenu -Texto "Navegadores"
$painelMenu.Controls.Add($botaoNavegadores)
$botaoNavegadores.BringToFront()

# Botao "Aplicativos"
$botaoAplicativos = New-BotaoMenu -Texto "Aplicativos"
$painelMenu.Controls.Add($botaoAplicativos)
$botaoAplicativos.BringToFront()

# ------------------------------------------------------------------
# Acao do botao "Aplicativos": por enquanto so um placeholder, ate
# definirmos quais aplicativos serao gerenciados aqui (mesmo padrao
# de tela usado em "Navegadores": limpa o painel de conteudo e
# desenha o titulo da secao).
# ------------------------------------------------------------------
$botaoAplicativos.Add_Click({
    $painelConteudo.Controls.Clear()

    $labelSecaoAplicativos = New-Object System.Windows.Forms.Label
    $labelSecaoAplicativos.Text = "Aplicativos"
    $labelSecaoAplicativos.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $labelSecaoAplicativos.AutoSize = $true
    $labelSecaoAplicativos.Location = New-Object System.Drawing.Point(20, 20)
    $painelConteudo.Controls.Add($labelSecaoAplicativos)

    $y = 70

    # ---------------- Java (Oracle JRE) ----------------
    $picLogoJava = New-Object System.Windows.Forms.PictureBox
    $picLogoJava.SizeMode = "Zoom"
    $picLogoJava.Size = New-Object System.Drawing.Size(24, 24)
    $picLogoJava.Location = New-Object System.Drawing.Point(20, $y)
    $picLogoJava.Image = & $refLogoJavaOficial
    $painelConteudo.Controls.Add($picLogoJava)

    $labelNomeJava = New-Object System.Windows.Forms.Label
    $labelNomeJava.Text = "Java (Oracle JRE)"
    $labelNomeJava.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $labelNomeJava.AutoSize = $true
    $labelNomeJava.Location = New-Object System.Drawing.Point(52, ($y + 3))
    $painelConteudo.Controls.Add($labelNomeJava)

    $chkJava = New-Object System.Windows.Forms.CheckBox
    $chkJava.Text = ""
    $chkJava.Location = New-Object System.Drawing.Point(230, ($y + 2))
    $chkJava.Size = New-Object System.Drawing.Size(20, 20)
    $painelConteudo.Controls.Add($chkJava)

    $labelStatusJava = New-Object System.Windows.Forms.Label
    $labelStatusJava.Text = ""
    $labelStatusJava.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $labelStatusJava.AutoSize = $true
    $labelStatusJava.Location = New-Object System.Drawing.Point(20, ($y + 32))
    $painelConteudo.Controls.Add($labelStatusJava)

    # Barra de progresso que aparece no lugar do texto enquanto o Java
    # esta sendo instalado ou desinstalado, crescendo aos poucos (veja
    # Invoke-RodapeInstalarJava / Invoke-RodapeDesinstalarJava).
    #
    # IMPORTANTE: com os Visual Styles do Windows ativos, uma
    # ProgressBar com poucos pixels de altura (o valor original aqui
    # era 6px) nao consegue desenhar o preenchimento tematizado - o
    # controle fica visivelmente "parado" mesmo com a propriedade
    # Value mudando por tras. Por isso a altura foi aumentada para
    # 14px (mesma logica ja usada nas barras de 24px do popup dos
    # navegadores, so que compacta o suficiente para caber nesta
    # linha). Tambem posicionamos a barra alguns pixels abaixo do
    # label de status, em vez de quase sobre ele, e chamamos
    # BringToFront() para garantir que ela fique por cima na pilha de
    # desenho independente da ordem de Controls.Add.
    $barraProgressoJava = New-Object System.Windows.Forms.ProgressBar
    $barraProgressoJava.Style = "Continuous"
    $barraProgressoJava.Minimum = 0
    $barraProgressoJava.Maximum = 100
    $barraProgressoJava.Value = 0
    $barraProgressoJava.Size = New-Object System.Drawing.Size(140, 14)
    $barraProgressoJava.Location = New-Object System.Drawing.Point(20, ($y + 30))
    $barraProgressoJava.Visible = $false
    $painelConteudo.Controls.Add($barraProgressoJava)
    $barraProgressoJava.BringToFront()
    $script:barraProgressoJava = $barraProgressoJava

    $javaJaInstalado = [bool](Get-JavaExePath)
    if ($javaJaInstalado) {
        $labelStatusJava.Text = "Ja instalado nesta maquina."
    }

    # Aponta as referencias de script para a caixa de selecao e o
    # label de status do Java, para que os botoes genericos do rodape
    # (e o despachante que decide qual dos dois itens acionar) saibam
    # onde escrever.
    $script:chkJava = $chkJava
    $script:labelStatusJava = $labelStatusJava

    # ---------------- WinRAR ----------------
    # Mesmo padrao do Java: caixa de selecao + botoes genericos do
    # rodape (Invoke-RodapeInstalarWinRAR / Invoke-RodapeDesinstalarWinRAR).
    $yWinRAR = $y + 70

    $picLogoWinRAR = New-Object System.Windows.Forms.PictureBox
    $picLogoWinRAR.SizeMode = "Zoom"
    $picLogoWinRAR.Size = New-Object System.Drawing.Size(24, 24)
    $picLogoWinRAR.Location = New-Object System.Drawing.Point(20, $yWinRAR)
    $picLogoWinRAR.Image = & $refLogoWinRAROficial
    $painelConteudo.Controls.Add($picLogoWinRAR)

    $labelNomeWinRAR = New-Object System.Windows.Forms.Label
    $labelNomeWinRAR.Text = "WinRAR"
    $labelNomeWinRAR.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $labelNomeWinRAR.AutoSize = $true
    $labelNomeWinRAR.Location = New-Object System.Drawing.Point(52, ($yWinRAR + 3))
    $painelConteudo.Controls.Add($labelNomeWinRAR)

    $chkWinRAR = New-Object System.Windows.Forms.CheckBox
    $chkWinRAR.Text = ""
    $chkWinRAR.Location = New-Object System.Drawing.Point(230, ($yWinRAR + 2))
    $chkWinRAR.Size = New-Object System.Drawing.Size(20, 20)
    $painelConteudo.Controls.Add($chkWinRAR)

    $labelStatusWinRAR = New-Object System.Windows.Forms.Label
    $labelStatusWinRAR.Text = ""
    $labelStatusWinRAR.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $labelStatusWinRAR.AutoSize = $true
    $labelStatusWinRAR.Location = New-Object System.Drawing.Point(20, ($yWinRAR + 32))
    $painelConteudo.Controls.Add($labelStatusWinRAR)

    $barraProgressoWinRAR = New-Object System.Windows.Forms.ProgressBar
    $barraProgressoWinRAR.Style = "Continuous"
    $barraProgressoWinRAR.Minimum = 0
    $barraProgressoWinRAR.Maximum = 100
    $barraProgressoWinRAR.Value = 0
    $barraProgressoWinRAR.Size = New-Object System.Drawing.Size(140, 14)
    $barraProgressoWinRAR.Location = New-Object System.Drawing.Point(20, ($yWinRAR + 30))
    $barraProgressoWinRAR.Visible = $false
    $painelConteudo.Controls.Add($barraProgressoWinRAR)
    $barraProgressoWinRAR.BringToFront()
    $script:barraProgressoWinRAR = $barraProgressoWinRAR

    $winrarJaInstalado = [bool](Get-WinRARExePath)
    if ($winrarJaInstalado) {
        $labelStatusWinRAR.Text = "Ja instalado nesta maquina."
    }

    $script:chkWinRAR = $chkWinRAR
    $script:labelStatusWinRAR = $labelStatusWinRAR

    # As duas caixas de selecao (Java e WinRAR) funcionam como um
    # "escolha so um": marcar uma desmarca a outra automaticamente, e
    # qualquer mudanca reavalia os botoes do rodape para o item que
    # ficou marcado (ou os desativa, se nenhum estiver marcado).
    #
    # IMPORTANTE (correcao de bug): assim como nos timers de instalacao
    # /desinstalacao (Java, WinRAR, navegadores), o .GetNewClosure()
    # abaixo isola o scriptblock - ele "enxerga" apenas as VARIAVEIS
    # capturadas no momento da chamada, e nao funcoes definidas com
    # "function ...". Por isso a chamada direta "Atualizar-BotoesRodape
    # Aplicativos" dentro de um scriptblock com GetNewClosure() falhava
    # com "termo nao reconhecido como nome de cmdlet, funcao...". A
    # correcao e a mesma usada nos timers: capturar a funcao como
    # referencia de scriptblock ANTES do GetNewClosure() e chama-la com
    # "&" em vez de pelo nome.
    $refAtualizarBotoesRodapeChk = ${function:Atualizar-BotoesRodapeAplicativos}

    $chkJava.Add_CheckedChanged({
        if ($chkJava.Checked -and $script:chkWinRAR -and $script:chkWinRAR.Checked) {
            $script:chkWinRAR.Checked = $false
        }
        & $refAtualizarBotoesRodapeChk
    }.GetNewClosure())

    $chkWinRAR.Add_CheckedChanged({
        if ($chkWinRAR.Checked -and $script:chkJava -and $script:chkJava.Checked) {
            $script:chkJava.Checked = $false
        }
        & $refAtualizarBotoesRodapeChk
    }.GetNewClosure())

    # Nenhuma caixa comeca marcada ao (re)abrir a tela, entao os
    # botoes do rodape ficam desativados ate o usuario marcar um item.
    $labelStatusRodape.Text = ""
    Atualizar-BotoesRodapeAplicativos
    $painelRodape.Visible = $true
})

# ------------------------------------------------------------------
# Acao do botao "Navegadores": lista os navegadores instalados
# como botoes na area de conteudo, cada um abrindo o respectivo
# navegador ao ser clicado
# ------------------------------------------------------------------
$botaoNavegadores.Add_Click({
  try {
    $painelRodape.Visible = $false
    $painelConteudo.Controls.Clear()

    $labelSecao = New-Object System.Windows.Forms.Label
    $labelSecao.Text = "Navegadores instalados"
    $labelSecao.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $labelSecao.AutoSize = $true
    $labelSecao.Location = New-Object System.Drawing.Point(20, 20)
    $painelConteudo.Controls.Add($labelSecao)

    # O @() aqui e essencial: se Get-NavegadoresInstalados encontrar
    # apenas 1 navegador, o PowerShell "desembrulha" o array de 1 item
    # e o transforma num objeto solto, fazendo $instalados.Count virar
    # $null em vez de 1. Isso quebrava o calculo de posicao da linha
    # divisoria logo abaixo (ela ficava 64px mais alta que deveria,
    # exatamente em cima do icone do unico navegador encontrado, ex:
    # Edge). Envolver com @() garante que $instalados seja SEMPRE um
    # array de verdade, com .Count correto em qualquer cenario (0, 1
    # ou varios navegadores).
    $instalados = @(Get-NavegadoresInstalados)

    # IMPORTANTE: antes havia um "return" aqui quando nenhum navegador
    # conhecido era encontrado. Isso interrompia o clique inteiro e
    # impedia que a secao "Gerenciar Firefox" (mais abaixo) fosse
    # desenhada - por isso a tela ficava vazia. Agora so pulamos a
    # lista de botoes e seguimos em frente para desenhar o resto.
    $y = 70
    if ($instalados.Count -eq 0) {
        $labelVazio = New-Object System.Windows.Forms.Label
        $labelVazio.Text = "Nenhum navegador conhecido foi encontrado nesta maquina."
        $labelVazio.AutoSize = $true
        $labelVazio.Location = New-Object System.Drawing.Point(20, $y)
        $painelConteudo.Controls.Add($labelVazio)
        $y += 40
    }

    # Botoes dos navegadores instalados: quadrados, lado a lado na mesma
    # linha, mostrando somente o logo oficial (sem texto). O nome de cada
    # um fica disponivel como dica (tooltip) ao passar o mouse.
    $ferramentaDicas = New-Object System.Windows.Forms.ToolTip
    $tamanhoBotaoNav = 64
    $espacamentoBotaoNav = 12
    $xNav = 20

    foreach ($nav in $instalados) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = ""
        $btn.Width = $tamanhoBotaoNav
        $btn.Height = $tamanhoBotaoNav
        $btn.FlatStyle = "Flat"
        $btn.FlatAppearance.BorderSize = 0
        $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(225, 225, 225)
        $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(205, 205, 205)
        $btn.BackColor = $corFundoConteudo
        $btn.Location = New-Object System.Drawing.Point($xNav, $y)
        $btn.Tag = $nav.Caminho

        # Icone oficial extraido direto do executavel deste navegador
        # (mesma tecnica usada para o Firefox mais abaixo), preenchendo
        # quase todo o botao ja que nao ha texto.
        $iconeNav = Get-IconeExecutavel -CaminhoExe $nav.Caminho -Tamanho ($tamanhoBotaoNav - 20)
        if ($iconeNav) {
            $btn.Image = $iconeNav
            $btn.ImageAlign = "MiddleCenter"
        }

        $ferramentaDicas.SetToolTip($btn, $nav.Nome)

        $btn.Add_Click({
            param($sender, $e)
            try {
                Start-Process -FilePath $sender.Tag
            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Nao foi possivel abrir o navegador: $($_.Exception.Message)",
                    "Erro",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
            }
        })

        $painelConteudo.Controls.Add($btn)
        $xNav += $tamanhoBotaoNav + $espacamentoBotaoNav
    }

    if ($instalados.Count -gt 0) { $y += $tamanhoBotaoNav }

    # --------------------------------------------------------------
    # Secao de instalacao/gerenciamento dos navegadores: Firefox e
    # Chrome lado a lado, na mesma linha.
    # --------------------------------------------------------------
    $y += 20

    $linhaSeparadora = New-Object System.Windows.Forms.Label
    $linhaSeparadora.BorderStyle = "Fixed3D"
    $linhaSeparadora.Location = New-Object System.Drawing.Point(20, $y)
    $linhaSeparadora.Size = New-Object System.Drawing.Size(650, 2)
    $painelConteudo.Controls.Add($linhaSeparadora)
    $y += 20

    $labelFirefoxTitulo = New-Object System.Windows.Forms.Label
    $labelFirefoxTitulo.Text = "Gerenciar Navegadores"
    $labelFirefoxTitulo.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $labelFirefoxTitulo.AutoSize = $true
    $labelFirefoxTitulo.Location = New-Object System.Drawing.Point(20, $y)
    $painelConteudo.Controls.Add($labelFirefoxTitulo)
    $y += 35

    # Coordenadas X de cada coluna: Firefox a esquerda, Chrome a
    # direita, ambos desenhados na mesma altura ($y) - ou seja, na
    # mesma linha.
    $colFirefoxLogoX = 20
    $colFirefoxCtrlX = 95
    $colChromeLogoX  = 245
    $colChromeCtrlX  = 320
    $colBraveLogoX   = 470
    $colBraveCtrlX   = 545

    # --------------------------------------------------------------
    # Instalacao multipla: uma caixa de selecao por navegador. Se o
    # usuario marcar varias, o botao "Instalar selecionados" abaixo
    # instala todas as marcadas; se marcar somente uma, instala so
    # essa. Cada caixa fica escondida quando o navegador correspondente
    # ja esta instalado (nesse caso nao ha nada para instalar).
    # --------------------------------------------------------------
    $labelInstrucaoSelecao = New-Object System.Windows.Forms.Label
    $labelInstrucaoSelecao.Text = "Marque um ou mais navegadores e clique em `"Instalar selecionados`"."
    $labelInstrucaoSelecao.AutoSize = $true
    $labelInstrucaoSelecao.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $labelInstrucaoSelecao.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $labelInstrucaoSelecao.Location = New-Object System.Drawing.Point(20, $y)
    $painelConteudo.Controls.Add($labelInstrucaoSelecao)
    $y += 22

    $chkSelecionarFirefox = New-Object System.Windows.Forms.CheckBox
    $chkSelecionarFirefox.Text = "Selecionar"
    $chkSelecionarFirefox.AutoSize = $true
    $chkSelecionarFirefox.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $chkSelecionarFirefox.Location = New-Object System.Drawing.Point($colFirefoxLogoX, $y)
    $painelConteudo.Controls.Add($chkSelecionarFirefox)

    $chkSelecionarChrome = New-Object System.Windows.Forms.CheckBox
    $chkSelecionarChrome.Text = "Selecionar"
    $chkSelecionarChrome.AutoSize = $true
    $chkSelecionarChrome.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $chkSelecionarChrome.Location = New-Object System.Drawing.Point($colChromeLogoX, $y)
    $painelConteudo.Controls.Add($chkSelecionarChrome)

    $chkSelecionarBrave = New-Object System.Windows.Forms.CheckBox
    $chkSelecionarBrave.Text = "Selecionar"
    $chkSelecionarBrave.AutoSize = $true
    $chkSelecionarBrave.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $chkSelecionarBrave.Location = New-Object System.Drawing.Point($colBraveLogoX, $y)
    $painelConteudo.Controls.Add($chkSelecionarBrave)
    $y += 24

    # Logo do Firefox (desenhado em tempo de execucao)
    $picLogoFirefox = New-Object System.Windows.Forms.PictureBox
    $picLogoFirefox.Size = New-Object System.Drawing.Size(72, 72)
    $picLogoFirefox.Location = New-Object System.Drawing.Point($colFirefoxLogoX, $y)
    $picLogoFirefox.SizeMode = "Zoom"
    $picLogoFirefox.Image = Get-FirefoxLogoBitmap
    $painelConteudo.Controls.Add($picLogoFirefox)

    # Rotulo de status (fica ao lado da logo)
    $labelStatusFirefox = New-Object System.Windows.Forms.Label
    $labelStatusFirefox.Text = "Pronto."
    $labelStatusFirefox.AutoSize = $true
    $labelStatusFirefox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $labelStatusFirefox.Location = New-Object System.Drawing.Point($colFirefoxCtrlX, ($y + 8))
    $labelStatusFirefox.MaximumSize = New-Object System.Drawing.Size(180, 0)
    $painelConteudo.Controls.Add($labelStatusFirefox)

    # Botao Instalar - bem pequeno, cantos arredondados, ao lado do logo
    $botaoInstalarFirefox = New-Object System.Windows.Forms.Button
    $botaoInstalarFirefox.Text = "Instalar"
    $botaoInstalarFirefox.Width = 56
    $botaoInstalarFirefox.Height = 20
    $botaoInstalarFirefox.FlatStyle = "Flat"
    $botaoInstalarFirefox.FlatAppearance.BorderSize = 0
    $botaoInstalarFirefox.BackColor = [System.Drawing.Color]::FromArgb(0, 153, 76)
    $botaoInstalarFirefox.ForeColor = [System.Drawing.Color]::White
    $botaoInstalarFirefox.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
    $botaoInstalarFirefox.Location = New-Object System.Drawing.Point($colFirefoxCtrlX, ($y + 36))
    $painelConteudo.Controls.Add($botaoInstalarFirefox)
    Set-BotaoCantosArredondados -Botao $botaoInstalarFirefox -Raio 8

    # Botao Desinstalar (ao lado do Instalar)
    $botaoDesinstalarFirefox = New-Object System.Windows.Forms.Button
    $botaoDesinstalarFirefox.Text = "Desinstalar"
    $botaoDesinstalarFirefox.Width = 66
    $botaoDesinstalarFirefox.Height = 20
    $botaoDesinstalarFirefox.FlatStyle = "Flat"
    $botaoDesinstalarFirefox.FlatAppearance.BorderSize = 0
    $botaoDesinstalarFirefox.BackColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
    $botaoDesinstalarFirefox.ForeColor = [System.Drawing.Color]::White
    $botaoDesinstalarFirefox.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
    $botaoDesinstalarFirefox.Location = New-Object System.Drawing.Point(($colFirefoxCtrlX + 56 + 6), ($y + 36))
    $painelConteudo.Controls.Add($botaoDesinstalarFirefox)
    Set-BotaoCantosArredondados -Botao $botaoDesinstalarFirefox -Raio 8

    # ----------------------------------------------------------
    # Mostra so o botao que faz sentido para o estado atual:
    #   - Firefox NAO instalado -> mostra somente "Instalar"
    #   - Firefox JA instalado  -> mostra somente "Desinstalar"
    # A checagem usa tanto o executavel local quanto o registro de
    # desinstalacao (cobre casos como instalacao via MSI que nao
    # deixa o exe no caminho padrao verificado por Get-FirefoxExePath).
    # ----------------------------------------------------------
    $firefoxJaInstalado = $false
    if (Get-FirefoxExePath) {
        $firefoxJaInstalado = $true
    } elseif (Get-FirefoxUninstallInfo) {
        $firefoxJaInstalado = $true
    }

    if ($firefoxJaInstalado) {
        $botaoInstalarFirefox.Visible = $false
        # Desinstalar ocupa o lugar do Instalar quando ele fica oculto
        $botaoDesinstalarFirefox.Location = New-Object System.Drawing.Point($colFirefoxCtrlX, $botaoDesinstalarFirefox.Location.Y)
        $chkSelecionarFirefox.Visible = $false
    } else {
        $botaoDesinstalarFirefox.Visible = $false
    }

    # Identificador do pacote no winget (App Installer)
    $idPacoteWinget = "Mozilla.Firefox.pt-BR"

    $botaoInstalarFirefox.Add_Click({
        $botaoInstalarFirefox.Enabled = $false
        $botaoDesinstalarFirefox.Enabled = $false
        $labelStatusFirefox.Text = "Instalando Firefox..."
        [System.Windows.Forms.Application]::DoEvents()

        # ------------------------------------------------------
        # Janela pop-up pequena, sobreposta a janela principal,
        # com uma barra de progresso DETERMINADA (cresce aos
        # poucos) em vez da barra indeterminada anterior.
        # ------------------------------------------------------
        $formProgresso = New-Object System.Windows.Forms.Form
        $formProgresso.Text = "Instalando Firefox"
        $formProgresso.Size = New-Object System.Drawing.Size(360, 150)
        $formProgresso.FormBorderStyle = "FixedDialog"
        $formProgresso.ControlBox = $false
        $formProgresso.MaximizeBox = $false
        $formProgresso.MinimizeBox = $false
        # CenterScreen garante que a telinha sempre abra centralizada
        # na tela, independente da posicao da janela principal.
        $formProgresso.StartPosition = "CenterScreen"
        $formProgresso.BackColor = [System.Drawing.Color]::White
        $formProgresso.TopMost = $true

        $labelProgresso = New-Object System.Windows.Forms.Label
        $labelProgresso.Text = "Instalando o Firefox, aguarde..."
        $labelProgresso.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $labelProgresso.TextAlign = "MiddleCenter"
        $labelProgresso.Location = New-Object System.Drawing.Point(15, 18)
        $labelProgresso.Size = New-Object System.Drawing.Size(310, 30)
        $formProgresso.Controls.Add($labelProgresso)

        $barraProgresso = New-Object System.Windows.Forms.ProgressBar
        $barraProgresso.Style = "Continuous"
        $barraProgresso.Minimum = 0
        $barraProgresso.Maximum = 100
        $barraProgresso.Value = 0
        $barraProgresso.Location = New-Object System.Drawing.Point(15, 58)
        $barraProgresso.Size = New-Object System.Drawing.Size(310, 24)
        $formProgresso.Controls.Add($barraProgresso)

        $labelPercentual = New-Object System.Windows.Forms.Label
        $labelPercentual.Text = "0%"
        $labelPercentual.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $labelPercentual.TextAlign = "MiddleCenter"
        $labelPercentual.Location = New-Object System.Drawing.Point(15, 88)
        $labelPercentual.Size = New-Object System.Drawing.Size(310, 20)
        $formProgresso.Controls.Add($labelPercentual)

        $formProgresso.Show($form)
        [System.Windows.Forms.Application]::DoEvents()

        try {
            # O "winget" e um "App Execution Alias": em muitos cenarios
            # (principalmente executando como Administrador, ou sem o
            # WindowsApps no PATH do processo) ele nao e encontrado
            # diretamente. Resolvemos o caminho completo como fallback.
            $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
            $caminhoWinget = "winget"

            if ($wingetCmd) {
                $caminhoWinget = $wingetCmd.Source
            } else {
                $candidato = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
                if (Test-Path $candidato) {
                    $caminhoWinget = $candidato
                }
            }

            $argumentosWinget = 'install --id "' + $idPacoteWinget + '" -e --silent --accept-package-agreements --accept-source-agreements'

            # Inicia o winget em segundo plano (sem janela) usando
            # System.Diagnostics.Process diretamente, para nao bloquear a
            # interface.
            $psiInstalar = New-Object System.Diagnostics.ProcessStartInfo
            $psiInstalar.FileName = $caminhoWinget
            $psiInstalar.Arguments = $argumentosWinget
            $psiInstalar.UseShellExecute = $false
            $psiInstalar.CreateNoWindow = $true
            $psiInstalar.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

            $processoInstalar = New-Object System.Diagnostics.Process
            $processoInstalar.StartInfo = $psiInstalar
            $processoInstalar.Start() | Out-Null

            # OBS: o winget nao expoe um percentual confiavel quando a
            # saida e redirecionada (o progresso real dele usa caracteres
            # de controle de console, nao texto simples). Por isso a
            # barra cresce de forma simulada e suave enquanto o processo
            # roda - ficando "presa" em 90% ate o winget realmente
            # terminar - e so entao completa para 100%.
            #
            # IMPORTANTE: variaveis soltas (ex: $processoConcluido = $true)
            # NAO persistem de um disparo do Tick para o outro dentro de
            # um .GetNewClosure() - cada disparo roda em um escopo novo.
            # Por isso o estado fica guardado em um Hashtable: mutar uma
            # propriedade de um objeto (referencia) persiste corretamente,
            # diferente de reatribuir uma variavel.
            # Mesma correcao aplicada em outros pontos do arquivo (Java,
            # WinRAR): .GetNewClosure(), usado no timer logo abaixo,
            # isola o scriptblock - ele so enxerga VARIAVEIS capturadas,
            # nao funcoes chamadas pelo nome ("function ..."). Por isso
            # capturamos aqui as funcoes de deteccao do Firefox como
            # referencias de scriptblock, para chama-las com "&" dentro
            # do timer em vez de pelo nome direto.
            $refGetFirefoxExePath = ${function:Get-FirefoxExePath}
            $refGetFirefoxUninstallInfo = ${function:Get-FirefoxUninstallInfo}

            $estadoInstalacao = @{
                Concluido        = $false
                TicksAteFechar   = 0
                ProcessoSaiu     = $false
                TicksVerificacao = 0
            }
            $ticksParaFechar     = 7    # 7 x 200ms = 1,4s apos concluir
            # O winget pode retornar codigo 0 (sucesso) antes mesmo do
            # instalador do Firefox terminar de gravar o exe/registro em
            # disco (o setup se desanexa do processo do winget). Por isso,
            # depois do ExitCode 0, ainda esperamos ATE 5s tentando
            # detectar o navegador de verdade antes de dar a instalacao
            # como concluida - e so nao travamos pra sempre porque ha
            # este limite de seguranca.
            $ticksMaxVerificacao = 25   # 25 x 200ms = 5s

            $timerInstalar = New-Object System.Windows.Forms.Timer
            $timerInstalar.Interval = 200

            $timerInstalar.Add_Tick({
                if (-not $estadoInstalacao.Concluido) {

                    if (-not $estadoInstalacao.ProcessoSaiu) {
                        if ($processoInstalar.HasExited) {
                            $estadoInstalacao.ProcessoSaiu = $true
                        } elseif ((-not $formProgresso.IsDisposed) -and ($barraProgresso.Value -lt 90)) {
                            $incremento = Get-Random -Minimum 2 -Maximum 6
                            $novoValor = $barraProgresso.Value + $incremento
                            if ($novoValor -gt 90) { $novoValor = 90 }
                            $barraProgresso.Value = $novoValor
                            $labelPercentual.Text = "$novoValor%"
                        }
                    }

                    if ($estadoInstalacao.ProcessoSaiu) {
                        if ($processoInstalar.ExitCode -ne 0) {
                            $estadoInstalacao.Concluido = $true
                            $labelStatusFirefox.Text = "winget terminou com o codigo $($processoInstalar.ExitCode)."
                            if (-not $formProgresso.IsDisposed) {
                                $labelProgresso.Text = "Falha na instalacao."
                                $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
                                $labelPercentual.Text = "Codigo $($processoInstalar.ExitCode)"
                            }
                            $botaoInstalarFirefox.Enabled = $true
                            $botaoDesinstalarFirefox.Enabled = $true
                        } else {
                            # winget disse que deu certo: so consideramos
                            # REALMENTE instalado quando conseguirmos
                            # detectar o Firefox (exe ou registro), em vez
                            # de confiar cegamente no codigo de saida.
                            $detectado = (& $refGetFirefoxExePath) -or (& $refGetFirefoxUninstallInfo)
                            $estadoInstalacao.TicksVerificacao++

                            if ($detectado -or ($estadoInstalacao.TicksVerificacao -ge $ticksMaxVerificacao)) {
                                $estadoInstalacao.Concluido = $true
                                $labelStatusFirefox.Text = "Firefox instalado com sucesso."
                                if (-not $formProgresso.IsDisposed) {
                                    $barraProgresso.Value = 100
                                    $labelPercentual.Text = "100%"
                                    $labelProgresso.Text = "Instalado com sucesso!"
                                    $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 60)
                                }
                                # Agora que o Firefox foi instalado, troca o icone de
                                # reserva pelo icone oficial extraido do executavel.
                                if (-not $picLogoFirefox.IsDisposed) {
                                    $picLogoFirefox.Image = & $refLogoFirefoxOficial
                                }

                                # Instalado com sucesso: some com o botao Instalar e
                                # mostra somente o Desinstalar, no lugar dele.
                                if (-not $botaoInstalarFirefox.IsDisposed) {
                                    $botaoInstalarFirefox.Visible = $false
                                }
                                if (-not $chkSelecionarFirefox.IsDisposed) {
                                    $chkSelecionarFirefox.Checked = $false
                                    $chkSelecionarFirefox.Visible = $false
                                }
                                if (-not $botaoDesinstalarFirefox.IsDisposed) {
                                    $botaoDesinstalarFirefox.Location = New-Object System.Drawing.Point($colFirefoxCtrlX, $botaoDesinstalarFirefox.Location.Y)
                                    $botaoDesinstalarFirefox.Visible = $true
                                }

                                $botaoInstalarFirefox.Enabled = $true
                                $botaoDesinstalarFirefox.Enabled = $true

                                # Atualiza a tela inteira de navegadores para
                                # refletir o novo estado (recem-instalado).
                                $botaoNavegadores.PerformClick()
                            } elseif (-not $formProgresso.IsDisposed) {
                                # Ainda esperando o SO confirmar: nao trava
                                # em 90% nem pula pra 100% cedo demais.
                                $barraProgresso.Value = 95
                                $labelPercentual.Text = "95%"
                                $labelProgresso.Text = "Finalizando instalacao..."
                            }
                        }
                    }

                } else {
                    # Instalacao ja concluida: mantem o resultado visivel
                    # por alguns ticks e entao fecha o pop-up sozinho.
                    $estadoInstalacao.TicksAteFechar++
                    if ($estadoInstalacao.TicksAteFechar -ge $ticksParaFechar) {
                        $timerInstalar.Stop()
                        $timerInstalar.Dispose()
                        if (-not $formProgresso.IsDisposed) {
                            $formProgresso.Close()
                            $formProgresso.Dispose()
                        }
                    }
                }
            }.GetNewClosure())

            $timerInstalar.Start()
        } catch {
            $formProgresso.Close()
            $formProgresso.Dispose()
            $labelStatusFirefox.Text = "Erro ao instalar: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show(
                "Falha ao instalar o Firefox:`n`n$($_.Exception.Message)",
                "Erro na instalacao",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $botaoInstalarFirefox.Enabled = $true
            $botaoDesinstalarFirefox.Enabled = $true
        }
    }.GetNewClosure())

    $botaoDesinstalarFirefox.Add_Click({
        $botaoInstalarFirefox.Enabled = $false
        $botaoDesinstalarFirefox.Enabled = $false
        $labelStatusFirefox.Text = "Procurando desinstalador do Firefox..."
        [System.Windows.Forms.Application]::DoEvents()

        try {
            # O winget --silent as vezes ainda abre a tela do desinstalador
            # do Firefox, pois depende de como o manifesto do pacote mapeia
            # o modo silencioso. Por isso chamamos diretamente o desinstalador
            # registrado no Windows, garantindo o parametro /S do NSIS
            # (instalador do Firefox), que e o que realmente evita qualquer UI.
            #
            # OBS: a busca no registro fica embutida aqui (em vez de chamar a
            # funcao Get-FirefoxUninstallInfo) porque .GetNewClosure() isola o
            # scriptblock em um escopo que nao enxerga funcoes definidas no
            # script - apenas variaveis capturadas. Chamar uma funcao externa
            # daqui resultaria em "termo nao reconhecido".
            $caminhosRegistroUninstall = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )

            $info = $null
            foreach ($caminhoReg in $caminhosRegistroUninstall) {
                $itens = Get-ItemProperty -Path $caminhoReg -ErrorAction SilentlyContinue |
                         Where-Object { $_.DisplayName -like "Mozilla Firefox*" }
                if ($itens) {
                    $info = $itens | Select-Object -First 1
                    break
                }
            }

            if (-not $info) {
                $labelStatusFirefox.Text = "Firefox nao encontrado nesta maquina."
                $botaoInstalarFirefox.Enabled = $true
                $botaoDesinstalarFirefox.Enabled = $true
                return
            }

            # Muitos programas (Firefox incluso) expoem uma QuietUninstallString
            # no registro - o comando "oficial" para desinstalacao silenciosa,
            # ja com a flag correta. Preferimos ela quando existir. So usamos
            # a UninstallString "normal" (que abre a tela) como fallback,
            # e nesse caso adicionamos a flag manualmente.
            #
            # IMPORTANTE: o desinstalador do Firefox (helper.exe) usa a flag
            # "-ms" para rodar silencioso - "/S" e a flag do INSTALADOR, nao
            # do desinstalador. Usar "/S" no desinstalador nao tem efeito e
            # foi a causa da tela nao fechar / do codigo de saida estranho.
            if ($info.QuietUninstallString) {
                $comandoUninstall = $info.QuietUninstallString
                $precisaAdicionarFlag = $false
            } else {
                $comandoUninstall = $info.UninstallString
                $precisaAdicionarFlag = $true
            }

            if ($comandoUninstall -match '^\s*"([^"]+)"\s*(.*)$') {
                $executavel = $Matches[1]
                $argumentosExtras = $Matches[2].Trim()
            } else {
                $partes = $comandoUninstall -split ' ', 2
                $executavel = $partes[0]
                $argumentosExtras = if ($partes.Count -gt 1) { $partes[1] } else { "" }
            }

            if ($precisaAdicionarFlag -and ($argumentosExtras -notmatch '(?i)(^|\s)(-ms|/S|/quiet|/qn)(\s|$)')) {
                $argumentosExtras = ("$argumentosExtras -ms").Trim()
            }

            # Antes este comando montava um script e abria uma janela do
            # PowerShell visivel para acompanhar a desinstalacao. Agora o
            # processo roda 100% escondido (CreateNoWindow + WindowStyle
            # Hidden, igual ao botao Instalar) e quem mostra o andamento
            # e somente o pop-up com a barra de progresso abaixo.
            $labelStatusFirefox.Text = "Desinstalando (em segundo plano)..."
            [System.Windows.Forms.Application]::DoEvents()

            # ------------------------------------------------------
            # Mesma janela pop-up pequena usada no botao Instalar,
            # com barra de progresso, agora tambem para o Desinstalar.
            # ------------------------------------------------------
            $formProgresso = New-Object System.Windows.Forms.Form
            $formProgresso.Text = "Desinstalando Firefox"
            $formProgresso.Size = New-Object System.Drawing.Size(360, 150)
            $formProgresso.FormBorderStyle = "FixedDialog"
            $formProgresso.ControlBox = $false
            $formProgresso.MaximizeBox = $false
            $formProgresso.MinimizeBox = $false
            $formProgresso.StartPosition = "CenterScreen"
            $formProgresso.BackColor = [System.Drawing.Color]::White
            $formProgresso.TopMost = $true

            $labelProgresso = New-Object System.Windows.Forms.Label
            $labelProgresso.Text = "Desinstalando o Firefox, aguarde..."
            $labelProgresso.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $labelProgresso.TextAlign = "MiddleCenter"
            $labelProgresso.Location = New-Object System.Drawing.Point(15, 18)
            $labelProgresso.Size = New-Object System.Drawing.Size(310, 30)
            $formProgresso.Controls.Add($labelProgresso)

            $barraProgresso = New-Object System.Windows.Forms.ProgressBar
            $barraProgresso.Style = "Continuous"
            $barraProgresso.Minimum = 0
            $barraProgresso.Maximum = 100
            $barraProgresso.Value = 0
            $barraProgresso.Location = New-Object System.Drawing.Point(15, 58)
            $barraProgresso.Size = New-Object System.Drawing.Size(310, 24)
            $formProgresso.Controls.Add($barraProgresso)

            $labelPercentual = New-Object System.Windows.Forms.Label
            $labelPercentual.Text = "0%"
            $labelPercentual.Font = New-Object System.Drawing.Font("Segoe UI", 9)
            $labelPercentual.TextAlign = "MiddleCenter"
            $labelPercentual.Location = New-Object System.Drawing.Point(15, 88)
            $labelPercentual.Size = New-Object System.Drawing.Size(310, 20)
            $formProgresso.Controls.Add($labelPercentual)

            $formProgresso.Show($form)
            [System.Windows.Forms.Application]::DoEvents()

            if (-not (Test-Path -LiteralPath $executavel)) {
                throw "O executavel do desinstalador nao foi encontrado em: $executavel"
            }

            # Executa o desinstalador diretamente (sem abrir nenhum console),
            # usando System.Diagnostics.Process com CreateNoWindow + Hidden,
            # exatamente como o botao Instalar faz com o winget. Sem -Wait
            # aqui, para nao travar a interface: um Timer (abaixo) acompanha
            # quando o processo termina e vai enchendo a barra enquanto isso.
            $psiDesinstalar = New-Object System.Diagnostics.ProcessStartInfo
            $psiDesinstalar.FileName = $executavel
            $psiDesinstalar.Arguments = $argumentosExtras
            $psiDesinstalar.UseShellExecute = $false
            $psiDesinstalar.CreateNoWindow = $true
            $psiDesinstalar.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

            $processoDesinstalar = New-Object System.Diagnostics.Process
            $processoDesinstalar.StartInfo = $psiDesinstalar
            $processoDesinstalar.Start() | Out-Null

            $estadoDesinstalacao = @{
                Concluido      = $false
                TicksAteFechar = 0
            }
            $ticksParaFecharDesinstalar = 7   # 7 x 200ms = 1,4s apos concluir

            $timerDesinstalar = New-Object System.Windows.Forms.Timer
            $timerDesinstalar.Interval = 200

            $timerDesinstalar.Add_Tick({
                if (-not $estadoDesinstalacao.Concluido) {
                    if ($processoDesinstalar.HasExited) {
                        $estadoDesinstalacao.Concluido = $true

                        if ($processoDesinstalar.ExitCode -eq 0) {
                            $labelStatusFirefox.Text = "Firefox desinstalado com sucesso."
                            if (-not $formProgresso.IsDisposed) {
                                $barraProgresso.Value = 100
                                $labelPercentual.Text = "100%"
                                $labelProgresso.Text = "Desinstalado com sucesso!"
                                $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 60)
                            }

                            # Desinstalado com sucesso: some com o botao
                            # Desinstalar e mostra somente o Instalar, no
                            # lugar dele.
                            if (-not $botaoDesinstalarFirefox.IsDisposed) {
                                $botaoDesinstalarFirefox.Visible = $false
                            }
                            if (-not $chkSelecionarFirefox.IsDisposed) {
                                $chkSelecionarFirefox.Visible = $true
                            }
                            if (-not $botaoInstalarFirefox.IsDisposed) {
                                $botaoInstalarFirefox.Location = New-Object System.Drawing.Point($colFirefoxCtrlX, $botaoInstalarFirefox.Location.Y)
                                $botaoInstalarFirefox.Visible = $true
                            }

                            # Atualiza a tela inteira de navegadores para
                            # refletir o novo estado (recem-desinstalado).
                            $botaoNavegadores.PerformClick()
                        } else {
                            $labelStatusFirefox.Text = "Desinstalador terminou com o codigo $($processoDesinstalar.ExitCode)."
                            if (-not $formProgresso.IsDisposed) {
                                $labelProgresso.Text = "Falha na desinstalacao."
                                $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
                                $labelPercentual.Text = "Codigo $($processoDesinstalar.ExitCode)"
                            }
                        }

                        $botaoInstalarFirefox.Enabled = $true
                        $botaoDesinstalarFirefox.Enabled = $true
                    } else {
                        if ((-not $formProgresso.IsDisposed) -and ($barraProgresso.Value -lt 90)) {
                            $incremento = Get-Random -Minimum 2 -Maximum 6
                            $novoValor = $barraProgresso.Value + $incremento
                            if ($novoValor -gt 90) { $novoValor = 90 }
                            $barraProgresso.Value = $novoValor
                            $labelPercentual.Text = "$novoValor%"
                        }
                    }
                } else {
                    # Desinstalacao ja concluida: mantem o resultado visivel
                    # por alguns ticks e entao fecha o pop-up sozinho.
                    $estadoDesinstalacao.TicksAteFechar++
                    if ($estadoDesinstalacao.TicksAteFechar -ge $ticksParaFecharDesinstalar) {
                        $timerDesinstalar.Stop()
                        $timerDesinstalar.Dispose()
                        if (-not $formProgresso.IsDisposed) {
                            $formProgresso.Close()
                            $formProgresso.Dispose()
                        }
                    }
                }
            }.GetNewClosure())

            $timerDesinstalar.Start()
        } catch {
            if ($formProgresso -and (-not $formProgresso.IsDisposed)) {
                $formProgresso.Close()
                $formProgresso.Dispose()
            }
            $labelStatusFirefox.Text = "Erro ao desinstalar: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show(
                "Falha ao desinstalar o Firefox:`n`n$($_.Exception.Message)",
                "Erro na desinstalacao",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $botaoInstalarFirefox.Enabled = $true
            $botaoDesinstalarFirefox.Enabled = $true
        }
    }.GetNewClosure())

    # --------------------------------------------------------------
    # Coluna do Chrome: logo + botoes Instalar / Desinstalar, na
    # MESMA linha (mesmo $y) da coluna do Firefox acima, so que mais
    # a direita (colChromeLogoX / colChromeCtrlX).
    # --------------------------------------------------------------

    # Logo do Chrome (icone oficial - extraido do exe local ou baixado)
    $picLogoChrome = New-Object System.Windows.Forms.PictureBox
    $picLogoChrome.Size = New-Object System.Drawing.Size(72, 72)
    $picLogoChrome.Location = New-Object System.Drawing.Point($colChromeLogoX, $y)
    $picLogoChrome.SizeMode = "Zoom"
    $picLogoChrome.Image = Get-ChromeLogoBitmap
    $painelConteudo.Controls.Add($picLogoChrome)

    # Rotulo de status (fica ao lado da logo)
    $labelStatusChrome = New-Object System.Windows.Forms.Label
    $labelStatusChrome.Text = "Pronto."
    $labelStatusChrome.AutoSize = $true
    $labelStatusChrome.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $labelStatusChrome.Location = New-Object System.Drawing.Point($colChromeCtrlX, ($y + 8))
    $labelStatusChrome.MaximumSize = New-Object System.Drawing.Size(180, 0)
    $painelConteudo.Controls.Add($labelStatusChrome)

    # Botao Instalar - bem pequeno, cantos arredondados, ao lado do logo
    $botaoInstalarChrome = New-Object System.Windows.Forms.Button
    $botaoInstalarChrome.Text = "Instalar"
    $botaoInstalarChrome.Width = 56
    $botaoInstalarChrome.Height = 20
    $botaoInstalarChrome.FlatStyle = "Flat"
    $botaoInstalarChrome.FlatAppearance.BorderSize = 0
    $botaoInstalarChrome.BackColor = [System.Drawing.Color]::FromArgb(0, 153, 76)
    $botaoInstalarChrome.ForeColor = [System.Drawing.Color]::White
    $botaoInstalarChrome.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
    $botaoInstalarChrome.Location = New-Object System.Drawing.Point($colChromeCtrlX, ($y + 36))
    $painelConteudo.Controls.Add($botaoInstalarChrome)
    Set-BotaoCantosArredondados -Botao $botaoInstalarChrome -Raio 8

    # Botao Desinstalar (ao lado do Instalar)
    $botaoDesinstalarChrome = New-Object System.Windows.Forms.Button
    $botaoDesinstalarChrome.Text = "Desinstalar"
    $botaoDesinstalarChrome.Width = 66
    $botaoDesinstalarChrome.Height = 20
    $botaoDesinstalarChrome.FlatStyle = "Flat"
    $botaoDesinstalarChrome.FlatAppearance.BorderSize = 0
    $botaoDesinstalarChrome.BackColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
    $botaoDesinstalarChrome.ForeColor = [System.Drawing.Color]::White
    $botaoDesinstalarChrome.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
    $botaoDesinstalarChrome.Location = New-Object System.Drawing.Point(($colChromeCtrlX + 56 + 6), ($y + 36))
    $painelConteudo.Controls.Add($botaoDesinstalarChrome)
    Set-BotaoCantosArredondados -Botao $botaoDesinstalarChrome -Raio 8

    # Mostra so o botao que faz sentido para o estado atual (mesma
    # regra usada acima para o Firefox).
    $chromeJaInstalado = $false
    if (Get-ChromeExePath) {
        $chromeJaInstalado = $true
    } elseif (Get-ChromeUninstallInfo) {
        $chromeJaInstalado = $true
    }

    if ($chromeJaInstalado) {
        $botaoInstalarChrome.Visible = $false
        $botaoDesinstalarChrome.Location = New-Object System.Drawing.Point($colChromeCtrlX, $botaoDesinstalarChrome.Location.Y)
        $chkSelecionarChrome.Visible = $false
    } else {
        $botaoDesinstalarChrome.Visible = $false
    }

    # Identificador do pacote no winget (App Installer)
    $idPacoteWingetChrome = "Google.Chrome"

    $botaoInstalarChrome.Add_Click({
        $botaoInstalarChrome.Enabled = $false
        $botaoDesinstalarChrome.Enabled = $false
        $labelStatusChrome.Text = "Instalando Chrome..."
        [System.Windows.Forms.Application]::DoEvents()

        $formProgresso = New-Object System.Windows.Forms.Form
        $formProgresso.Text = "Instalando Chrome"
        $formProgresso.Size = New-Object System.Drawing.Size(360, 150)
        $formProgresso.FormBorderStyle = "FixedDialog"
        $formProgresso.ControlBox = $false
        $formProgresso.MaximizeBox = $false
        $formProgresso.MinimizeBox = $false
        $formProgresso.StartPosition = "CenterScreen"
        $formProgresso.BackColor = [System.Drawing.Color]::White
        $formProgresso.TopMost = $true

        $labelProgresso = New-Object System.Windows.Forms.Label
        $labelProgresso.Text = "Instalando o Chrome, aguarde..."
        $labelProgresso.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $labelProgresso.TextAlign = "MiddleCenter"
        $labelProgresso.Location = New-Object System.Drawing.Point(15, 18)
        $labelProgresso.Size = New-Object System.Drawing.Size(310, 30)
        $formProgresso.Controls.Add($labelProgresso)

        $barraProgresso = New-Object System.Windows.Forms.ProgressBar
        $barraProgresso.Style = "Continuous"
        $barraProgresso.Minimum = 0
        $barraProgresso.Maximum = 100
        $barraProgresso.Value = 0
        $barraProgresso.Location = New-Object System.Drawing.Point(15, 58)
        $barraProgresso.Size = New-Object System.Drawing.Size(310, 24)
        $formProgresso.Controls.Add($barraProgresso)

        $labelPercentual = New-Object System.Windows.Forms.Label
        $labelPercentual.Text = "0%"
        $labelPercentual.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $labelPercentual.TextAlign = "MiddleCenter"
        $labelPercentual.Location = New-Object System.Drawing.Point(15, 88)
        $labelPercentual.Size = New-Object System.Drawing.Size(310, 20)
        $formProgresso.Controls.Add($labelPercentual)

        $formProgresso.Show($form)
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
            $caminhoWinget = "winget"

            if ($wingetCmd) {
                $caminhoWinget = $wingetCmd.Source
            } else {
                $candidato = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
                if (Test-Path $candidato) {
                    $caminhoWinget = $candidato
                }
            }

            $argumentosWinget = 'install --id "' + $idPacoteWingetChrome + '" -e --silent --accept-package-agreements --accept-source-agreements'

            $psiInstalar = New-Object System.Diagnostics.ProcessStartInfo
            $psiInstalar.FileName = $caminhoWinget
            $psiInstalar.Arguments = $argumentosWinget
            $psiInstalar.UseShellExecute = $false
            $psiInstalar.CreateNoWindow = $true
            $psiInstalar.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

            $processoInstalar = New-Object System.Diagnostics.Process
            $processoInstalar.StartInfo = $psiInstalar
            $processoInstalar.Start() | Out-Null

            # Mesma correcao aplicada em outros pontos do arquivo: o
            # .GetNewClosure() do timer logo abaixo isola o scriptblock
            # e nao enxerga funcoes chamadas pelo nome, so variaveis
            # capturadas - por isso as funcoes de deteccao do Chrome sao
            # capturadas aqui como referencias de scriptblock.
            $refGetChromeExePath = ${function:Get-ChromeExePath}
            $refGetChromeUninstallInfo = ${function:Get-ChromeUninstallInfo}

            $estadoInstalacao = @{
                Concluido        = $false
                TicksAteFechar   = 0
                ProcessoSaiu     = $false
                TicksVerificacao = 0
            }
            $ticksParaFechar = 7
            # O winget do Chrome usa um stub que aciona o Google Update em
            # segundo plano - o winget pode retornar codigo 0 antes do
            # chrome.exe realmente existir no disco. Por isso esperamos
            # ate 5s tentando detectar o navegador de verdade antes de dar
            # a instalacao como concluida.
            $ticksMaxVerificacao = 25   # 25 x 200ms = 5s

            $timerInstalar = New-Object System.Windows.Forms.Timer
            $timerInstalar.Interval = 200

            $timerInstalar.Add_Tick({
                if (-not $estadoInstalacao.Concluido) {

                    if (-not $estadoInstalacao.ProcessoSaiu) {
                        if ($processoInstalar.HasExited) {
                            $estadoInstalacao.ProcessoSaiu = $true
                        } elseif ((-not $formProgresso.IsDisposed) -and ($barraProgresso.Value -lt 90)) {
                            $incremento = Get-Random -Minimum 2 -Maximum 6
                            $novoValor = $barraProgresso.Value + $incremento
                            if ($novoValor -gt 90) { $novoValor = 90 }
                            $barraProgresso.Value = $novoValor
                            $labelPercentual.Text = "$novoValor%"
                        }
                    }

                    if ($estadoInstalacao.ProcessoSaiu) {
                        if ($processoInstalar.ExitCode -ne 0) {
                            $estadoInstalacao.Concluido = $true
                            $labelStatusChrome.Text = "winget terminou com o codigo $($processoInstalar.ExitCode)."
                            if (-not $formProgresso.IsDisposed) {
                                $labelProgresso.Text = "Falha na instalacao."
                                $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
                                $labelPercentual.Text = "Codigo $($processoInstalar.ExitCode)"
                            }
                            $botaoInstalarChrome.Enabled = $true
                            $botaoDesinstalarChrome.Enabled = $true
                        } else {
                            # winget disse que deu certo: so consideramos
                            # REALMENTE instalado quando conseguirmos
                            # detectar o Chrome (exe ou registro).
                            $detectado = (& $refGetChromeExePath) -or (& $refGetChromeUninstallInfo)
                            $estadoInstalacao.TicksVerificacao++

                            if ($detectado -or ($estadoInstalacao.TicksVerificacao -ge $ticksMaxVerificacao)) {
                                $estadoInstalacao.Concluido = $true
                                $labelStatusChrome.Text = "Chrome instalado com sucesso."
                                if (-not $formProgresso.IsDisposed) {
                                    $barraProgresso.Value = 100
                                    $labelPercentual.Text = "100%"
                                    $labelProgresso.Text = "Instalado com sucesso!"
                                    $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 60)
                                }
                                # Agora que o Chrome foi instalado, troca o icone de
                                # reserva/baixado pelo icone oficial extraido do executavel.
                                if (-not $picLogoChrome.IsDisposed) {
                                    $picLogoChrome.Image = & $refLogoChromeOficial
                                }

                                # Instalado com sucesso: some com o botao Instalar e
                                # mostra somente o Desinstalar, no lugar dele.
                                if (-not $botaoInstalarChrome.IsDisposed) {
                                    $botaoInstalarChrome.Visible = $false
                                }
                                if (-not $chkSelecionarChrome.IsDisposed) {
                                    $chkSelecionarChrome.Checked = $false
                                    $chkSelecionarChrome.Visible = $false
                                }
                                if (-not $botaoDesinstalarChrome.IsDisposed) {
                                    $botaoDesinstalarChrome.Location = New-Object System.Drawing.Point($colChromeCtrlX, $botaoDesinstalarChrome.Location.Y)
                                    $botaoDesinstalarChrome.Visible = $true
                                }

                                $botaoInstalarChrome.Enabled = $true
                                $botaoDesinstalarChrome.Enabled = $true

                                # Atualiza a tela inteira de navegadores para
                                # refletir o novo estado (recem-instalado).
                                $botaoNavegadores.PerformClick()
                            } elseif (-not $formProgresso.IsDisposed) {
                                $barraProgresso.Value = 95
                                $labelPercentual.Text = "95%"
                                $labelProgresso.Text = "Finalizando instalacao..."
                            }
                        }
                    }

                } else {
                    $estadoInstalacao.TicksAteFechar++
                    if ($estadoInstalacao.TicksAteFechar -ge $ticksParaFechar) {
                        $timerInstalar.Stop()
                        $timerInstalar.Dispose()
                        if (-not $formProgresso.IsDisposed) {
                            $formProgresso.Close()
                            $formProgresso.Dispose()
                        }
                    }
                }
            }.GetNewClosure())

            $timerInstalar.Start()
        } catch {
            $formProgresso.Close()
            $formProgresso.Dispose()
            $labelStatusChrome.Text = "Erro ao instalar: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show(
                "Falha ao instalar o Chrome:`n`n$($_.Exception.Message)",
                "Erro na instalacao",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $botaoInstalarChrome.Enabled = $true
            $botaoDesinstalarChrome.Enabled = $true
        }
    }.GetNewClosure())

    $botaoDesinstalarChrome.Add_Click({
        $botaoInstalarChrome.Enabled = $false
        $botaoDesinstalarChrome.Enabled = $false
        $labelStatusChrome.Text = "Desinstalando Chrome..."
        [System.Windows.Forms.Application]::DoEvents()

        $formProgresso = New-Object System.Windows.Forms.Form
        $formProgresso.Text = "Desinstalando Chrome"
        $formProgresso.Size = New-Object System.Drawing.Size(360, 150)
        $formProgresso.FormBorderStyle = "FixedDialog"
        $formProgresso.ControlBox = $false
        $formProgresso.MaximizeBox = $false
        $formProgresso.MinimizeBox = $false
        $formProgresso.StartPosition = "CenterScreen"
        $formProgresso.BackColor = [System.Drawing.Color]::White
        $formProgresso.TopMost = $true

        $labelProgresso = New-Object System.Windows.Forms.Label
        $labelProgresso.Text = "Desinstalando o Chrome, aguarde..."
        $labelProgresso.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $labelProgresso.TextAlign = "MiddleCenter"
        $labelProgresso.Location = New-Object System.Drawing.Point(15, 18)
        $labelProgresso.Size = New-Object System.Drawing.Size(310, 30)
        $formProgresso.Controls.Add($labelProgresso)

        $barraProgresso = New-Object System.Windows.Forms.ProgressBar
        $barraProgresso.Style = "Continuous"
        $barraProgresso.Minimum = 0
        $barraProgresso.Maximum = 100
        $barraProgresso.Value = 0
        $barraProgresso.Location = New-Object System.Drawing.Point(15, 58)
        $barraProgresso.Size = New-Object System.Drawing.Size(310, 24)
        $formProgresso.Controls.Add($barraProgresso)

        $labelPercentual = New-Object System.Windows.Forms.Label
        $labelPercentual.Text = "0%"
        $labelPercentual.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $labelPercentual.TextAlign = "MiddleCenter"
        $labelPercentual.Location = New-Object System.Drawing.Point(15, 88)
        $labelPercentual.Size = New-Object System.Drawing.Size(310, 20)
        $formProgresso.Controls.Add($labelPercentual)

        $formProgresso.Show($form)
        [System.Windows.Forms.Application]::DoEvents()

        try {
            # Mesma resolucao de caminho do winget usada no botao Instalar:
            # o "winget" e um App Execution Alias que nem sempre e
            # encontrado diretamente (ex: rodando como Administrador).
            $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
            $caminhoWinget = "winget"

            if ($wingetCmd) {
                $caminhoWinget = $wingetCmd.Source
            } else {
                $candidato = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
                if (Test-Path $candidato) {
                    $caminhoWinget = $candidato
                }
            }

            # Comando pedido: winget uninstall --id Google.Chrome
            # ("-e" garante o ID exato e "--silent" evita qualquer tela,
            # ja que o processo roda 100% escondido, sem console).
            $argumentosWinget = 'uninstall --id "' + $idPacoteWingetChrome + '" -e --silent --accept-source-agreements'

            $psiDesinstalar = New-Object System.Diagnostics.ProcessStartInfo
            $psiDesinstalar.FileName = $caminhoWinget
            $psiDesinstalar.Arguments = $argumentosWinget
            $psiDesinstalar.UseShellExecute = $false
            $psiDesinstalar.CreateNoWindow = $true
            $psiDesinstalar.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

            $processoDesinstalar = New-Object System.Diagnostics.Process
            $processoDesinstalar.StartInfo = $psiDesinstalar
            $processoDesinstalar.Start() | Out-Null

            $estadoDesinstalacao = @{
                Concluido      = $false
                TicksAteFechar = 0
            }
            $ticksParaFecharDesinstalar = 7

            $timerDesinstalar = New-Object System.Windows.Forms.Timer
            $timerDesinstalar.Interval = 200

            $timerDesinstalar.Add_Tick({
                if (-not $estadoDesinstalacao.Concluido) {
                    if ($processoDesinstalar.HasExited) {
                        $estadoDesinstalacao.Concluido = $true

                        if ($processoDesinstalar.ExitCode -eq 0) {
                            $labelStatusChrome.Text = "Chrome desinstalado com sucesso."
                            if (-not $formProgresso.IsDisposed) {
                                $barraProgresso.Value = 100
                                $labelPercentual.Text = "100%"
                                $labelProgresso.Text = "Desinstalado com sucesso!"
                                $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 60)
                            }

                            # Desinstalado com sucesso: some com o botao
                            # Desinstalar e mostra somente o Instalar, no
                            # lugar dele.
                            if (-not $botaoDesinstalarChrome.IsDisposed) {
                                $botaoDesinstalarChrome.Visible = $false
                            }
                            if (-not $chkSelecionarChrome.IsDisposed) {
                                $chkSelecionarChrome.Visible = $true
                            }
                            if (-not $botaoInstalarChrome.IsDisposed) {
                                $botaoInstalarChrome.Location = New-Object System.Drawing.Point($colChromeCtrlX, $botaoInstalarChrome.Location.Y)
                                $botaoInstalarChrome.Visible = $true
                            }

                            # Atualiza a tela inteira de navegadores para
                            # refletir o novo estado (recem-desinstalado).
                            $botaoNavegadores.PerformClick()
                        } else {
                            $labelStatusChrome.Text = "winget terminou com o codigo $($processoDesinstalar.ExitCode)."
                            if (-not $formProgresso.IsDisposed) {
                                $labelProgresso.Text = "Falha na desinstalacao."
                                $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
                                $labelPercentual.Text = "Codigo $($processoDesinstalar.ExitCode)"
                            }
                        }

                        $botaoInstalarChrome.Enabled = $true
                        $botaoDesinstalarChrome.Enabled = $true
                    } else {
                        if ((-not $formProgresso.IsDisposed) -and ($barraProgresso.Value -lt 90)) {
                            $incremento = Get-Random -Minimum 2 -Maximum 6
                            $novoValor = $barraProgresso.Value + $incremento
                            if ($novoValor -gt 90) { $novoValor = 90 }
                            $barraProgresso.Value = $novoValor
                            $labelPercentual.Text = "$novoValor%"
                        }
                    }
                } else {
                    $estadoDesinstalacao.TicksAteFechar++
                    if ($estadoDesinstalacao.TicksAteFechar -ge $ticksParaFecharDesinstalar) {
                        $timerDesinstalar.Stop()
                        $timerDesinstalar.Dispose()
                        if (-not $formProgresso.IsDisposed) {
                            $formProgresso.Close()
                            $formProgresso.Dispose()
                        }
                    }
                }
            }.GetNewClosure())

            $timerDesinstalar.Start()
        } catch {
            if ($formProgresso -and (-not $formProgresso.IsDisposed)) {
                $formProgresso.Close()
                $formProgresso.Dispose()
            }
            $labelStatusChrome.Text = "Erro ao desinstalar: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show(
                "Falha ao desinstalar o Chrome:`n`n$($_.Exception.Message)",
                "Erro na desinstalacao",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $botaoInstalarChrome.Enabled = $true
            $botaoDesinstalarChrome.Enabled = $true
        }
    }.GetNewClosure())

    # --------------------------------------------------------------
    # Coluna do Brave: logo + botoes Instalar / Desinstalar, na
    # 3a coluna (colBraveLogoX / colBraveCtrlX), na MESMA linha do
    # Firefox e do Chrome.
    # --------------------------------------------------------------

    # Logo do Brave (icone oficial - extraido do exe local ou baixado)
    $picLogoBrave = New-Object System.Windows.Forms.PictureBox
    $picLogoBrave.Size = New-Object System.Drawing.Size(72, 72)
    $picLogoBrave.Location = New-Object System.Drawing.Point($colBraveLogoX, $y)
    $picLogoBrave.SizeMode = "Zoom"
    $picLogoBrave.Image = Get-BraveLogoBitmap
    $painelConteudo.Controls.Add($picLogoBrave)

    # Rotulo de status (fica ao lado da logo)
    $labelStatusBrave = New-Object System.Windows.Forms.Label
    $labelStatusBrave.Text = "Pronto."
    $labelStatusBrave.AutoSize = $true
    $labelStatusBrave.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $labelStatusBrave.Location = New-Object System.Drawing.Point($colBraveCtrlX, ($y + 8))
    $labelStatusBrave.MaximumSize = New-Object System.Drawing.Size(180, 0)
    $painelConteudo.Controls.Add($labelStatusBrave)

    # Botao Instalar - bem pequeno, cantos arredondados, ao lado do logo
    $botaoInstalarBrave = New-Object System.Windows.Forms.Button
    $botaoInstalarBrave.Text = "Instalar"
    $botaoInstalarBrave.Width = 56
    $botaoInstalarBrave.Height = 20
    $botaoInstalarBrave.FlatStyle = "Flat"
    $botaoInstalarBrave.FlatAppearance.BorderSize = 0
    $botaoInstalarBrave.BackColor = [System.Drawing.Color]::FromArgb(0, 153, 76)
    $botaoInstalarBrave.ForeColor = [System.Drawing.Color]::White
    $botaoInstalarBrave.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
    $botaoInstalarBrave.Location = New-Object System.Drawing.Point($colBraveCtrlX, ($y + 36))
    $painelConteudo.Controls.Add($botaoInstalarBrave)
    Set-BotaoCantosArredondados -Botao $botaoInstalarBrave -Raio 8

    # Botao Desinstalar (ao lado do Instalar)
    $botaoDesinstalarBrave = New-Object System.Windows.Forms.Button
    $botaoDesinstalarBrave.Text = "Desinstalar"
    $botaoDesinstalarBrave.Width = 66
    $botaoDesinstalarBrave.Height = 20
    $botaoDesinstalarBrave.FlatStyle = "Flat"
    $botaoDesinstalarBrave.FlatAppearance.BorderSize = 0
    $botaoDesinstalarBrave.BackColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
    $botaoDesinstalarBrave.ForeColor = [System.Drawing.Color]::White
    $botaoDesinstalarBrave.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
    $botaoDesinstalarBrave.Location = New-Object System.Drawing.Point(($colBraveCtrlX + 56 + 6), ($y + 36))
    $painelConteudo.Controls.Add($botaoDesinstalarBrave)
    Set-BotaoCantosArredondados -Botao $botaoDesinstalarBrave -Raio 8

    # Avanca $y para o que vier depois na tela (mesma logica usada
    # apos a linha Firefox/Chrome).
    $y += 90

    # Mostra so o botao que faz sentido para o estado atual (mesma
    # regra usada acima para Firefox/Chrome).
    $braveJaInstalado = $false
    if (Get-BraveExePath) {
        $braveJaInstalado = $true
    } elseif (Get-BraveUninstallInfo) {
        $braveJaInstalado = $true
    }

    if ($braveJaInstalado) {
        $botaoInstalarBrave.Visible = $false
        $botaoDesinstalarBrave.Location = New-Object System.Drawing.Point($colBraveCtrlX, $botaoDesinstalarBrave.Location.Y)
        $chkSelecionarBrave.Visible = $false
    } else {
        $botaoDesinstalarBrave.Visible = $false
    }

    # --------------------------------------------------------------
    # Botao unico para instalacao multipla: instala de uma vez todos
    # os navegadores cujas caixas de selecao estiverem marcadas. Ele
    # simplesmente aciona o clique do botao "Instalar" de cada um dos
    # navegadores marcados (reaproveitando toda a logica de instalacao
    # e a janela de progresso que ja existem para cada navegador), entao
    # nao duplica codigo nem risco de comportamento diferente entre
    # instalar "um por um" ou "varios de uma vez".
    # --------------------------------------------------------------
    $botaoInstalarSelecionados = New-Object System.Windows.Forms.Button
    $botaoInstalarSelecionados.Text = "Instalar selecionados"
    $botaoInstalarSelecionados.AutoSize = $true
    $botaoInstalarSelecionados.Height = 28
    $botaoInstalarSelecionados.Padding = New-Object System.Windows.Forms.Padding(10, 0, 10, 0)
    $botaoInstalarSelecionados.FlatStyle = "Flat"
    $botaoInstalarSelecionados.FlatAppearance.BorderSize = 0
    $botaoInstalarSelecionados.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $botaoInstalarSelecionados.ForeColor = [System.Drawing.Color]::White
    $botaoInstalarSelecionados.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $botaoInstalarSelecionados.Location = New-Object System.Drawing.Point($colFirefoxLogoX, ($y + 66))
    $painelConteudo.Controls.Add($botaoInstalarSelecionados)
    Set-BotaoCantosArredondados -Botao $botaoInstalarSelecionados -Raio 8

    $botaoInstalarSelecionados.Add_Click({
        $algumaMarcada = $false

        if ((-not $chkSelecionarFirefox.IsDisposed) -and $chkSelecionarFirefox.Visible -and $chkSelecionarFirefox.Checked -and $botaoInstalarFirefox.Visible) {
            $algumaMarcada = $true
            $botaoInstalarFirefox.PerformClick()
        }
        if ((-not $chkSelecionarChrome.IsDisposed) -and $chkSelecionarChrome.Visible -and $chkSelecionarChrome.Checked -and $botaoInstalarChrome.Visible) {
            $algumaMarcada = $true
            $botaoInstalarChrome.PerformClick()
        }
        if ((-not $chkSelecionarBrave.IsDisposed) -and $chkSelecionarBrave.Visible -and $chkSelecionarBrave.Checked -and $botaoInstalarBrave.Visible) {
            $algumaMarcada = $true
            $botaoInstalarBrave.PerformClick()
        }

        if (-not $algumaMarcada) {
            [System.Windows.Forms.MessageBox]::Show(
                "Marque a caixa `"Selecionar`" de ao menos um navegador antes de clicar em Instalar selecionados.",
                "Nenhum navegador selecionado",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
    })

    # Identificador do pacote no winget (App Installer)
    $idPacoteWingetBrave = "Brave.Brave"

    $botaoInstalarBrave.Add_Click({
        $botaoInstalarBrave.Enabled = $false
        $botaoDesinstalarBrave.Enabled = $false
        $labelStatusBrave.Text = "Instalando Brave..."
        [System.Windows.Forms.Application]::DoEvents()

        $formProgresso = New-Object System.Windows.Forms.Form
        $formProgresso.Text = "Instalando Brave"
        $formProgresso.Size = New-Object System.Drawing.Size(360, 150)
        $formProgresso.FormBorderStyle = "FixedDialog"
        $formProgresso.ControlBox = $false
        $formProgresso.MaximizeBox = $false
        $formProgresso.MinimizeBox = $false
        $formProgresso.StartPosition = "CenterScreen"
        $formProgresso.BackColor = [System.Drawing.Color]::White
        $formProgresso.TopMost = $true

        $labelProgresso = New-Object System.Windows.Forms.Label
        $labelProgresso.Text = "Instalando o Brave, aguarde..."
        $labelProgresso.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $labelProgresso.TextAlign = "MiddleCenter"
        $labelProgresso.Location = New-Object System.Drawing.Point(15, 18)
        $labelProgresso.Size = New-Object System.Drawing.Size(310, 30)
        $formProgresso.Controls.Add($labelProgresso)

        $barraProgresso = New-Object System.Windows.Forms.ProgressBar
        $barraProgresso.Style = "Continuous"
        $barraProgresso.Minimum = 0
        $barraProgresso.Maximum = 100
        $barraProgresso.Value = 0
        $barraProgresso.Location = New-Object System.Drawing.Point(15, 58)
        $barraProgresso.Size = New-Object System.Drawing.Size(310, 24)
        $formProgresso.Controls.Add($barraProgresso)

        $labelPercentual = New-Object System.Windows.Forms.Label
        $labelPercentual.Text = "0%"
        $labelPercentual.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $labelPercentual.TextAlign = "MiddleCenter"
        $labelPercentual.Location = New-Object System.Drawing.Point(15, 88)
        $labelPercentual.Size = New-Object System.Drawing.Size(310, 20)
        $formProgresso.Controls.Add($labelPercentual)

        $formProgresso.Show($form)
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
            $caminhoWinget = $null

            if ($wingetCmd) {
                $caminhoWinget = $wingetCmd.Source
            } else {
                $candidato = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
                if (Test-Path $candidato) {
                    $caminhoWinget = $candidato
                }
            }

            if (-not $caminhoWinget) {
                throw "winget (App Installer) nao foi encontrado nesta maquina. Instale o 'App Installer' pela Microsoft Store e tente novamente."
            }

            # O instalador silencioso do Brave espera indefinidamente por
            # uma confirmacao para fechar o navegador (ou o atualizador)
            # se algum desses processos ja estiver rodando - e como essa
            # janela de confirmacao fica oculta (CreateNoWindow/Hidden),
            # ninguem nunca clica nela e o processo trava para sempre.
            # Por isso encerramos esses processos antes de instalar.
            $processosBraveConflitantes = @("brave", "brave_installer", "BraveCrashHandler", "BraveCrashHandler64", "BraveUpdate")
            foreach ($nomeProcesso in $processosBraveConflitantes) {
                Get-Process -Name $nomeProcesso -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }

            $argumentosWinget = 'install --id "' + $idPacoteWingetBrave + '" -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity'

            $psiInstalar = New-Object System.Diagnostics.ProcessStartInfo
            $psiInstalar.FileName = $caminhoWinget
            $psiInstalar.Arguments = $argumentosWinget
            $psiInstalar.UseShellExecute = $false
            $psiInstalar.CreateNoWindow = $true
            $psiInstalar.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            $psiInstalar.RedirectStandardOutput = $true
            $psiInstalar.RedirectStandardError = $true

            $processoInstalar = New-Object System.Diagnostics.Process
            $processoInstalar.StartInfo = $psiInstalar
            $processoInstalar.EnableRaisingEvents = $true

            # Acumula a saida real do winget (stdout+stderr) de forma
            # assincrona - se so lermos depois do processo terminar,
            # o buffer pode encher e travar o winget para sempre.
            $sbSaidaInstalar = New-Object System.Text.StringBuilder
            $handlerSaida = {
                if ($EventArgs.Data) { [void]$sbSaidaInstalar.AppendLine($EventArgs.Data) }
            }
            Register-ObjectEvent -InputObject $processoInstalar -EventName OutputDataReceived -Action $handlerSaida | Out-Null
            Register-ObjectEvent -InputObject $processoInstalar -EventName ErrorDataReceived -Action $handlerSaida | Out-Null

            $processoInstalar.Start() | Out-Null
            $processoInstalar.BeginOutputReadLine()
            $processoInstalar.BeginErrorReadLine()

            # Mesma correcao aplicada em outros pontos do arquivo: o
            # .GetNewClosure() do timer logo abaixo isola o scriptblock
            # e nao enxerga funcoes chamadas pelo nome, so variaveis
            # capturadas - por isso as funcoes usadas dentro do timer
            # (deteccao do Brave e descricao de erro do winget) sao
            # capturadas aqui como referencias de scriptblock.
            $refGetBraveExePath = ${function:Get-BraveExePath}
            $refGetBraveUninstallInfo = ${function:Get-BraveUninstallInfo}
            $refGetDescricaoErroWingetBrave = ${function:Get-DescricaoErroWinget}

            $estadoInstalacao = @{
                Concluido        = $false
                TicksAteFechar   = 0
                TicksDecorridos  = 0
                ProcessoSaiu     = $false
                TicksVerificacao = 0
            }
            $ticksParaFechar = 7
            # 200ms x 900 = 3 minutos. Generoso (o download pode demorar
            # em conexoes lentas), mas finito - se passar disso, algo
            # travou de verdade e o processo precisa ser morto, em vez
            # de deixar a barra presa em 90% para sempre.
            $ticksTimeout = 900
            # O winget pode retornar codigo 0 antes do instalador do Brave
            # (que se desanexa) terminar de gravar o exe/registro em
            # disco. Por isso, depois do ExitCode 0, ainda esperamos ate
            # 5s tentando detectar o navegador de verdade antes de dar a
            # instalacao como concluida.
            $ticksMaxVerificacao = 25   # 25 x 200ms = 5s

            $timerInstalar = New-Object System.Windows.Forms.Timer
            $timerInstalar.Interval = 200

            $timerInstalar.Add_Tick({
                if (-not $estadoInstalacao.Concluido) {

                    if (-not $estadoInstalacao.ProcessoSaiu) {
                        $estadoInstalacao.TicksDecorridos++
                        if ((-not $processoInstalar.HasExited) -and ($estadoInstalacao.TicksDecorridos -ge $ticksTimeout)) {
                            $estadoInstalacao.Concluido = $true
                            try { $processoInstalar.Kill($true) } catch { }

                            $labelStatusBrave.Text = "A instalacao travou e foi cancelada apos 3 minutos sem resposta."
                            if (-not $formProgresso.IsDisposed) {
                                $labelProgresso.Text = "Instalacao cancelada (travou)."
                                $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
                                $labelPercentual.Text = "Timeout"
                            }
                            [System.Windows.Forms.MessageBox]::Show(
                                "A instalacao do Brave nao respondeu por 3 minutos e foi cancelada.`n`nIsso costuma acontecer quando o instalador fica esperando uma janela oculta (ex.: pedindo para fechar o Brave) que ninguem consegue ver ou clicar. Feche qualquer janela do Brave/BraveUpdate que esteja aberta e tente novamente.",
                                "Instalacao travada",
                                [System.Windows.Forms.MessageBoxButtons]::OK,
                                [System.Windows.Forms.MessageBoxIcon]::Warning
                            )
                            Get-EventSubscriber | Where-Object { $_.SourceObject -eq $processoInstalar } | Unregister-Event
                            $timerInstalar.Stop()
                            $timerInstalar.Dispose()
                            if (-not $formProgresso.IsDisposed) {
                                $formProgresso.Close()
                                $formProgresso.Dispose()
                            }
                            $botaoInstalarBrave.Enabled = $true
                            $botaoDesinstalarBrave.Enabled = $true
                            return
                        }

                        if ($processoInstalar.HasExited) {
                            $estadoInstalacao.ProcessoSaiu = $true
                        } elseif ((-not $formProgresso.IsDisposed) -and ($barraProgresso.Value -lt 90)) {
                            $incremento = Get-Random -Minimum 2 -Maximum 6
                            $novoValor = $barraProgresso.Value + $incremento
                            if ($novoValor -gt 90) { $novoValor = 90 }
                            $barraProgresso.Value = $novoValor
                            $labelPercentual.Text = "$novoValor%"
                        }
                    }

                    if ($estadoInstalacao.ProcessoSaiu) {
                        if ($processoInstalar.ExitCode -ne 0) {
                            $estadoInstalacao.Concluido = $true

                            $descricaoErro = & $refGetDescricaoErroWingetBrave -CodigoSaida $processoInstalar.ExitCode
                            $saidaWinget = $sbSaidaInstalar.ToString().Trim()

                            $labelStatusBrave.Text = "Falha (codigo $($processoInstalar.ExitCode)): $descricaoErro"
                            if (-not $formProgresso.IsDisposed) {
                                $labelProgresso.Text = "Falha na instalacao."
                                $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
                                $labelPercentual.Text = "Codigo $($processoInstalar.ExitCode)"
                            }

                            $mensagemDetalhada = "Falha ao instalar o Brave.`n`nCodigo: $($processoInstalar.ExitCode)`nMotivo provavel: $descricaoErro"
                            if ($saidaWinget) {
                                $mensagemDetalhada += "`n`nSaida do winget:`n$saidaWinget"
                            }
                            [System.Windows.Forms.MessageBox]::Show(
                                $mensagemDetalhada,
                                "Erro na instalacao",
                                [System.Windows.Forms.MessageBoxButtons]::OK,
                                [System.Windows.Forms.MessageBoxIcon]::Error
                            )

                            Get-EventSubscriber | Where-Object { $_.SourceObject -eq $processoInstalar } | Unregister-Event
                            $botaoInstalarBrave.Enabled = $true
                            $botaoDesinstalarBrave.Enabled = $true
                        } else {
                            # winget disse que deu certo: so consideramos
                            # REALMENTE instalado quando conseguirmos
                            # detectar o Brave (exe ou registro).
                            $detectado = (& $refGetBraveExePath) -or (& $refGetBraveUninstallInfo)
                            $estadoInstalacao.TicksVerificacao++

                            if ($detectado -or ($estadoInstalacao.TicksVerificacao -ge $ticksMaxVerificacao)) {
                                $estadoInstalacao.Concluido = $true
                                $labelStatusBrave.Text = "Brave instalado com sucesso."
                                if (-not $formProgresso.IsDisposed) {
                                    $barraProgresso.Value = 100
                                    $labelPercentual.Text = "100%"
                                    $labelProgresso.Text = "Instalado com sucesso!"
                                    $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 60)
                                }
                                # Agora que o Brave foi instalado, troca o icone de
                                # reserva/baixado pelo icone oficial extraido do executavel.
                                if (-not $picLogoBrave.IsDisposed) {
                                    $picLogoBrave.Image = & $refLogoBraveOficial
                                }

                                # Instalado com sucesso: some com o botao Instalar e
                                # mostra somente o Desinstalar, no lugar dele.
                                if (-not $botaoInstalarBrave.IsDisposed) {
                                    $botaoInstalarBrave.Visible = $false
                                }
                                if (-not $chkSelecionarBrave.IsDisposed) {
                                    $chkSelecionarBrave.Checked = $false
                                    $chkSelecionarBrave.Visible = $false
                                }
                                if (-not $botaoDesinstalarBrave.IsDisposed) {
                                    $botaoDesinstalarBrave.Location = New-Object System.Drawing.Point($colBraveCtrlX, $botaoDesinstalarBrave.Location.Y)
                                    $botaoDesinstalarBrave.Visible = $true
                                }

                                Get-EventSubscriber | Where-Object { $_.SourceObject -eq $processoInstalar } | Unregister-Event
                                $botaoInstalarBrave.Enabled = $true
                                $botaoDesinstalarBrave.Enabled = $true

                                # Atualiza a tela inteira de navegadores para
                                # refletir o novo estado (recem-instalado).
                                $botaoNavegadores.PerformClick()
                            } elseif (-not $formProgresso.IsDisposed) {
                                $barraProgresso.Value = 95
                                $labelPercentual.Text = "95%"
                                $labelProgresso.Text = "Finalizando instalacao..."
                            }
                        }
                    }

                } else {
                    $estadoInstalacao.TicksAteFechar++
                    if ($estadoInstalacao.TicksAteFechar -ge $ticksParaFechar) {
                        $timerInstalar.Stop()
                        $timerInstalar.Dispose()
                        if (-not $formProgresso.IsDisposed) {
                            $formProgresso.Close()
                            $formProgresso.Dispose()
                        }
                    }
                }
            }.GetNewClosure())

            $timerInstalar.Start()
        } catch {
            $formProgresso.Close()
            $formProgresso.Dispose()
            $labelStatusBrave.Text = "Erro ao instalar: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show(
                "Falha ao instalar o Brave:`n`n$($_.Exception.Message)",
                "Erro na instalacao",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $botaoInstalarBrave.Enabled = $true
            $botaoDesinstalarBrave.Enabled = $true
        }
    }.GetNewClosure())

    $botaoDesinstalarBrave.Add_Click({
        $botaoInstalarBrave.Enabled = $false
        $botaoDesinstalarBrave.Enabled = $false
        $labelStatusBrave.Text = "Desinstalando Brave..."
        [System.Windows.Forms.Application]::DoEvents()

        $formProgresso = New-Object System.Windows.Forms.Form
        $formProgresso.Text = "Desinstalando Brave"
        $formProgresso.Size = New-Object System.Drawing.Size(360, 150)
        $formProgresso.FormBorderStyle = "FixedDialog"
        $formProgresso.ControlBox = $false
        $formProgresso.MaximizeBox = $false
        $formProgresso.MinimizeBox = $false
        $formProgresso.StartPosition = "CenterScreen"
        $formProgresso.BackColor = [System.Drawing.Color]::White
        $formProgresso.TopMost = $true

        $labelProgresso = New-Object System.Windows.Forms.Label
        $labelProgresso.Text = "Desinstalando o Brave, aguarde..."
        $labelProgresso.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $labelProgresso.TextAlign = "MiddleCenter"
        $labelProgresso.Location = New-Object System.Drawing.Point(15, 18)
        $labelProgresso.Size = New-Object System.Drawing.Size(310, 30)
        $formProgresso.Controls.Add($labelProgresso)

        $barraProgresso = New-Object System.Windows.Forms.ProgressBar
        $barraProgresso.Style = "Continuous"
        $barraProgresso.Minimum = 0
        $barraProgresso.Maximum = 100
        $barraProgresso.Value = 0
        $barraProgresso.Location = New-Object System.Drawing.Point(15, 58)
        $barraProgresso.Size = New-Object System.Drawing.Size(310, 24)
        $formProgresso.Controls.Add($barraProgresso)

        $labelPercentual = New-Object System.Windows.Forms.Label
        $labelPercentual.Text = "0%"
        $labelPercentual.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $labelPercentual.TextAlign = "MiddleCenter"
        $labelPercentual.Location = New-Object System.Drawing.Point(15, 88)
        $labelPercentual.Size = New-Object System.Drawing.Size(310, 20)
        $formProgresso.Controls.Add($labelPercentual)

        $formProgresso.Show($form)
        [System.Windows.Forms.Application]::DoEvents()

        try {
            # O winget uninstall do Brave nao funciona: o setup.exe do
            # Brave, quando chamado com --uninstall puro (o que o winget
            # --silent faz), abre um prompt pedindo pra fechar o navegador
            # primeiro - como a janela fica oculta, o processo trava pra
            # sempre e nunca desinstala. A propria Brave Software confirma
            # que so o parametro --force-uninstall evita esse prompt.
            #
            # Por isso lemos o UninstallString direto do registro (aponta
            # pro setup.exe correto, dentro da pasta da versao instalada,
            # ja com --system-level ou nao, conforme o caso) e so
            # acrescentamos --force-uninstall nele.
            $caminhosRegistroUninstall = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )

            $infoBrave = $null
            foreach ($caminhoReg in $caminhosRegistroUninstall) {
                $itens = Get-ItemProperty -Path $caminhoReg -ErrorAction SilentlyContinue |
                         Where-Object { $_.DisplayName -like "Brave*" }
                if ($itens) {
                    $infoBrave = $itens | Select-Object -First 1
                    break
                }
            }

            if (-not $infoBrave) {
                throw "Brave nao encontrado no registro de desinstalacao desta maquina."
            }

            $uninstallStr = $infoBrave.UninstallString
            if ($uninstallStr -match '^"([^"]+)"\s*(.*)$') {
                $caminhoSetupBrave = $Matches[1]
                $argsRegistroBrave = $Matches[2]
            } else {
                $partesUninstall = $uninstallStr.Split(' ', 2)
                $caminhoSetupBrave = $partesUninstall[0]
                $argsRegistroBrave = if ($partesUninstall.Count -gt 1) { $partesUninstall[1] } else { "" }
            }

            $psiDesinstalar = New-Object System.Diagnostics.ProcessStartInfo
            $psiDesinstalar.FileName = $caminhoSetupBrave
            $psiDesinstalar.Arguments = ($argsRegistroBrave + " --force-uninstall").Trim()
            $psiDesinstalar.UseShellExecute = $false
            $psiDesinstalar.CreateNoWindow = $true
            $psiDesinstalar.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

            $processoDesinstalar = New-Object System.Diagnostics.Process
            $processoDesinstalar.StartInfo = $psiDesinstalar
            $processoDesinstalar.Start() | Out-Null

            $estadoDesinstalacao = @{
                Concluido      = $false
                TicksAteFechar = 0
            }
            $ticksParaFecharDesinstalar = 7

            $timerDesinstalar = New-Object System.Windows.Forms.Timer
            $timerDesinstalar.Interval = 200

            $timerDesinstalar.Add_Tick({
                if (-not $estadoDesinstalacao.Concluido) {
                    if ($processoDesinstalar.HasExited) {
                        $estadoDesinstalacao.Concluido = $true

                        # O setup.exe do Brave pode retornar 0 ou 19 quando
                        # a desinstalacao da certo (19 = "reinicio adiado"),
                        # entao os dois contam como sucesso aqui.
                        if ($processoDesinstalar.ExitCode -eq 0 -or $processoDesinstalar.ExitCode -eq 19) {
                            $labelStatusBrave.Text = "Brave desinstalado com sucesso."
                            if (-not $formProgresso.IsDisposed) {
                                $barraProgresso.Value = 100
                                $labelPercentual.Text = "100%"
                                $labelProgresso.Text = "Desinstalado com sucesso!"
                                $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 60)
                            }

                            # Desinstalado com sucesso: some com o botao
                            # Desinstalar e mostra somente o Instalar, no
                            # lugar dele.
                            if (-not $botaoDesinstalarBrave.IsDisposed) {
                                $botaoDesinstalarBrave.Visible = $false
                            }
                            if (-not $chkSelecionarBrave.IsDisposed) {
                                $chkSelecionarBrave.Visible = $true
                            }
                            if (-not $botaoInstalarBrave.IsDisposed) {
                                $botaoInstalarBrave.Location = New-Object System.Drawing.Point($colBraveCtrlX, $botaoInstalarBrave.Location.Y)
                                $botaoInstalarBrave.Visible = $true
                            }

                            # Atualiza a tela inteira de navegadores para
                            # refletir o novo estado (recem-desinstalado).
                            $botaoNavegadores.PerformClick()
                        } else {
                            $labelStatusBrave.Text = "winget terminou com o codigo $($processoDesinstalar.ExitCode)."
                            if (-not $formProgresso.IsDisposed) {
                                $labelProgresso.Text = "Falha na desinstalacao."
                                $labelProgresso.ForeColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
                                $labelPercentual.Text = "Codigo $($processoDesinstalar.ExitCode)"
                            }
                        }

                        $botaoInstalarBrave.Enabled = $true
                        $botaoDesinstalarBrave.Enabled = $true
                    } else {
                        if ((-not $formProgresso.IsDisposed) -and ($barraProgresso.Value -lt 90)) {
                            $incremento = Get-Random -Minimum 2 -Maximum 6
                            $novoValor = $barraProgresso.Value + $incremento
                            if ($novoValor -gt 90) { $novoValor = 90 }
                            $barraProgresso.Value = $novoValor
                            $labelPercentual.Text = "$novoValor%"
                        }
                    }
                } else {
                    $estadoDesinstalacao.TicksAteFechar++
                    if ($estadoDesinstalacao.TicksAteFechar -ge $ticksParaFecharDesinstalar) {
                        $timerDesinstalar.Stop()
                        $timerDesinstalar.Dispose()
                        if (-not $formProgresso.IsDisposed) {
                            $formProgresso.Close()
                            $formProgresso.Dispose()
                        }
                    }
                }
            }.GetNewClosure())

            $timerDesinstalar.Start()
        } catch {
            if ($formProgresso -and (-not $formProgresso.IsDisposed)) {
                $formProgresso.Close()
                $formProgresso.Dispose()
            }
            $labelStatusBrave.Text = "Erro ao desinstalar: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show(
                "Falha ao desinstalar o Brave:`n`n$($_.Exception.Message)",
                "Erro na desinstalacao",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $botaoInstalarBrave.Enabled = $true
            $botaoDesinstalarBrave.Enabled = $true
        }
    }.GetNewClosure())

  } catch {
    # Rede de seguranca: se qualquer coisa acima falhar, mostramos o
    # erro real em vez de deixar a tela de conteudo em branco (ou o
    # script inteiro morrer silenciosamente, ja que este clique roda
    # antes do ShowDialog - ver comentario abaixo).
    [System.Windows.Forms.MessageBox]::Show(
        "Erro ao montar a tela de navegadores:`n`n$($_.Exception.Message)",
        "Erro",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
  }
})

# EnableVisualStyles precisa ser chamado antes de qualquer controle ser
# criado/exibido - por isso foi movido para antes do PerformClick abaixo
# (antes ficava depois, o que e contra a recomendacao da Microsoft e podia
# causar comportamento instavel dependendo da versao do .NET).
[System.Windows.Forms.Application]::EnableVisualStyles()

# Exibe a tela de navegadores automaticamente ao abrir (opcional)
# Comente a linha abaixo se preferir que o usuario clique manualmente
$botaoNavegadores.PerformClick()

[void]$form.ShowDialog()
