<#
  Um único crash do donation-service, para a demonstração de self-healing PASSO A PASSO
  (roteiro do vídeo 2.5). Versão PowerShell do crash-once.sh — não precisa de bash/WSL.

  Uso: rode 4-5 vezes seguidas, esperando o pod voltar entre uma e outra:
    .\scripts\crash-once.ps1
    .\scripts\crash-once.ps1
    ...

  Pré: kubeconfig no cluster + donation-service com CHAOS_ENDPOINTS_ENABLED=true.
#>
$ErrorActionPreference = 'Stop'
$ns = 'solidarytech'
$localPort = 18082

# fixa o mesmo pod entre execuções (o mais antigo em Running)
$pod = kubectl -n $ns get pods -l app=donation-service --field-selector=status.phase=Running `
  --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[0].metadata.name}'

$r0 = kubectl -n $ns get pod $pod -o jsonpath='{.status.containerStatuses[0].restartCount}'
Write-Host "pod alvo : $pod"
Write-Host "restarts : $r0  (antes)"

$pf = Start-Process kubectl -PassThru -WindowStyle Hidden `
  -ArgumentList "-n $ns port-forward pod/$pod ${localPort}:8082"
try {
  for ($i = 0; $i -lt 20; $i++) {
    try { Invoke-WebRequest "http://localhost:$localPort/live" -TimeoutSec 2 -UseBasicParsing | Out-Null; break }
    catch { Start-Sleep -Milliseconds 500 }
  }
  $resp = Invoke-RestMethod "http://localhost:$localPort/debug/crash" -Method Post -TimeoutSec 3
  Write-Host "crash    : $($resp | ConvertTo-Json -Compress)"
} finally {
  Stop-Process -Id $pf.Id -Force -ErrorAction SilentlyContinue
}

Write-Host -NoNewline "aguardando o container reiniciar"
for ($i = 0; $i -lt 60; $i++) {
  $ready = kubectl -n $ns get pod $pod -o jsonpath='{.status.containerStatuses[0].ready}' 2>$null
  $rc    = kubectl -n $ns get pod $pod -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>$null
  if ($rc -ne $r0 -and $ready -eq 'true') { break }
  Write-Host -NoNewline '.'; Start-Sleep -Seconds 2
}
Write-Host ''
kubectl -n $ns get pod $pod
$rf = kubectl -n $ns get pod $pod -o jsonpath='{.status.containerStatuses[0].restartCount}'
Write-Host "restarts : $rf  (depois)"
Write-Host ''
Write-Host '-> repita ate restarts > 3. Ai acompanhe:'
Write-Host '   Prometheus /alerts : DonationServiceCrashLooping  (inactive -> pending -> firing)'
Write-Host "   healer             : kubectl -n $ns logs deploy/healer-service -f --since=2m"
