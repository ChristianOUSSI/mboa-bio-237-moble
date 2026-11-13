<#
.SYNOPSIS
  Construit les quatre APK de MBOA BIO 237 : fournisseur, admin, consommateur, livreur.

.DESCRIPTION
  Chaque flavor porte deux choses :

    * --flavor           : ce que voit Android (nom d'app, identifiant, splash)
    * --dart-define      : ce que voit Dart (l'ecran racine, les credentials)

  Les deux doivent etre d'accord. Un APK construit avec --flavor admin mais
  sans MBOA_ROLE=admin demarre sur l'app cliente : c'est l'erreur la plus
  frequente de ce projet, et c'est pour elle que ce script existe.

  Les cles Supabase ne sont jamais dans le depot. Elles passent par les
  parametres, ou par un fichier .env.local lu ligne a ligne.

.PARAMETER Url
  https://XXXX.supabase.co  -- sans lui, les APK tournent en mode demonstration
  sur la base SQLite du telephone. C'est voulu et testable, mais ce n'est pas
  un build a envoyer en test terrain.

.PARAMETER Cle
  La cle anon du projet. Jamais la service_role : elle serait extractible
  depuis l'APK en trente secondes.

.PARAMETER Role
  Limiter la construction a un seul flavor : fournisseur | admin | consommateur | livreur

.PARAMETER Mode
  apk (par defaut, un fichier par flavor) ou appbundle (pour le Play Store).

.EXAMPLE
  powershell -File tool\build_apks.ps1 -Url https://abcd.supabase.co -Cle eyJhbGciOi...
  powershell -File tool\build_apks.ps1 -Role fournisseur -Mode appbundle
#>

[CmdletBinding()]
param(
    [string]$Url = "",
    [string]$Cle = "",
    [ValidateSet("fournisseur", "admin", "consommateur", "livreur", "tous")]
    [string]$Role = "tous",
    [ValidateSet("apk", "appbundle")]
    [string]$Mode = "apk"
)

$ErrorActionPreference = "Stop"

$racine = Split-Path -Parent $PSScriptRoot
Set-Location $racine

function Ecrire($m) { Write-Host "[MBOA] $m" -ForegroundColor Cyan }
function Alerte($m) { Write-Host "[MBOA] $m" -ForegroundColor Yellow }
function OK($m) { Write-Host "[MBOA] $m" -ForegroundColor Green }

# ---------------------------------------------------------------------------
# 0. Le wrapper Gradle doit exister.
# ---------------------------------------------------------------------------
if (-not (Test-Path "android\gradle\wrapper\gradle-wrapper.jar")) {
    Alerte "Wrapper Gradle absent. Le dossier android/ est incomplet."
    throw "Lancez d'abord : powershell -ExecutionPolicy Bypass -File tool\bootstrap_android.ps1"
}

# ---------------------------------------------------------------------------
# 1. Credentials : parametres, sinon .env.local, sinon mode demonstration.
# ---------------------------------------------------------------------------
if ((-not $Url) -and (Test-Path ".env.local")) {
    foreach ($ligne in Get-Content ".env.local") {
        if ($ligne -match "^\s*SUPABASE_URL\s*=\s*(.+)$") { $Url = $Matches[1].Trim() }
        if ($ligne -match "^\s*SUPABASE_ANON_KEY\s*=\s*(.+)$") { $Cle = $Matches[1].Trim() }
    }
    Ecrire "Credentials lus dans .env.local"
}

$enLigne = $Url.StartsWith("http") -and $Cle.Length -gt 20
if (-not $enLigne) {
    Alerte "Aucun Supabase fourni : les APK tourneront en demonstration, sur la base locale."
    Alerte "Les donnees ne quitteront pas le telephone, et les trois apps ne se parleront pas."
}

# ---------------------------------------------------------------------------
# 2. Preparation.
# ---------------------------------------------------------------------------
Ecrire "flutter pub get"
& flutter pub get
if ($LASTEXITCODE -ne 0) { throw "pub get a echoue. Verifiez les versions de paquets." }

# Les icones de lanceur se regenerent a partir du logo officiel : trois apps,
# une seule identite visuelle, comme l'impose la charte.
if (Test-Path "assets\logo\mboa_bio_237.jpeg") {
    Ecrire "flutter_launcher_icons"
    & dart run flutter_launcher_icons 2>$null
    if ($LASTEXITCODE -ne 0) { Alerte "Icones non regenerees (package absent ?), build quand meme." }
}

# ---------------------------------------------------------------------------
# 3. Construction.
# ---------------------------------------------------------------------------
$roles = if ($Role -eq "tous") { @("fournisseur", "admin", "consommateur", "livreur") } else { @($Role) }
$sousDossier = if ($Mode -eq "apk") { "apk" } else { "app" }
$extensions = if ($Mode -eq "apk") { @(".apk") } else { @(".aab") }

$produits = @()

foreach ($r in $roles) {
    Ecrire "Build $Mode / flavor $r"

    $arguments = @(
        "build", $Mode,
        "--release",
        "--flavor", $r,
        "--dart-define=MBOA_ROLE=$r"
    )
    if ($enLigne) {
        $arguments += "--dart-define=SUPABASE_URL=$Url"
        $arguments += "--dart-define=SUPABASE_ANON_KEY=$Cle"
    }

    & flutter @arguments
    if ($LASTEXITCODE -ne 0) { throw "Le build du flavor $r a echoue. Voir la sortie Gradle ci-dessus." }

    $dossier = "build\app\outputs\$sousDossier\release\$r"
    foreach ($ext in $extensions) {
        Get-ChildItem -Path $dossier -Filter "*$ext" -ErrorAction SilentlyContinue | ForEach-Object {
            $destination = "dist\mboa-$r$ext"
            New-Item -ItemType Directory -Force -Path "dist" | Out-Null
            Copy-Item $_.FullName $destination -Force
            $taille = [math]::Round((Get-Item $destination).Length / 1MB, 1)
            OK "$destination  ($taille Mo)"
            $produits += $destination
        }
    }
}

# ---------------------------------------------------------------------------
# 4. Resume.
# ---------------------------------------------------------------------------
if ($produits.Count -eq 0) {
    throw "Aucun fichier produit. Le build a rendu une sortie vide : anormal."
}

Ecrire ""
Ecrire "${($produits.Count)} fichier(s) dans dist/ :"
foreach ($p in $produits) { Ecrire "  $p" }
Alerte "Ces APK sont compilés, pas testés sur un appareil. Les ouvrir sur un Tecno réel avant tout envoi en village."
