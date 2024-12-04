# Helper function to check if a program is installed
function Check-Installed {
    param ([string]$ProgramName)
    $found = Get-Command $ProgramName -ErrorAction SilentlyContinue
    return $found -ne $null
}

# Helper function to install a program using winget
function Install-Program {
    param ([string]$PackageName)
    Write-Host "Installing $PackageName..." -ForegroundColor Yellow
    Start-Process -FilePath "winget" -ArgumentList "install --id $PackageName --silent --accept-source-agreements --accept-package-agreements" -Wait
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to install $PackageName. Check winget or installation errors." -ForegroundColor Red
        exit 1
    }
}

# Helper function to run a command in Git Bash
function Run-GitBashCommand {
    param ([string]$Command)
    $gitBashExe = "$($Env:ProgramFiles)\Git\bin\bash.exe"
    if (-not (Test-Path $gitBashExe)) {
        Write-Host "Git Bash executable not found!" -ForegroundColor Red
        exit 1
    }
    & $gitBashExe -c $Command
}

# Function to create and display SSH key
function Setup-SSHKey {
    if (-not (Test-Path "~/.ssh/id_rsa.pub")) {
        Write-Host "Generating a new SSH key..." -ForegroundColor Yellow
        Run-GitBashCommand "ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ''"
    } else {
        Write-Host "SSH key already exists." -ForegroundColor Green
    }
    Write-Host "Public Key:" -ForegroundColor Cyan
    Run-GitBashCommand "cat ~/.ssh/id_rsa.pub"
}

# Helper function to confirm user action
function Confirm-Action {
    param ([string]$Message)
    $response = Read-Host "$Message (y/n)"
    return $response -match '^(y|Y)$'
}

# Function to create a folder
function Create-Folder {
    param ([string]$DefaultPath)
    $customPath = Read-Host "Default folder: $DefaultPath. Press Enter to accept or specify an alternative path"
    $targetPath = if ($customPath -eq "") { $DefaultPath } else { $customPath }

    if (-not (Test-Path $targetPath)) {
        Write-Host "Creating folder: $targetPath" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    } else {
        Write-Host "Folder already exists: $targetPath" -ForegroundColor Green
    }

    return $targetPath
}

# Function to clone a Git repository
function Clone-Repo {
    param ([string]$RepoUrl, [string]$TargetPath)
    Write-Host "Cloning repository into: $TargetPath"
    & git clone $RepoUrl $TargetPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Git clone failed! Check SSH key and repository access." -ForegroundColor Red
        exit 1
    }
}

# Function to create and activate a Conda environment
function Setup-CondaEnv {
    param ([string]$EnvFilePath)
    Write-Host "Creating Conda environment from: $EnvFilePath" -ForegroundColor Yellow
    & conda env create -f $EnvFilePath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create the Conda environment. Check the environment file." -ForegroundColor Red
        exit 1
    }
}

# Function to activate Conda environment and run setup.py
function Activate-EnvAndRunSetup {
    param ([string]$EnvName, [string]$RepoPath)
    Write-Host "Activating Conda environment: $EnvName" -ForegroundColor Yellow
    & conda activate $EnvName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to activate the Conda environment." -ForegroundColor Red
        exit 1
    }

    Set-Location $RepoPath
    Write-Host "Running python setup.py develop" -ForegroundColor Yellow
    & python setup.py develop
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to run setup.py. Check dependencies." -ForegroundColor Red
        exit 1
    }
}

# Main script workflow
Write-Host "Step 1: Checking for Miniconda and Git..." -ForegroundColor Cyan
if (-not (Check-Installed "conda")) {
    Install-Program "Anaconda.Miniconda3"
} else {
    Write-Host "Miniconda is already installed." -ForegroundColor Green
}

if (-not (Check-Installed "git")) {
    Install-Program "Git.Git"
} else {
    Write-Host "Git is already installed." -ForegroundColor Green
}

Write-Host "Step 2: Generating or displaying SSH key..." -ForegroundColor Cyan
Setup-SSHKey

Write-Host "Step 3: Confirming SSH key setup..." -ForegroundColor Cyan
if (-not (Confirm-Action "Have you added your SSH key to GitHub and verified access?")) {
    Write-Host "Please add your SSH key and retry." -ForegroundColor Red
    exit 1
}

Write-Host "Step 4: Setting up project..." -ForegroundColor Cyan
$defaultPath = "C:\Users\$([Environment]::UserName)\software"
$softwareFolder = Create-Folder -DefaultPath $defaultPath

$repoUrl = "git@github.com:qpit/pyrpl.git"
$repoPath = Join-Path -Path $softwareFolder -ChildPath "pyrpl"
Clone-Repo -RepoUrl $repoUrl -TargetPath $repoPath

Write-Host "Step 5: Setting up Conda environment..." -ForegroundColor Cyan
$envFilePath = Join-Path -Path $repoPath -ChildPath "rp_env.yml"
if (-not (Test-Path $envFilePath)) {
    Write-Host "Environment file not found: $envFilePath" -ForegroundColor Red
    exit 1
}
Setup-CondaEnv -EnvFilePath $envFilePath

Write-Host "Step 6: Activating environment and running setup.py..." -ForegroundColor Cyan
Activate-EnvAndRunSetup -EnvName "rp" -RepoPath $repoPath

Write-Host "Setup complete! Repository is ready, and environment is configured." -ForegroundColor Green