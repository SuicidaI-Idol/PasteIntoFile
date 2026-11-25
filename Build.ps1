param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$env:VSLANG = '1033'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw 'Visual Studio Build Tools with .NET desktop build tools are required.'
}
$msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild was not found.' }
Push-Location $PSScriptRoot
try {
    $buildOptions = @('/p:PreferredUILang=en-US')
    if ($Configuration -eq 'Debug') {
        $buildOptions += '/p:PlatformTarget=x64'
        $buildOptions += '/p:Prefer32Bit=false'
    }
    & $msbuild 'PasteIntoFile.sln' /restore /m "/p:Configuration=$Configuration" /p:Flavor=Portable @buildOptions /verbosity:minimal /nologo
    if ($LASTEXITCODE -ne 0) { throw "Build failed (exit code $LASTEXITCODE)." }
    Copy-Item -LiteralPath 'LICENSE' -Destination "PasteIntoFile\bin\$Configuration\LICENSE"
    Write-Host "Application: $PSScriptRoot\PasteIntoFile\bin\$Configuration\PasteIntoFile.exe"
} finally {
    Pop-Location
}
