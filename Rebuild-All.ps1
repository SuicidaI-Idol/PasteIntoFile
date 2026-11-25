$ErrorActionPreference = 'Stop'
$env:VSLANG = '1033'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'

function Invoke-BuildTool {
    param([string]$Tool, [string[]]$Arguments)
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed (exit code $LASTEXITCODE)." }
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'Visual Studio Build Tools is required.' }
$msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild was not found.' }

$wix = Join-Path $env:LOCALAPPDATA 'PasteIntoFile-BuildTools\wix-3.14.1'
if (-not (Test-Path (Join-Path $wix 'light.exe'))) {
    Write-Host 'Downloading WiX 3.14.1 (official portable distribution)...'
    New-Item -ItemType Directory -Force -Path $wix | Out-Null
    $archive = Join-Path $wix 'wix.zip'
    Invoke-WebRequest 'https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip' -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath $wix -Force
    Remove-Item -LiteralPath $archive
}

Push-Location $PSScriptRoot
try {
    $debugExe = Join-Path $PSScriptRoot 'PasteIntoFile\bin\Debug\PasteIntoFile.exe'
    if (Get-Process PasteIntoFile -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $debugExe }) {
        throw 'Stop the debug session (Shift+F5) before rebuilding everything.'
    }
    $common = @('PasteIntoFile.sln', '/restore', '/t:Rebuild', '/m', '/nologo', '/verbosity:minimal', '/p:PreferredUILang=en-US')
    Invoke-BuildTool $msbuild ($common + @('/p:Configuration=Debug', '/p:Flavor=Portable', '/p:PlatformTarget=x64', '/p:Prefer32Bit=false'))
    Invoke-BuildTool $msbuild ($common + @('/p:Configuration=Release', '/p:Flavor=Portable'))
    Copy-Item LICENSE 'PasteIntoFile\bin\Release\LICENSE'

    $version = (Get-Item 'PasteIntoFile\bin\Release\PasteIntoFile.exe').VersionInfo.ProductVersion
    $dist = Join-Path $PSScriptRoot 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    Compress-Archive -Path 'PasteIntoFile\bin\Release\*' -DestinationPath (Join-Path $dist "PasteIntoFile_${version}_portable.zip") -Force

    # Separate output prevents installer and portable settings providers from mixing.
    $installerFiles = Join-Path $PSScriptRoot 'PasteIntoFile\bin\Installer'
    Invoke-BuildTool $msbuild ($common + @('/p:Configuration=Release', '/p:Flavor=Installer', "/p:OutputPath=$installerFiles\"))
    Copy-Item LICENSE (Join-Path $installerFiles 'LICENSE')
    $work = Join-Path $PSScriptRoot 'Installer\obj'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $fragment = Join-Path $work 'releaseFiles.wxs'
    Invoke-BuildTool (Join-Path $wix 'heat.exe') @('dir', $installerFiles, '-dr', 'INSTALLFOLDER', '-ag', '-cg', 'ReleaseFragment', '-ke', '-srd', '-sfrag', '-nologo', '-t', 'Installer\releaseFiles.xslt', '-out', $fragment)
    Invoke-BuildTool (Join-Path $wix 'candle.exe') @('-nologo', '-ext', 'WixUtilExtension', '-out', "$work\", $fragment, 'Installer\PasteIntoFile.wxs')
    $msi = Join-Path $dist "PasteIntoFile_${version}_installer.msi"
    Invoke-BuildTool (Join-Path $wix 'light.exe') @('-nologo', '-b', $installerFiles, (Join-Path $work 'releaseFiles.wixobj'), (Join-Path $work 'PasteIntoFile.wixobj'), '-ext', 'WixNetFxExtension', '-ext', 'WixUtilExtension', '-out', $msi)
    Write-Host "Build completed: $dist"
} finally {
    Pop-Location
}
