[CmdletBinding()]
param(
    [string]$Message = "Actualiza Zumac Web",
    [switch]$SkipBuild,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = [System.IO.Path]::GetFullPath(
    (Join-Path -Path $PSScriptRoot -ChildPath "..")
)
$buildDirectory = Join-Path -Path $projectRoot -ChildPath "build\web"
$repositoryUrl = "https://github.com/02051994/Zumac.git"
$pagesBaseHref = "/Zumac/"
$temporaryDirectory = $null
$temporaryDirectoryIsSafe = $false
$locationDepth = 0

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "El comando '$Command $($Arguments -join ' ')' terminó con código $LASTEXITCODE."
    }
}

function Assert-WebBuild {
    $requiredFiles = @(
        "index.html",
        "main.dart.js",
        "flutter_bootstrap.js"
    )

    foreach ($requiredFile in $requiredFiles) {
        $requiredPath = Join-Path -Path $buildDirectory -ChildPath $requiredFile
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "La compilación no generó el archivo requerido: $requiredPath"
        }
    }

    $indexPath = Join-Path -Path $buildDirectory -ChildPath "index.html"
    $indexContent = Get-Content -LiteralPath $indexPath -Raw
    if ($indexContent -notmatch '<base href="/Zumac/">') {
        throw "La compilación no tiene la ruta base requerida $pagesBaseHref."
    }
}

Push-Location -LiteralPath $projectRoot
$locationDepth++

try {
    if (-not $SkipBuild) {
        Write-Host "Compilando Flutter Web para $pagesBaseHref..."
        Invoke-NativeCommand flutter build web --release --base-href $pagesBaseHref
    }

    Assert-WebBuild

    if ($DryRun) {
        Write-Host "Validación correcta. No se publicaron cambios."
        return
    }

    $systemTempDirectory = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath()
    )
    $temporaryDirectory = [System.IO.Path]::GetFullPath(
        (Join-Path -Path $systemTempDirectory -ChildPath (
            "zumac-web-deploy-" + [System.Guid]::NewGuid().ToString("N")
        ))
    )

    $safeTempPrefix = $systemTempDirectory.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $temporaryDirectory.StartsWith(
        $safeTempPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "La carpeta temporal quedó fuera del directorio temporal permitido."
    }

    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    $temporaryDirectoryIsSafe = $true

    Write-Host "Preparando una copia temporal del sitio publicado..."
    Invoke-NativeCommand git clone --depth 1 --branch main $repositoryUrl $temporaryDirectory

    $publishedEntries = Get-ChildItem -LiteralPath $temporaryDirectory -Force |
        Where-Object { $_.Name -ne ".git" }
    foreach ($publishedEntry in $publishedEntries) {
        Remove-Item -LiteralPath $publishedEntry.FullName -Recurse -Force
    }

    $buildEntries = Get-ChildItem -LiteralPath $buildDirectory -Force
    foreach ($buildEntry in $buildEntries) {
        Copy-Item `
            -LiteralPath $buildEntry.FullName `
            -Destination $temporaryDirectory `
            -Recurse `
            -Force
    }

    Copy-Item `
        -LiteralPath (Join-Path -Path $projectRoot -ChildPath "web\.nojekyll") `
        -Destination (Join-Path -Path $temporaryDirectory -ChildPath ".nojekyll") `
        -Force

    Push-Location -LiteralPath $temporaryDirectory
    $locationDepth++

    Invoke-NativeCommand git config user.name "02051994"
    Invoke-NativeCommand git config user.email "118220540+02051994@users.noreply.github.com"
    Invoke-NativeCommand git add -A

    & git diff --cached --quiet
    $diffExitCode = $LASTEXITCODE
    if ($diffExitCode -eq 0) {
        Write-Host "La web publicada ya está actualizada."
    } elseif ($diffExitCode -eq 1) {
        Invoke-NativeCommand git commit -m $Message
        Invoke-NativeCommand git push origin main
        Write-Host "Publicación terminada: https://02051994.github.io/Zumac/"
    } else {
        throw "No se pudo comprobar el contenido preparado para publicar."
    }
} finally {
    while ($locationDepth -gt 0) {
        Pop-Location
        $locationDepth--
    }

    if (
        $temporaryDirectoryIsSafe -and
        $null -ne $temporaryDirectory -and
        (Test-Path -LiteralPath $temporaryDirectory)
    ) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}
