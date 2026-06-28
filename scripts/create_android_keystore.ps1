param(
  [string]$OutputDir = ".secrets",
  [string]$Alias = "opencb",
  [string]$StorePassword,
  [string]$KeyPassword
)

$ErrorActionPreference = "Stop"

if (-not $StorePassword) {
  $StorePassword = [Convert]::ToBase64String(
    [Security.Cryptography.RandomNumberGenerator]::GetBytes(24)
  )
}
if (-not $KeyPassword) {
  $KeyPassword = [Convert]::ToBase64String(
    [Security.Cryptography.RandomNumberGenerator]::GetBytes(24)
  )
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$keystorePath = Join-Path $OutputDir "opencb-upload-keystore.jks"

keytool -genkeypair `
  -v `
  -keystore $keystorePath `
  -storetype JKS `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias $Alias `
  -storepass $StorePassword `
  -keypass $KeyPassword `
  -dname "CN=OpenCB, OU=OpenCB, O=OpenCB, L=Ho Chi Minh City, S=Ho Chi Minh, C=VN"

$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystorePath))
$localKeyProperties = @"
storeFile=upload-keystore.jks
storePassword=$StorePassword
keyAlias=$Alias
keyPassword=$KeyPassword
"@
$localKeyProperties | Set-Content -Path (Join-Path $OutputDir "key.properties") -Encoding utf8

Write-Host ""
Write-Host "Created: $keystorePath"
Write-Host ""
Write-Host "Add these GitHub repository secrets:"
Write-Host "ANDROID_KEYSTORE_BASE64=$base64"
Write-Host "ANDROID_KEYSTORE_PASSWORD=$StorePassword"
Write-Host "ANDROID_KEY_ALIAS=$Alias"
Write-Host "ANDROID_KEY_PASSWORD=$KeyPassword"
Write-Host ""
Write-Host "Backup $OutputDir somewhere safe. Losing this keystore means future Android updates cannot use the same signature."
