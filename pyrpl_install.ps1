function Install-Software {
    param (
        [string]$Name,
        [string]$WingetId
    )
    
    if (!(Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Host "Installing $Name..." -ForegroundColor Yellow
        winget install --id $WingetId --silent --accept-package-agreements
    } else {
        Write-Host "$Name is already installed." -ForegroundColor Yellow
    }
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


# Helper function to run a command in Git Bash
function Run-GitBashCommand {
    param ([string]$Command)
    $gitBashExe = "$($Env:ProgramFiles)\Git\bin\bash.exe"
    if (-not (Test-Path $gitBashExe)) {
        Write-Host "Git Bash executable not found!" -ForegroundColor Red
        Read-Host -Prompt "Press enter to exit..."
        exit 1
    }
    & $gitBashExe -c $Command
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
        Write-Host "Git clone failed! Check SSH key and repository access. In case the local folder already exists under the specified path, please delete it manually and retry." -ForegroundColor Red
        Read-Host -Prompt "Press enter to continue or terminate the script with 'Ctrl+C'..."
    } else {
        Write-Host "Repository cloned successfully!" -ForegroundColor Green
    }
}

# Setting up Conda environment according to environment file
function Setup-CondaEnv {
    param ([string]$EnvFilePath)
    
    $condaPath = "$HOME\AppData\Local\miniconda3\shell\condabin\conda-hook.ps1"
    
    if (-not (Test-Path $condaPath)) {
        Write-Host "Conda not found at $condaPath" -ForegroundColor Red
        exit 1
    }

    $condaBaseEnvPath = Split-Path (Split-Path $condaPath -Parent) -Parent

    Write-Host "Activating Conda hook from: $condaPath" -ForegroundColor Yellow
    & $condaPath
    Write-Host "Activating Conda environment from: $condaBaseEnvPath" -ForegroundColor Yellow
    & conda activate $condaBaseEnvPath
    Write-Host "Creating Conda environment from: $EnvFilePath" -ForegroundColor Yellow
    & conda env create --file=$EnvFilePath
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create the Conda environment. Check the environment file." -ForegroundColor Red
        Read-Host -Prompt "Press enter to exit..."
        exit 1
    } else {
        Write-Host "Conda 'rp' environment created successfully!" -ForegroundColor Green
    }
}


# Function to activate Conda environment and run setup.py
function Activate-EnvAndRunSetup {
    param ([string]$EnvName, [string]$RepoPath)
    Write-Host "Activating Conda environment: $EnvName" -ForegroundColor Yellow
    & conda activate $EnvName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to activate the Conda environment $EnvName." -ForegroundColor Red
        Read-Host -Prompt "Press enter to exit..."
        exit 1
    }

    Set-Location $RepoPath
    Write-Host "Running python setup.py develop" -ForegroundColor Yellow
    & python setup.py develop
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to run setup.py. Check dependencies." -ForegroundColor Red
        Read-Host -Prompt "Press enter to exit..."
        exit 1
    }
}

# Main script workflow
Read-Host -Prompt "Press enter to start installation..."
# Install conda and git using winget
Write-Host "`r`n=======================================================`r`nStep 1: Installing conda and git..." -ForegroundColor Cyan
Install-Software -Name "conda" -WingetId "Anaconda.Miniconda3"
Install-Software -Name "git" -WingetId "Git.Git"


Write-Host "`r`n=======================================================`r`nStep 2: Generating or displaying SSH key..." -ForegroundColor Cyan
Setup-SSHKey

Write-Host "`r`n=======================================================`r`nStep 3: Confirming SSH key setup..." -ForegroundColor Cyan
if (-not (Confirm-Action "Please enter 'y' after you added the public SSH key to your GitHub account. Also ensure that your GitHub account has access to the repository.")) {
    Write-Host "Please add your SSH key and retry." -ForegroundColor Red
    Read-Host -Prompt "Press enter to exit..."
    exit 1
}

Write-Host "`r`n=======================================================`r`nStep 4: Setting up project..." -ForegroundColor Cyan
$defaultPath = [System.IO.Path]::Combine($HOME, "software")
$softwareFolder = Create-Folder -DefaultPath $defaultPath

$repoUrl = "git@github.com:qpit/pyrpl.git"
$repoPath = Join-Path -Path $softwareFolder -ChildPath "pyrpl"
Clone-Repo -RepoUrl $repoUrl -TargetPath $repoPath

Write-Host "`r`n=======================================================`r`nStep 5: Setting up Conda environment..." -ForegroundColor Cyan
$envFilePath = Join-Path -Path $repoPath -ChildPath "rp_env.yml"
if (-not (Test-Path $envFilePath)) {
    Write-Host "Environment file not found: $envFilePath" -ForegroundColor Red
    Read-Host -Prompt "Press enter to exit..."
    exit 1
}
Setup-CondaEnv -EnvFilePath $envFilePath

Write-Host "`r`n=======================================================`r`nStep 6: Activating environment and running setup.py..." -ForegroundColor Cyan
Activate-EnvAndRunSetup -EnvName "rp" -RepoPath $repoPath

Write-Host "`r=======================================================``Setup complete! Repository is ready, and environment is configured." -ForegroundColor Green