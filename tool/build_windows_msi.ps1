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
$outputRoot = Join-Path $projectRoot 'build\installer'
$objectRoot = Join-Path $outputRoot 'obj'
$msiPath = Join-Path $outputRoot '页间_0.2.0_x64.msi'

$heat = Join-Path $WixRoot 'heat.exe'
$candle = Join-Path $WixRoot 'candle.exe'
$light = Join-Path $WixRoot 'light.exe'
$wixUi = Join-Path $WixRoot 'WixUIExtension.dll'

foreach ($required in @($sourceDir, $installerSource, $heat, $candle, $light, $wixUi)) {
  if (-not (Test-Path -LiteralPath $required)) {
    throw "Required build input does not exist: $required"
  }
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
  -var var.SourceDir `
  -out $harvestedSource
if ($LASTEXITCODE -ne 0) { throw "WiX heat failed with exit code $LASTEXITCODE" }

& $candle `
  -nologo `
  -arch x64 `
  "-dSourceDir=$sourceDir" `
  "-dProjectDir=$projectRoot" `
  -out "$objectRoot\" `
  $installerSource `
  $harvestedSource
if ($LASTEXITCODE -ne 0) { throw "WiX candle failed with exit code $LASTEXITCODE" }

& $light `
  -nologo `
  -ext $wixUi `
  -cultures:zh-CN `
  -out $msiPath `
  (Join-Path $objectRoot 'product.wixobj') `
  (Join-Path $objectRoot 'application-files.wixobj')
if ($LASTEXITCODE -ne 0) { throw "WiX light failed with exit code $LASTEXITCODE" }

Write-Output $msiPath
