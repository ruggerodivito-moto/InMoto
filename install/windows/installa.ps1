# InMoto — Script installazione Windows
# Esegui con: tasto destro → "Esegui con PowerShell"
# oppure: powershell -ExecutionPolicy Bypass -File installa.ps1

param(
    [string]$GithubUser = "ruggerodivito-moto"
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "InMoto Installer"

function Write-Header {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   InMoto — Installatore per iPhone" -ForegroundColor White
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step([int]$n, [string]$text) {
    Write-Host "[$n] $text" -ForegroundColor Yellow
}

function Write-OK([string]$text) {
    Write-Host "    OK  $text" -ForegroundColor Green
}

function Write-Err([string]$text) {
    Write-Host "    !! $text" -ForegroundColor Red
}

function Pause-Screen {
    Write-Host ""
    Write-Host "Premi un tasto per continuare..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ── Cartella di lavoro ────────────────────────────────────────────────────────
$WorkDir = "$env:TEMP\InMotoInstaller"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

Write-Header

# ── STEP 1: Scarica IPA da GitHub Releases ────────────────────────────────────
Write-Step 1 "Scarico InMoto.ipa da GitHub Releases..."

$IpaUrl  = "https://github.com/$GithubUser/InMoto/releases/latest/download/InMoto.ipa"
$IpaPath = "$WorkDir\InMoto.ipa"

try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $IpaUrl -OutFile $IpaPath -UseBasicParsing
    $sizeMB = [math]::Round((Get-Item $IpaPath).Length / 1MB, 1)
    Write-OK "InMoto.ipa scaricato ($sizeMB MB)"
} catch {
    Write-Err "Impossibile scaricare l'IPA."
    Write-Host ""
    Write-Host "Verifica che il repository GitHub sia pubblico e abbia almeno una Release." -ForegroundColor Yellow
    Write-Host "URL tentato: $IpaUrl" -ForegroundColor Gray
    Pause-Screen
    exit 1
}

# ── STEP 2: Scarica Sideloadly ────────────────────────────────────────────────
Write-Step 2 "Scarico Sideloadly (firma e installa l'IPA gratuitamente)..."

$SideloadlyUrl  = "https://sideloadly.io/SideloadlySetup64.exe"
$SideloadlyPath = "$WorkDir\SideloadlySetup.exe"
$SideloadlyExe  = "$env:LOCALAPPDATA\Sideloadly\sideloadly.exe"

$AlreadyInstalled = Test-Path $SideloadlyExe

if ($AlreadyInstalled) {
    Write-OK "Sideloadly già installato"
} else {
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $SideloadlyUrl -OutFile $SideloadlyPath -UseBasicParsing
        Write-OK "Sideloadly scaricato"

        Write-Host ""
        Write-Host "    Installazione Sideloadly in corso..." -ForegroundColor Yellow
        Start-Process -FilePath $SideloadlyPath -ArgumentList "/S" -Wait
        Write-OK "Sideloadly installato"
    } catch {
        Write-Err "Download Sideloadly fallito."
        Write-Host ""
        Write-Host "Scarica manualmente Sideloadly da: https://sideloadly.io" -ForegroundColor Yellow
        Write-Host "Poi trascina il file '$IpaPath' su Sideloadly." -ForegroundColor Gray
        Pause-Screen
        exit 1
    }
}

# ── STEP 3: iTunes / Apple Mobile Device Support ─────────────────────────────
Write-Step 3 "Verifico iTunes / Apple Mobile Device Support..."

$iTunesKey = "HKLM:\SOFTWARE\Apple Inc.\Apple Mobile Device Support"
if (Test-Path $iTunesKey) {
    Write-OK "Apple Mobile Device Support trovato"
} else {
    Write-Host ""
    Write-Host "    iTunes o Apple Mobile Device Support non trovato." -ForegroundColor Yellow
    Write-Host "    Sideloadly ne ha bisogno per comunicare con iPhone." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    Scaricalo da: https://www.apple.com/itunes/download/win64" -ForegroundColor Cyan
    Write-Host "    Oppure installa la versione Microsoft Store di iTunes." -ForegroundColor Cyan
    Write-Host ""
    $choice = Read-Host "    Vuoi aprire il sito iTunes ora? (s/n)"
    if ($choice -eq "s") {
        Start-Process "https://www.apple.com/itunes/download/win64"
    }
    Write-Host ""
    Write-Host "    Installa iTunes, poi torna a eseguire questo script." -ForegroundColor Yellow
    Pause-Screen
    exit 0
}

# ── STEP 4: Apri Sideloadly con l'IPA ────────────────────────────────────────
Write-Step 4 "Apro Sideloadly con InMoto.ipa..."

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  ISTRUZIONI SIDELOADLY" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Connetti iPhone al PC con il cavo USB" -ForegroundColor White
Write-Host "  2. Sblocca iPhone e tocca 'Fidati' se richiesto" -ForegroundColor White
Write-Host "  3. In Sideloadly, l'IPA e' gia' caricato" -ForegroundColor White
Write-Host "  4. Inserisci il tuo Apple ID (GRATUITO)" -ForegroundColor White
Write-Host "  5. Clicca 'Start'" -ForegroundColor White
Write-Host "  6. Inserisci la password quando richiesta" -ForegroundColor White
Write-Host ""
Write-Host "  NOTA: La prima installazione richiede ~2 minuti." -ForegroundColor Gray
Write-Host "  L'app dura 7 giorni — SideStore la rinnova automaticamente." -ForegroundColor Gray
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan

Pause-Screen

# Cerca l'eseguibile Sideloadly in posizioni comuni
$SideloadlyPaths = @(
    $SideloadlyExe,
    "$env:LOCALAPPDATA\Programs\Sideloadly\sideloadly.exe",
    "C:\Program Files\Sideloadly\sideloadly.exe",
    "C:\Program Files (x86)\Sideloadly\sideloadly.exe"
)

$ExeFound = $SideloadlyPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($ExeFound) {
    # Apri Sideloadly con l'IPA come argomento
    Start-Process -FilePath $ExeFound -ArgumentList "`"$IpaPath`""
    Write-OK "Sideloadly aperto con InMoto.ipa"
} else {
    Write-Host ""
    Write-Host "  Sideloadly non trovato in posizione standard." -ForegroundColor Yellow
    Write-Host "  Aprilo manualmente e trascina questo file:" -ForegroundColor Yellow
    Write-Host "  $IpaPath" -ForegroundColor Cyan
    Write-Host ""
    # Copia il percorso negli appunti
    $IpaPath | Set-Clipboard
    Write-Host "  (Percorso copiato negli appunti)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  PROSSIMO PASSO: SideStore" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Dopo aver installato InMoto, installa SideStore" -ForegroundColor White
Write-Host "  per il rinnovo automatico del certificato ogni 7 giorni:" -ForegroundColor White
Write-Host ""
Write-Host "  1. Apri Safari su iPhone" -ForegroundColor White
Write-Host "  2. Vai su: https://sidestore.io" -ForegroundColor Cyan
Write-Host "  3. Segui le istruzioni di installazione" -ForegroundColor White
Write-Host "  4. In SideStore, vai in Sorgenti e aggiungi:" -ForegroundColor White

# Leggi il GitHub user dall'apps.json se disponibile
$AppsJsonPath = Split-Path $PSScriptRoot | Split-Path | Join-Path -ChildPath "apps.json"
if (Test-Path $AppsJsonPath) {
    $AppsJson = Get-Content $AppsJsonPath | ConvertFrom-Json
    $SourceUrl = $AppsJson.apps[0].downloadURL -replace "/releases/latest/download/.*", ""
    $SourceUrl = "https://raw.githubusercontent.com/$GithubUser/InMoto/main/apps.json"
    Write-Host "     $SourceUrl" -ForegroundColor Cyan
}

Write-Host ""
Pause-Screen
