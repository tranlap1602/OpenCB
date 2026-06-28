param(
  [string]$Configuration,
  [string]$TargetPath,
  [string]$ProcessName
)

if ($Configuration -ne 'Debug') {
  exit 0
}

try {
  $target = [System.IO.Path]::GetFullPath($TargetPath)
  Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Path -and ([System.IO.Path]::GetFullPath($_.Path) -eq $target)
    } |
    Stop-Process -Force
} catch {
  exit 0
}
