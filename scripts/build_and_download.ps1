<#
.SYNOPSIS
    Script de automação para compilar o Silence via GitHub Actions e baixar o APK resultante.

.DESCRIPTION
    Este script automatiza o ciclo de build no GitHub:
    1. Opcionalmente envia as alterações locais (git commit + push) para disparar a build,
       ou aciona diretamente o workflow via API/workflow_dispatch (se token fornecido).
    2. Monitora o status da execução do workflow no GitHub Actions em tempo real.
    3. Se a build for bem-sucedida, baixa o artefato APK descompactado na pasta 'build-output'.
    4. Se a build falhar, obtém e imprime os logs de erro diretamente no terminal.

.PARAMETER PushChanges
    Se especificado ($true), faz git add, commit e push antes de aguardar a build.

.PARAMETER CommitMessage
    Mensagem do commit quando -PushChanges for usado. Padrão: "feat: implement amoled theme and build workflow"

.PARAMETER GitHubToken
    Token de Acesso Pessoal (PAT) do GitHub opcional. Se não informado, tenta ler da variável $env:GITHUB_TOKEN.

.PARAMETER OutputDir
    Diretório onde o APK será salvo. Padrão: "./build-output"
#>

[CmdletBinding()]
param(
    [switch]$PushChanges,
    [string]$CommitMessage,
    [string]$GitHubToken = $env:GITHUB_TOKEN,
    [string]$OutputDir = "./build-output"
)

$ErrorActionPreference = "Stop"
$RepoOwner = "S-Marcos-S"
$RepoName = "Silence"
$ApiBase = "https://api.github.com/repos/$RepoOwner/$RepoName"

function Write-Info([string]$msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Cyan
}

function Write-Success([string]$msg) {
    Write-Host "[SUCCESS] $msg" -ForegroundColor Green
}

function Write-Warn([string]$msg) {
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function Write-Err([string]$msg) {
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

function Get-AutoCommitMessage {
    $rawStatus = git status --porcelain
    if (-not $rawStatus) {
        return "chore: update repository"
    }

    $files = $rawStatus | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -gt 3) {
            $line.Substring(3).Trim('"', ' ')
        }
    }

    $hasUi = $files | Where-Object { $_ -like "*src/main/java/*/ui/*" }
    $hasRes = $files | Where-Object { $_ -like "*src/main/res/*" }
    $hasWorkflow = $files | Where-Object { $_ -like "*.github/workflows/*" }
    $hasGradle = $files | Where-Object { $_ -like "*gradle*" -or $_ -like "*build.gradle*" }
    $hasScript = $files | Where-Object { $_ -like "*scripts/*" -or $_ -like "*.bat" }
    $hasPrefOrCore = $files | Where-Object { $_ -like "*Preferences.kt*" -or $_ -like "*MainActivity.kt*" }

    $baseNames = $files | ForEach-Object { Split-Path $_ -Leaf } | Select-Object -Unique

    if ($baseNames.Count -le 2) {
        $joined = $baseNames -join " and "
        if ($hasWorkflow) { return "ci: update $joined" }
        if ($hasGradle) { return "build: update $joined" }
        if ($hasScript) { return "chore: update $joined" }
        if ($hasUi -or $hasRes) { return "feat(ui): update $joined" }
        return "chore: update $joined"
    }

    if ($hasUi -and $hasPrefOrCore) {
        return "feat(settings): update theme and preferences UI"
    }
    if ($hasUi -or $hasRes) {
        return "feat(ui): update UI components and resources"
    }
    if ($hasWorkflow -and $hasScript) {
        return "ci: improve build automation and workflows"
    }
    if ($hasGradle) {
        return "build: update project build configuration"
    }
    if ($hasScript) {
        return "chore: update project scripts"
    }

    $summaryFiles = ($baseNames | Select-Object -First 3) -join ", "
    return "feat: update $summaryFiles"
}

$headers = @{
    "User-Agent" = "Silence-Build-Script"
    "Accept" = "application/vnd.github+json"
}

if ($GitHubToken) {
    $headers["Authorization"] = "Bearer $GitHubToken"
}

# 1. Push opcional das alterações
if ($PushChanges) {
    Write-Info "Verificando status do Git..."
    $status = git status --porcelain
    if ($status) {
        if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
            $suggestedMsg = Get-AutoCommitMessage
            Write-Host ""
            Write-Host "Foram detectadas alteracoes no projeto prontas para commit." -ForegroundColor Cyan
            Write-Host "Sugestao de titulo gerada: '$suggestedMsg'" -ForegroundColor Yellow
            $inputMsg = Read-Host "Digite o nome/mensagem do commit (Enter para usar a sugestao)"
            if ([string]::IsNullOrWhiteSpace($inputMsg)) {
                $CommitMessage = $suggestedMsg
            } else {
                $CommitMessage = $inputMsg.Trim()
            }
            Write-Host ""
        }
        Write-Info "Criando commit: '$CommitMessage'..."
        git add -A
        git commit -m $CommitMessage
    } else {
        Write-Info "Nenhuma alteração pendente para commit."
    }
    Write-Info "Enviando alterações para origin/master (git push)..."
    git push origin master
    Write-Success "Push realizado com sucesso!"
    Start-Sleep -Seconds 3
}

# Obter o último commit hash local
$latestCommit = (git rev-parse HEAD).Trim()
Write-Info "Último commit local: $latestCommit"

# 2. Localizar o workflow run associado
Write-Info "Buscando execução correspondente no GitHub Actions..."
$run = $null
$maxRetries = 20
$retryCount = 0

while (-not $run -and $retryCount -lt $maxRetries) {
    $retryCount++
    try {
        $runsResponse = Invoke-RestMethod -Uri "$ApiBase/actions/runs?per_page=10" -Headers $headers -Method Get
        $matchingRun = $runsResponse.workflow_runs | Where-Object { 
            $_.head_sha -eq $latestCommit -or $_.name -eq "Android CI"
        } | Select-Object -First 1

        if ($matchingRun) {
            $run = $matchingRun
            break
        }
    } catch {
        Write-Warn "Aguardando GitHub registrar o workflow (tentativa $retryCount/$maxRetries)..."
    }
    Start-Sleep -Seconds 4
}

if (-not $run) {
    Write-Err "Não foi possível localizar uma execução recente do workflow no GitHub."
    Write-Warn "Se este repositório for um fork, o GitHub Actions vem desativado por padrão."
    Write-Info "Acesse para ativar: https://github.com/$RepoOwner/$RepoName/actions"
    Write-Info "Clique no botão verde: 'I understand my workflows, go ahead and enable them'."
    Write-Info "Depois, execute o build novamente!"
    exit 1
}

$runId = $run.id
$htmlUrl = $run.html_url
Write-Info "Workflow encontrado: ID $runId"
Write-Info "Acompanhe também em: $htmlUrl"

# 3. Monitorar status da build em tempo real
Write-Info "Aguardando a conclusão da build..."
$isCompleted = $false
$conclusion = $null

while (-not $isCompleted) {
    Start-Sleep -Seconds 8
    try {
        $runStatus = Invoke-RestMethod -Uri "$ApiBase/actions/runs/$runId" -Headers $headers -Method Get
        $status = $runStatus.status
        $conclusion = $runStatus.conclusion
        $timestamp = (Get-Date).ToString("HH:mm:ss")

        Write-Host "[$timestamp] Status: $status | Conclusão: $conclusion" -ForegroundColor DarkGray

        if ($status -eq "completed") {
            $isCompleted = $true
        }
    } catch {
        Write-Warn "Falha temporária ao consultar status da execução: $($_.Exception.Message)"
    }
}

# 4. Avaliar resultado da build
if ($conclusion -eq "success") {
    Write-Success "Build finalizada com SUCESSO no GitHub Actions!"
    
    # 5. Baixar o artefato APK
    Write-Info "Buscando artefatos gerados..."
    $artifactsResponse = Invoke-RestMethod -Uri "$ApiBase/actions/runs/$runId/artifacts" -Headers $headers -Method Get
    $apkArtifact = $artifactsResponse.artifacts | Where-Object { $_.name -eq "silence-debug-apk" } | Select-Object -First 1

    if (-not $apkArtifact) {
        Write-Warn "Nenhum artefato 'silence-debug-apk' encontrado na execução."
        exit 0
    }

    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $zipPath = Join-Path $OutputDir "silence-apk.zip"
    Write-Info "Baixando artefato ($([math]::Round($apkArtifact.size_in_bytes / 1MB, 2)) MB)..."

    # Se tiver token, pode baixar direto da API; caso contrário, usa o archive_download_url
    try {
        $downloadUrl = $apkArtifact.archive_download_url
        if ($headers.ContainsKey("Authorization")) {
            Invoke-WebRequest -Uri $downloadUrl -Headers $headers -OutFile $zipPath
        } else {
            Write-Warn "Download de artefatos pela API requer autenticação do GitHub."
            Write-Info "Você pode baixar diretamente pelo navegador em: $htmlUrl"
            Write-Info "Ou configure um Personal Access Token com: `$env:GITHUB_TOKEN = 'seu_token' e execute o script novamente."
            exit 0
        }

        # Descompactar
        Write-Info "Descompactando arquivo APK..."
        Expand-Archive -Path $zipPath -DestinationPath $OutputDir -Force
        Remove-Item $zipPath -Force

        $downloadedApk = Get-ChildItem -Path $OutputDir -Filter "*.apk" -Recurse | Select-Object -First 1
        if ($downloadedApk) {
            Write-Success "APK baixado com sucesso em: $($downloadedApk.FullName)"
        }
    } catch {
        Write-Err "Erro ao baixar artefato: $($_.Exception.Message)"
        Write-Info "Você pode baixar o APK pela interface do GitHub em: $htmlUrl"
    }

} else {
    Write-Err "A build FALHOU no GitHub Actions com conclusão: $conclusion"
    Write-Info "Consultando logs dos passos com falha..."
    
    try {
        $jobsResponse = Invoke-RestMethod -Uri "$ApiBase/actions/runs/$runId/jobs" -Headers $headers -Method Get
        foreach ($job in $jobsResponse.jobs) {
            if ($job.conclusion -eq "failure") {
                Write-Err "Job falhou: $($job.name)"
                foreach ($step in $job.steps) {
                    if ($step.conclusion -eq "failure") {
                        Write-Err " -> Passo que falhou: $($step.name)"
                    }
                }
            }
        }
    } catch {
        Write-Warn "Não foi possível carregar o resumo dos jobs: $($_.Exception.Message)"
    }

    Write-Info "Veja os logs completos em: $htmlUrl"
}
