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
# Gera um icone (bitmap) estilizado representando o Firefox,
# desenhado em tempo de execucao (nao usa nenhuma imagem externa).
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
# Formulario principal
# ------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Onix Consulting"
$form.Size = New-Object System.Drawing.Size(700, 450)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(600, 400)
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

$form.Controls.Add($painelConteudo)
$form.Controls.Add($painelMenu)

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

# ------------------------------------------------------------------
# Acao do botao "Navegadores": lista os navegadores instalados
# como botoes na area de conteudo, cada um abrindo o respectivo
# navegador ao ser clicado
# ------------------------------------------------------------------
$botaoNavegadores.Add_Click({
    $painelConteudo.Controls.Clear()

    $labelSecao = New-Object System.Windows.Forms.Label
    $labelSecao.Text = "Navegadores instalados"
    $labelSecao.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $labelSecao.AutoSize = $true
    $labelSecao.Location = New-Object System.Drawing.Point(20, 20)
    $painelConteudo.Controls.Add($labelSecao)

    $instalados = Get-NavegadoresInstalados

    if ($instalados.Count -eq 0) {
        $labelVazio = New-Object System.Windows.Forms.Label
        $labelVazio.Text = "Nenhum navegador conhecido foi encontrado nesta maquina."
        $labelVazio.AutoSize = $true
        $labelVazio.Location = New-Object System.Drawing.Point(20, 70)
        $painelConteudo.Controls.Add($labelVazio)
        return
    }

    $y = 70
    foreach ($nav in $instalados) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $nav.Nome
        $btn.Width = 220
        $btn.Height = 45
        $btn.FlatStyle = "Flat"
        $btn.Location = New-Object System.Drawing.Point(20, $y)
        $btn.Tag = $nav.Caminho
        $btn.Font = New-Object System.Drawing.Font("Segoe UI", 10)

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
        $y += 55
    }

    # --------------------------------------------------------------
    # Secao dedicada ao Firefox: logo + botoes Instalar / Desinstalar
    # --------------------------------------------------------------
    $y += 20

    $linhaSeparadora = New-Object System.Windows.Forms.Label
    $linhaSeparadora.BorderStyle = "Fixed3D"
    $linhaSeparadora.Location = New-Object System.Drawing.Point(20, $y)
    $linhaSeparadora.Size = New-Object System.Drawing.Size(400, 2)
    $painelConteudo.Controls.Add($linhaSeparadora)
    $y += 20

    $labelFirefoxTitulo = New-Object System.Windows.Forms.Label
    $labelFirefoxTitulo.Text = "Gerenciar Firefox"
    $labelFirefoxTitulo.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $labelFirefoxTitulo.AutoSize = $true
    $labelFirefoxTitulo.Location = New-Object System.Drawing.Point(20, $y)
    $painelConteudo.Controls.Add($labelFirefoxTitulo)
    $y += 35

    # Logo do Firefox (desenhado em tempo de execucao)
    $picLogoFirefox = New-Object System.Windows.Forms.PictureBox
    $picLogoFirefox.Size = New-Object System.Drawing.Size(72, 72)
    $picLogoFirefox.Location = New-Object System.Drawing.Point(20, $y)
    $picLogoFirefox.SizeMode = "Zoom"
    $picLogoFirefox.Image = New-FirefoxLogoBitmap
    $painelConteudo.Controls.Add($picLogoFirefox)

    # Rotulo de status (fica ao lado da logo)
    $labelStatusFirefox = New-Object System.Windows.Forms.Label
    $labelStatusFirefox.Text = "Pronto."
    $labelStatusFirefox.AutoSize = $true
    $labelStatusFirefox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $labelStatusFirefox.Location = New-Object System.Drawing.Point(105, ($y + 25))
    $labelStatusFirefox.MaximumSize = New-Object System.Drawing.Size(320, 0)
    $painelConteudo.Controls.Add($labelStatusFirefox)

    $y += 85

    # Botao Instalar (abaixo da logo)
    $botaoInstalarFirefox = New-Object System.Windows.Forms.Button
    $botaoInstalarFirefox.Text = "Instalar"
    $botaoInstalarFirefox.Width = 105
    $botaoInstalarFirefox.Height = 40
    $botaoInstalarFirefox.FlatStyle = "Flat"
    $botaoInstalarFirefox.BackColor = [System.Drawing.Color]::FromArgb(0, 153, 76)
    $botaoInstalarFirefox.ForeColor = [System.Drawing.Color]::White
    $botaoInstalarFirefox.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $botaoInstalarFirefox.Location = New-Object System.Drawing.Point(20, $y)
    $painelConteudo.Controls.Add($botaoInstalarFirefox)

    # Botao Desinstalar (ao lado do Instalar)
    $botaoDesinstalarFirefox = New-Object System.Windows.Forms.Button
    $botaoDesinstalarFirefox.Text = "Desinstalar"
    $botaoDesinstalarFirefox.Width = 105
    $botaoDesinstalarFirefox.Height = 40
    $botaoDesinstalarFirefox.FlatStyle = "Flat"
    $botaoDesinstalarFirefox.BackColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
    $botaoDesinstalarFirefox.ForeColor = [System.Drawing.Color]::White
    $botaoDesinstalarFirefox.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $botaoDesinstalarFirefox.Location = New-Object System.Drawing.Point(135, $y)
    $painelConteudo.Controls.Add($botaoDesinstalarFirefox)

    # URL oficial da Mozilla para o instalador mais recente (64 bits, pt-BR)
    $urlOficialFirefox = "https://download.mozilla.org/?product=firefox-latest&os=win64&lang=pt-BR"

    $botaoInstalarFirefox.Add_Click({
        $botaoInstalarFirefox.Enabled = $false
        $botaoDesinstalarFirefox.Enabled = $false
        $labelStatusFirefox.Text = "Baixando instalador oficial da Mozilla..."

        $destinoInstalador = Join-Path $env:TEMP "FirefoxSetup.exe"
        $webClient = New-Object System.Net.WebClient

        $webClient.Add_DownloadProgressChanged({
            param($s, $e)
            $labelStatusFirefox.Text = "Baixando instalador oficial... $($e.ProgressPercentage)%"
        })

        $webClient.Add_DownloadFileCompleted({
            param($s, $e)
            if ($e.Error) {
                $labelStatusFirefox.Text = "Erro ao baixar: $($e.Error.Message)"
                $botaoInstalarFirefox.Enabled = $true
                $botaoDesinstalarFirefox.Enabled = $true
                return
            }

            $labelStatusFirefox.Text = "Executando instalacao silenciosa..."
            try {
                # /S = instalacao silenciosa (padrao do instalador NSIS do Firefox)
                Start-Process -FilePath $destinoInstalador -ArgumentList "/S"
                $labelStatusFirefox.Text = "Instalacao iniciada. Aguarde alguns instantes."
            } catch {
                $labelStatusFirefox.Text = "Erro ao instalar: $($_.Exception.Message)"
            } finally {
                $botaoInstalarFirefox.Enabled = $true
                $botaoDesinstalarFirefox.Enabled = $true
            }
        })

        try {
            $webClient.DownloadFileAsync([Uri]$urlOficialFirefox, $destinoInstalador)
        } catch {
            $labelStatusFirefox.Text = "Erro ao iniciar download: $($_.Exception.Message)"
            $botaoInstalarFirefox.Enabled = $true
            $botaoDesinstalarFirefox.Enabled = $true
        }
    })

    $botaoDesinstalarFirefox.Add_Click({
        $botaoInstalarFirefox.Enabled = $false
        $botaoDesinstalarFirefox.Enabled = $false
        $labelStatusFirefox.Text = "Procurando instalacao do Firefox..."
        [System.Windows.Forms.Application]::DoEvents()

        $info = Get-FirefoxUninstallInfo

        if (-not $info) {
            $labelStatusFirefox.Text = "Firefox nao encontrado nesta maquina."
            $botaoInstalarFirefox.Enabled = $true
            $botaoDesinstalarFirefox.Enabled = $true
            return
        }

        $labelStatusFirefox.Text = "Desinstalando silenciosamente..."
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $uninstallString = $info.UninstallString

            if ($uninstallString -match '^\s*"([^"]+)"\s*(.*)$') {
                $executavel = $Matches[1]
                $argumentosExtras = $Matches[2].Trim()
            } else {
                $partes = $uninstallString -split ' ', 2
                $executavel = $partes[0]
                $argumentosExtras = if ($partes.Count -gt 1) { $partes[1] } else { "" }
            }

            # /S = desinstalacao silenciosa (padrao do instalador NSIS do Firefox)
            $argumentosFinais = ("$argumentosExtras /S").Trim()
            Start-Process -FilePath $executavel -ArgumentList $argumentosFinais -Wait

            $labelStatusFirefox.Text = "Firefox desinstalado com sucesso."
        } catch {
            $labelStatusFirefox.Text = "Erro ao desinstalar: $($_.Exception.Message)"
        } finally {
            $botaoInstalarFirefox.Enabled = $true
            $botaoDesinstalarFirefox.Enabled = $true
        }
    })
})

# Exibe a tela de navegadores automaticamente ao abrir (opcional)
# Comente a linha abaixo se preferir que o usuario clique manualmente
$botaoNavegadores.PerformClick()

[System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
