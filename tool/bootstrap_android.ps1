<#
.SYNOPSIS
  Complete le dossier android/ de MBOA BIO 237 avec les fichiers que seul le
  SDK Flutter sait generer : le wrapper Gradle, les icones de lanceur par
  defaut, le .gitignore Android.

.DESCRIPTION
  Le depot contient tout le code Dart, les migrations SQL, les pictogrammes
  et la configuration des trois flavors. Il ne contient pas, et ne peut pas
  contenir :

    * gradle/wrapper/gradle-wrapper.jar   (un binaire, hors de question de le
                                          mettre dans un depot de specs)
    * gradlew / gradlew.bat              (generes avec le jar)
    * res/mipmap-*/ic_launcher.png       (les PNG d'icone)

  Sans ces fichiers, `flutter build apk` echoue avant meme de lire une ligne
  de notre code. Ce script cree un projet jetable ailleurs, et ne copie dans
  le notre QUE ce qui manque.

  Il n'ecrase jamais un fichier existant : notre app/build.gradle avec ses
  trois flavors, notre AndroidManifest avec ses permissions et notre splash
  avec le logo officiel passent avant ceux du modele Flutter.

.PARAMETER Emplacement
  Dossier ou creer le projet jetable. Par defaut .\.scaffold_flutter

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool/bootstrap_android.ps1
#>

[CmdletBinding()]
param(
    [string]$Emplacement = ".\.scaffold_flutter"
)

$ErrorActionPreference = "Stop"

$racine = Split-Path -Parent $PSScriptRoot
Set-Location $racine

function Ecrire($message) { Write-Host "[MBOA] $message" -ForegroundColor Cyan }
function Alerte($message) { Write-Host "[MBOA] $message" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# 1. Le SDK doit etre la.
# ---------------------------------------------------------------------------
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    throw "flutter introuvable dans le PATH. Installez le Flutter SDK 3.22+, " +
          "puis relancez ce script depuis un terminal qui le voit."
}

Ecrire "Flutter : $((& flutter --version) | Select-Object -First 1)"

# ---------------------------------------------------------------------------
# 2. Projet jetable, meme organisation et meme nom que le notre.
# ---------------------------------------------------------------------------
if (Test-Path $Emplacement) {
    Alerte "$Emplacement existe deja, supprime"
    Remove-Item -Recurse -Force $Emplacement
}

Ecrire "Creation du projet modele dans $Emplacement"
& flutter create `
    --platforms=android `
    --org bio.mboa `
    --project-name mboa_bio `
    $Emplacement | Out-Null

if (-not (Test-Path "$Emplacement\android")) {
    throw "Le projet modele n'a pas produit de dossier android/. Verifiez la version de Flutter."
}

# ---------------------------------------------------------------------------
# 3. Copie selective : uniquement ce qui manque.
# ---------------------------------------------------------------------------
$source = Join-Path $Emplacement "android"
$dest = Join-Path $racine "android"

$aCopier = @(
    "gradlew",
    "gradlew.bat",
    "gradle\wrapper\gradle-wrapper.jar",
    "gradle\wrapper\gradle-wrapper.properties",
    ".gitignore",
    "app\.gitignore",
    "app\src\main\res\mipmap-hdpi\ic_launcher.png",
    "app\src\main\res\mipmap-mdpi\ic_launcher.png",
    "app\src\main\res\mipmap-xhdpi\ic_launcher.png",
    "app\src\main\res\mipmap-xxhdpi\ic_launcher.png",
    "app\src\main\res\mipmap-xxxhdpi\ic_launcher.png"
)

$nombre = 0
foreach ($chemin in $aCopier) {
    $d = Join-Path $source $chemin
    $a = Join-Path $dest $chemin

    if (-not (Test-Path $d)) {
        Alerte "absent du modele : $chemin"
        continue
    }
    if (Test-Path $a) {
        Ecrire "conservé (déjà présent) : $chemin"
        continue
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $a) | Out-Null
    Copy-Item $d $a
    $nombre++
    Ecrire "copié : $chemin"
}

# ---------------------------------------------------------------------------
# 4. Nettoyage du projet jetable.
# ---------------------------------------------------------------------------
Remove-Item -Recurse -Force $Emplacement

Ecrire "$nombre fichier(s) ajoute(s). Le dossier android/ est complet."
Ecrire "Etape suivante : powershell -File tool\build_apks.ps1 -Url <SUPABASE_URL> -Cle <ANON_KEY>"
