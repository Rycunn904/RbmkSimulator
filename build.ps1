$ErrorActionPreference = "Stop"

$WorkspaceRoot = "C:\Users\CatBo\OneDrive\Desktop\CODE\RbmkServer"
$SimRoot       = $PSScriptRoot
$BuildTmp      = Join-Path $SimRoot "build_tmp"
$LibsDir       = Join-Path $BuildTmp "libs"
$DistInput     = Join-Path $SimRoot "dist_input"
$DistOutput    = Join-Path $SimRoot "dist_output"
$UnityServerDir = "C:\Users\CatBo\RBMK_3D\Assets\StreamingAssets\RbmkServer"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   RBMK 0.4.7 Full Multi-Repo Build       " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# [1/8] Clean build directories
Write-Host "`n[1/8] Cleaning previous build artifacts..." -ForegroundColor Yellow
foreach ($dir in @($BuildTmp, $DistInput, $DistOutput)) {
    if (Test-Path $dir) { Remove-Item -Path $dir -Recurse -Force }
}
New-Item -ItemType Directory -Path $LibsDir -Force | Out-Null

# Locate AbsoluteLayout.jar (from release app/ or workspace)
$AbsJar = Get-ChildItem -Path $WorkspaceRoot -Filter "AbsoluteLayout*.jar" -Recurse | Select-Object -First 1
if (-not $AbsJar) {
    throw "Could not find AbsoluteLayout.jar anywhere under $WorkspaceRoot"
}
Copy-Item $AbsJar.FullName -Destination (Join-Path $LibsDir "AbsoluteLayout.jar")

# Helper function to compile a sibling Java repo into a JAR in build_tmp\libs
function Build-JavaLibrary {
    param(
        [string]$RepoName,
        [string]$JarName,
        [string[]]$ExtraClasspathJars
    )

    $RepoDir = Get-ChildItem -Path $WorkspaceRoot -Directory | Where-Object { $_.Name -ieq $RepoName } | Select-Object -First 1
    if (-not $RepoDir) {
        throw "Could not find sibling repository '$RepoName' inside $WorkspaceRoot"
    }

    $SrcDir = Join-Path $RepoDir.FullName "src"
    if (-not (Test-Path $SrcDir)) { $SrcDir = $RepoDir.FullName }

    $ClassesOut = Join-Path $BuildTmp "classes_$RepoName"
    New-Item -ItemType Directory -Path $ClassesOut -Force | Out-Null

    $JavaFiles = Get-ChildItem -Path $SrcDir -Filter "*.java" -Recurse | Select-Object -ExpandProperty FullName
    Write-Host "  -> Building $JarName ($($JavaFiles.Count) source files)..." -ForegroundColor Green

    $ArgFile = Join-Path $BuildTmp "sources_$RepoName.txt"
    $JavaFiles | ForEach-Object { "`"$($_.Replace('\', '/'))`"" } | Set-Content -Path $ArgFile -Encoding ASCII

    if ($ExtraClasspathJars.Count -gt 0) {
        $Cp = ($ExtraClasspathJars -join ";")
        & javac -encoding UTF-8 -cp $Cp -d $ClassesOut "@$ArgFile"
    } else {
        & javac -encoding UTF-8 -d $ClassesOut "@$ArgFile"
    }
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed for $RepoName" }

    # Copy any non-.java resource files (properties, icons, etc.)
    Get-ChildItem -Path $SrcDir -Recurse -File | Where-Object { $_.Extension -ne ".java" } | ForEach-Object {
        $RelPath = $_.FullName.Substring($SrcDir.Length).TrimStart('\', '/')
        $DestFile = Join-Path $ClassesOut $RelPath
        New-Item -ItemType Directory -Path (Split-Path $DestFile -Parent) -Force | Out-Null
        Copy-Item $_.FullName -Destination $DestFile -Force
    }

    $OutJar = Join-Path $LibsDir $JarName
    & jar cf $OutJar -C $ClassesOut .
    if ($LASTEXITCODE -ne 0) { throw "JAR packaging failed for $JarName" }

    return $OutJar
}

# [2/8] Build dependency libraries in exact dependency order: utils -> phxnetmod -> jmplot
Write-Host "`n[2/8] Compiling sibling libraries into build_tmp\libs..." -ForegroundColor Yellow
$UtilsJar     = Build-JavaLibrary -RepoName "utils"     -JarName "utils-0.0.1-SNAPSHOT.jar"     -ExtraClasspathJars @()
$PhxNetModJar = Build-JavaLibrary -RepoName "phxnetmod" -JarName "phxnetmod-0.0.1-SNAPSHOT.jar" -ExtraClasspathJars @($UtilsJar)
$JmPlotJar    = Build-JavaLibrary -RepoName "jmplot"    -JarName "jmplot-0.0.1-SNAPSHOT.jar"    -ExtraClasspathJars @($UtilsJar, $PhxNetModJar)

# [3/8] Compile RbmkSimulator
Write-Host "`n[3/8] Compiling RbmkSimulator..." -ForegroundColor Yellow
$SimClasses = Join-Path $BuildTmp "classes_rbmksim"
New-Item -ItemType Directory -Path $SimClasses -Force | Out-Null

$SimSrc = Join-Path $SimRoot "src"
$SimJavaFiles = Get-ChildItem -Path $SimSrc -Filter "*.java" -Recurse | Select-Object -ExpandProperty FullName
$SimArgFile = Join-Path $BuildTmp "sources_rbmksim.txt"
$SimJavaFiles | ForEach-Object { "`"$($_.Replace('\', '/'))`"" } | Set-Content -Path $SimArgFile -Encoding ASCII

$AllJars = Get-ChildItem -Path $LibsDir -Filter "*.jar" | Select-Object -ExpandProperty FullName
$SimClasspath = ($AllJars -join ";")

& javac -encoding UTF-8 -cp $SimClasspath -d $SimClasses "@$SimArgFile"
if ($LASTEXITCODE -ne 0) { throw "RbmkSimulator compilation failed!" }

# Copy RbmkSimulator resources
Get-ChildItem -Path $SimSrc -Recurse -File | Where-Object { $_.Extension -ne ".java" } | ForEach-Object {
    $RelPath = $_.FullName.Substring($SimSrc.Length).TrimStart('\', '/')
    $DestFile = Join-Path $SimClasses $RelPath
    New-Item -ItemType Directory -Path (Split-Path $DestFile -Parent) -Force | Out-Null
    Copy-Item $_.FullName -Destination $DestFile -Force
}

# [4/8] Package RbmkSimulator.jar into dist_input
Write-Host "`n[4/8] Packaging RbmkSimulator.jar & dependencies..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $DistInput -Force | Out-Null
Copy-Item -Path "$LibsDir\*.jar" -Destination $DistInput -Force

$ManifestFile = Join-Path $BuildTmp "MANIFEST.MF"
@"
Manifest-Version: 1.0
Main-Class: com.hartrusion.rbmksim.RbmkSimulator
Class-Path: utils-0.0.1-SNAPSHOT.jar phxnetmod-0.0.1-SNAPSHOT.jar jmplot-0.0.1-SNAPSHOT.jar AbsoluteLayout.jar
"@ | Set-Content -Path $ManifestFile -Encoding ASCII

$MainJar = Join-Path $DistInput "RbmkSimulator.jar"
& jar cfm $MainJar $ManifestFile -C $SimClasses .
if ($LASTEXITCODE -ne 0) { throw "Failed to package RbmkSimulator.jar" }

# [5/8] Run jpackage to generate standalone Windows app-image (RbmkServer.exe)
Write-Host "`n[5/8] Building standalone RbmkServer.exe via jpackage..." -ForegroundColor Yellow
& jpackage `
    --type app-image `
    --name RbmkServer `
    --input $DistInput `
    --dest $DistOutput `
    --main-jar RbmkSimulator.jar `
    --main-class com.hartrusion.rbmksim.RbmkSimulator
if ($LASTEXITCODE -ne 0) { throw "jpackage failed!" }

# [6/8] Deploy fresh build to Unity StreamingAssets (preserving saves/)
Write-Host "`n[6/8] Deploying RbmkServer to Unity StreamingAssets..." -ForegroundColor Yellow
$BuiltServerDir = Join-Path $DistOutput "RbmkServer"
New-Item -ItemType Directory -Path $UnityServerDir -Force | Out-Null

# /MIR mirrors everything from $BuiltServerDir into $UnityServerDir (including hidden/dot files & read-only files)
# /XD saves ensures your existing saves folder and .ic files are never touched or deleted
& robocopy $BuiltServerDir $UnityServerDir /MIR /XD "saves" /R:3 /W:1 /NFL /NDL /NJH /NJS
if ($LASTEXITCODE -ge 8) {
    throw "Robocopy deployment failed with exit code $LASTEXITCODE"
}

Write-Host "`n[7/8] Cleaning build artifacts..." -ForegroundColor Yellow
foreach ($dir in @($BuildTmp, $DistInput)) {
    if (Test-Path $dir) { Remove-Item -Path $dir -Recurse -Force }
}

Write-Host "`n[8/8] Build Complete! RbmkServer.exe is updated with 0.4.7 + Multiplayer." -ForegroundColor Cyan
