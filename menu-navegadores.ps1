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
# Formulario principal
# ------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Menu Principal"
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
})

# Exibe a tela de navegadores automaticamente ao abrir (opcional)
# Comente a linha abaixo se preferir que o usuario clique manualmente
$botaoNavegadores.PerformClick()

[System.Windows.Forms.Application]::EnableVisualStyles()
[void]$form.ShowDialog()
