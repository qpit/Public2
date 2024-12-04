function Install-Software {
    param (
        [string]$Name,
        [string]$WingetId
    )
    
    if (!(Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Host "Installing $Name..." -ForegroundColor Yellow
        winget install --id $WingetId --silent --accept-package-agreements
    } else {
        Write-Host "$Name is already installed." -ForegroundColor Green
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
    }
}

# Function to find Anaconda executable
function Find-CondaPath {
    # Potential default Conda installation paths
    $defaultPaths = @(
        "$env:USERPROFILE\Miniconda3\Scripts\conda.exe",
        "$env:USERPROFILE\Anaconda3\Scripts\conda.exe", 
        "$env:ProgramData\Miniconda3\Scripts\conda.exe",
        "C:\ProgramData\Miniconda3\Scripts\conda.exe",
        "C:\Program Files\Miniconda3\Scripts\conda.exe"
    )

    # Check default paths
    $foundPath = $defaultPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($foundPath) {
        Write-Host "Found Conda at: $foundPath" -ForegroundColor Green
        return $foundPath
    }

    # Prompt user if not found
    $manualPath = Read-Host "Conda executable not found. Please provide the full path to conda.exe"
    
    if (Test-Path $manualPath) {
        Write-Host "Manually provided path verified." -ForegroundColor Green
        return $manualPath
    }

    Write-Host "Could not locate Conda executable!" -ForegroundColor Red
    return $null
}

# Modify the script to use a global variable to store the Conda path
$global:CondaPath = $null

# Setup-CondaEnv to use the global Conda path
function Setup-CondaEnv {
    param ([string]$EnvFilePath)
    
    $global:CondaPath = Find-CondaPath

    if (-not $global:CondaPath) {
        Write-Host "Cannot proceed without Conda executable." -ForegroundColor Red
        return
    }

    Write-Host "Creating Conda environment from: $EnvFilePath" -ForegroundColor Yellow
    & $global:CondaPath env create -f $EnvFilePath
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create the Conda environment." -ForegroundColor Red
    }
}

# Function to activate Conda environment and run setup.py
function Activate-EnvAndRunSetup {
    param ([string]$EnvName, [string]$RepoPath)
    Write-Host "Activating Conda environment: $EnvName" -ForegroundColor Yellow
    & conda activate $EnvName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to activate the Conda environment." -ForegroundColor Red
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
# Install conda and git using winget
Install-Software -Name "conda" -WingetId "Anaconda.Miniconda3"
Install-Software -Name "git" -WingetId "Git.Git"


Write-Host "Step 2: Generating or displaying SSH key..." -ForegroundColor Cyan
Setup-SSHKey

Write-Host "Step 3: Confirming SSH key setup..." -ForegroundColor Cyan
if (-not (Confirm-Action "Have you added your SSH key to GitHub and verified access?")) {
    Write-Host "Please add your SSH key and retry." -ForegroundColor Red
    Read-Host -Prompt "Press enter to exit..."
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
    Read-Host -Prompt "Press enter to exit..."
    exit 1
}
Setup-CondaEnv -EnvFilePath $envFilePath

Write-Host "Step 6: Activating environment and running setup.py..." -ForegroundColor Cyan
Activate-EnvAndRunSetup -EnvName "rp" -RepoPath $repoPath

Write-Host "Setup complete! Repository is ready, and environment is configured." -ForegroundColor Green