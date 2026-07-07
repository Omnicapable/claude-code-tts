# patch_tts_hook_timeout.ps1
# Applies the BeginConnect 2-second timeout fix to the installed tts_hook.ps1.
# Run once — right-click -> Run with PowerShell (no admin needed).
# Safe to re-run; checks whether the patch is already applied before touching anything.

$hookPath = "$env:USERPROFILE\.claude\tts_hook.ps1"

if (-not (Test-Path $hookPath)) {
    Write-Host "ERROR: $hookPath not found. Is Claude Code TTS installed?" -ForegroundColor Red
    pause
    exit 1
}

$content = Get-Content $hookPath -Raw

if ($content -match "BeginConnect") {
    Write-Host "Already patched — BeginConnect is already present in $hookPath" -ForegroundColor Green
    pause
    exit 0
}

if (-not ($content -match [regex]::Escape('$client.Connect("127.0.0.1"'))) {
    Write-Host "ERROR: Expected Connect pattern not found — file may have been modified manually." -ForegroundColor Red
    pause
    exit 1
}

# Back up original
Copy-Item $hookPath "$hookPath.bak" -Force
Write-Host "Backup saved to $hookPath.bak"

# Apply patch — replace both Connect calls with BeginConnect + 2s timeout
$old = '$client.Connect("127.0.0.1", $port)'
$new = @'
$ar = $client.BeginConnect("127.0.0.1", $port, $null, $null)
    $ok = $ar.AsyncWaitHandle.WaitOne(2000)
    if (-not $ok) { $client.Close(); throw "Connect timeout" }
    $client.EndConnect($ar)
'@

$content = $content.Replace($old, $new)
Set-Content $hookPath -Value $content -Encoding UTF8 -NoNewline

Write-Host "Patch applied successfully to $hookPath" -ForegroundColor Green
Write-Host "Both Connect calls now have a 2-second timeout (was: blocking indefinitely)."
pause
