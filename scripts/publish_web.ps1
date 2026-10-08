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
$sourceBranchName = "source"
$deploymentBranch = "main"
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

function Get-NativeText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $output = & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "El comando '$Command $($Arguments -join ' ')' terminó con código $LASTEXITCODE."
    }

    return (($output | Out-String).Trim())
}

function Assert-SourceBackedUp {
    $workingTreeStatus = Get-NativeText git status --porcelain --untracked-files=normal
    if (-not [string]::IsNullOrWhiteSpace($workingTreeStatus)) {
        throw @"
El árbol de código fuente tiene cambios sin commit.
Revisa, prueba, agrega y confirma primero los archivos correctos antes de publicar.
"@
    }

    $sourceBranch = Get-NativeText git branch --show-current
    if ([string]::IsNullOrWhiteSpace($sourceBranch)) {
        throw "No se puede publicar desde un HEAD separado de una rama."
    }
    if ($sourceBranch -ne $sourceBranchName) {
        throw @"
La publicación debe ejecutarse desde '$sourceBranchName', no desde '$sourceBranch'.
Integra y publica primero el código fuente estable en '$sourceBranchName'.
"@
    }

    $upstream = & git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($upstream)) {
        throw "La rama '$sourceBranch' no tiene upstream. Publica primero el código fuente."
    }

    $localCommit = Get-NativeText git rev-parse HEAD
    $remoteCommit = Get-NativeText git rev-parse $upstream
    if ($localCommit -ne $remoteCommit) {
        throw @"
El commit local $localCommit no coincide con $upstream ($remoteCommit).
Ejecuta git push y verifica la sincronización antes de compilar/publicar.
"@
    }

    Write-Host "Código fuente respaldado en $upstream ($localCommit)."
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

function New-VersionedWebAssets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Revision
    )

    if ($Revision -notmatch '^[0-9a-f]{12}$') {
        throw "La revisión web '$Revision' no tiene el formato esperado."
    }

    $mainFileName = "main.$Revision.dart.js"
    $bootstrapFileName = "flutter_bootstrap.$Revision.js"
    $mainPath = Join-Path -Path $buildDirectory -ChildPath "main.dart.js"
    $bootstrapPath = Join-Path -Path $buildDirectory -ChildPath "flutter_bootstrap.js"
    $indexPath = Join-Path -Path $buildDirectory -ChildPath "index.html"

    Get-ChildItem -LiteralPath $buildDirectory -File |
        Where-Object {
            $_.Name -match '^main\.[0-9a-f]{12}\.dart\.js$' -or
            $_.Name -match '^flutter_bootstrap\.[0-9a-f]{12}\.js$'
        } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

    Copy-Item `
        -LiteralPath $mainPath `
        -Destination (Join-Path -Path $buildDirectory -ChildPath $mainFileName) `
        -Force

    $bootstrapContent = Get-Content -LiteralPath $bootstrapPath -Raw
    $defaultMainReference = '"mainJsPath":"main.dart.js"'
    if (-not $bootstrapContent.Contains($defaultMainReference)) {
        throw "No se encontró la referencia estándar a main.dart.js en el bootstrap."
    }
    $bootstrapContent = $bootstrapContent.Replace(
        $defaultMainReference,
        ('"mainJsPath":"{0}"' -f $mainFileName)
    )

    $versionedBootstrapPath = Join-Path `
        -Path $buildDirectory `
        -ChildPath $bootstrapFileName
    [System.IO.File]::WriteAllText(
        $versionedBootstrapPath,
        $bootstrapContent,
        [System.Text.UTF8Encoding]::new($false)
    )

    $indexContent = Get-Content -LiteralPath $indexPath -Raw
    $bootstrapPattern = 'flutter_bootstrap(?:\.[0-9a-f]{12})?\.js'
    if ($indexContent -notmatch $bootstrapPattern) {
        throw "No se encontró la referencia al bootstrap en index.html."
    }
    $indexContent = [System.Text.RegularExpressions.Regex]::Replace(
        $indexContent,
        $bootstrapPattern,
        $bootstrapFileName
    )
    [System.IO.File]::WriteAllText(
        $indexPath,
        $indexContent,
        [System.Text.UTF8Encoding]::new($false)
    )

    return [PSCustomObject]@{
        MainFileName = $mainFileName
        BootstrapFileName = $bootstrapFileName
    }
}

function Assert-VersionedWebBuild {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Assets
    )

    $mainPath = Join-Path -Path $buildDirectory -ChildPath $Assets.MainFileName
    $bootstrapPath = Join-Path `
        -Path $buildDirectory `
        -ChildPath $Assets.BootstrapFileName
    $indexPath = Join-Path -Path $buildDirectory -ChildPath "index.html"

    foreach ($requiredPath in @($mainPath, $bootstrapPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "No se generó el recurso web versionado: $requiredPath"
        }
    }

    $bootstrapContent = Get-Content -LiteralPath $bootstrapPath -Raw
    if ($bootstrapContent -notmatch [regex]::Escape($Assets.MainFileName)) {
        throw "El bootstrap versionado no referencia $($Assets.MainFileName)."
    }

    $indexContent = Get-Content -LiteralPath $indexPath -Raw
    if ($indexContent -notmatch [regex]::Escape($Assets.BootstrapFileName)) {
        throw "index.html no referencia $($Assets.BootstrapFileName)."
    }
}

Push-Location -LiteralPath $projectRoot
$locationDepth++

try {
    Assert-SourceBackedUp

    if (-not $SkipBuild) {
        Write-Host "Compilando Flutter Web para $pagesBaseHref..."
        Invoke-NativeCommand flutter build web --release --base-href $pagesBaseHref
    }

    Assert-WebBuild
    $sourceRevision = Get-NativeText git rev-parse --short=12 HEAD
    $versionedAssets = New-VersionedWebAssets -Revision $sourceRevision
    Assert-VersionedWebBuild -Assets $versionedAssets
    Write-Host "Recursos web versionados para evitar cachés antiguas: $sourceRevision."

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
    Invoke-NativeCommand git clone --depth 1 --branch $deploymentBranch $repositoryUrl $temporaryDirectory

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

    foreach ($unversionedEntry in @(
        (Join-Path -Path $temporaryDirectory -ChildPath "main.dart.js"),
        (Join-Path -Path $temporaryDirectory -ChildPath "flutter_bootstrap.js"),
        (Join-Path -Path $temporaryDirectory -ChildPath "flutter_service_worker.js")
    )) {
        if (Test-Path -LiteralPath $unversionedEntry -PathType Leaf) {
            Remove-Item -LiteralPath $unversionedEntry -Force
        }
    }

    Copy-Item `
        -LiteralPath (Join-Path -Path $projectRoot -ChildPath "web\.nojekyll") `
        -Destination (Join-Path -Path $temporaryDirectory -ChildPath ".nojekyll") `
        -Force

    Push-Location -LiteralPath $temporaryDirectory
    $locationDepth++

    Invoke-NativeCommand git config user.name "02051994"
    Invoke-NativeCommand git config user.email "118220540+02051994@users.noreply.github.com"
    # Pasar -A dentro de un arreglo evita que PowerShell lo interprete como
    # abreviatura del parametro -Arguments de Invoke-NativeCommand.
    Invoke-NativeCommand -Command git -Arguments @("add", "-A")

    & git diff --cached --quiet
    $diffExitCode = $LASTEXITCODE
    if ($diffExitCode -eq 0) {
        Write-Host "La web publicada ya está actualizada."
    } elseif ($diffExitCode -eq 1) {
        Invoke-NativeCommand git commit -m $Message
        Invoke-NativeCommand git push origin $deploymentBranch
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
