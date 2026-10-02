[CmdletBinding()]
param(
  [string]$WixRoot = $env:WIX_ROOT
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($WixRoot)) {
  throw 'Specify -WixRoot or set WIX_ROOT to the WiX Toolset directory.'
}
$WixRoot = (Resolve-Path -LiteralPath $WixRoot).Path
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$installerSource = Join-Path $projectRoot 'installer\windows\product.wxs'
$packageFilter = Join-Path $projectRoot 'installer\windows\package_filter.xslt'
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$outputRoot = Join-Path $projectRoot 'build\installer'
$objectRoot = Join-Path $outputRoot 'obj'

$versionText = Get-Content -LiteralPath $pubspecPath -Raw
$versionMatch = [regex]::Match(
  $versionText,
  '(?m)^version:\s*(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(?<suffix>-[^+\s]+)?\+(?<build>\d+)\s*$'
)
if (-not $versionMatch.Success) {
  throw 'Cannot read the app version from pubspec.yaml.'
}
$displayVersion = $versionMatch.Value.Split(':', 2)[1].Trim().Split('+', 2)[0]
$major = [int]$versionMatch.Groups['major'].Value
$minor = [int]$versionMatch.Groups['minor'].Value
$patch = [int]$versionMatch.Groups['patch'].Value
$suffix = $versionMatch.Groups['suffix'].Value
if ($suffix -match '^-dev\.(\d+)$') {
  $msiPatch = $patch * 1000 + [int]$Matches[1]
} elseif ([string]::IsNullOrEmpty($suffix)) {
  $msiPatch = $patch * 1000 + 999
} else {
  throw "Unsupported prerelease version for MSI: $suffix"
}
if ($msiPatch -gt 65535) {
  throw "MSI numeric version is out of range: $msiPatch"
}
# Windows Installer compares only three numeric version fields. The display name
# and filename keep the exact Flutter version, while the numeric field increases
# across dev builds and then the stable release.
$msiVersion = "$major.$minor.$msiPatch"
$msiPath = Join-Path $outputRoot "yejian_${displayVersion}_x64.msi"

$heat = Join-Path $WixRoot 'heat.exe'
$candle = Join-Path $WixRoot 'candle.exe'
$light = Join-Path $WixRoot 'light.exe'
$wixUi = Join-Path $WixRoot 'WixUIExtension.dll'

foreach ($required in @($sourceDir, $installerSource, $packageFilter, $heat, $candle, $light, $wixUi)) {
  if (-not (Test-Path -LiteralPath $required)) {
    throw "Required build input does not exist: $required"
  }
}

if (Test-Path -LiteralPath (Join-Path $sourceDir 'user-data')) {
  throw 'Release directory contains user data; remove it from the packaging source before building MSI.'
}
$exeVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
  (Join-Path $sourceDir 'yejian.exe')
).FileVersion
if ($exeVersion -ne "$displayVersion+$($versionMatch.Groups['build'].Value)") {
  throw "Windows executable version ($exeVersion) does not match pubspec.yaml. Rebuild Windows first."
}

New-Item -ItemType Directory -Force -Path $outputRoot, $objectRoot | Out-Null
$harvestedSource = Join-Path $outputRoot 'application-files.wxs'

& $heat dir $sourceDir `
  -nologo `
  -cg ApplicationFiles `
  -dr INSTALLFOLDER `
  -srd `
  -sreg `
  -sfrag `
  -ag `
  -t $packageFilter `
  -var var.SourceDir `
  -out $harvestedSource
if ($LASTEXITCODE -ne 0) { throw "WiX heat failed with exit code $LASTEXITCODE" }

& $candle `
  -nologo `
  -arch x64 `
  "-dSourceDir=$sourceDir" `
  "-dProjectDir=$projectRoot" `
  "-dAppDisplayVersion=$displayVersion" `
  "-dMsiVersion=$msiVersion" `
  -out "$objectRoot\" `
  $installerSource `
  $harvestedSource
if ($LASTEXITCODE -ne 0) { throw "WiX candle failed with exit code $LASTEXITCODE" }

& $light `
  -nologo `
  -ext $wixUi `
  -cultures:zh-CN `
  -sice:ICE38 `
  -sice:ICE64 `
  -sice:ICE91 `
  -out $msiPath `
  (Join-Path $objectRoot 'product.wixobj') `
  (Join-Path $objectRoot 'application-files.wixobj')
if ($LASTEXITCODE -ne 0) { throw "WiX light failed with exit code $LASTEXITCODE" }

Write-Output $msiPath
