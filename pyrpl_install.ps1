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
    Run-GitBashCommand "cat ~/.ssh/id_rsa.pub" # This line displays the public key
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

    # Check if git command is available
    if (!(Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "Error: Git command not found. It seems Git is not correctly installed or not in your PATH." -ForegroundColor Red
        Write-Host "Please clone the repository manually using the following command:" -ForegroundColor Yellow
        Write-Host "git clone $RepoUrl '$TargetPath'" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "After cloning, press Enter to continue the script." -ForegroundColor Green
        Read-Host -Prompt "Waiting for manual clone..."
        # After manual clone, assume it was successful and continue.
        Write-Host "Continuing script after manual clone..." -ForegroundColor Green
        return # Exit the function to prevent the original git clone attempt
    }

    Write-Host "Cloning repository into: $TargetPath"
    & git clone $RepoUrl $TargetPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Git clone failed! Check SSH key and repository access. In case the local folder already exists under the specified path, please delete it manually and retry." -ForegroundColor Red
        Read-Host -Prompt "Press enter to continue or terminate the script with 'Ctrl+C'..."
    } else {
        Write-Host "Repository cloned successfully!" -ForegroundColor Green
    }
}

# Function to create and activate a conda environment
function Create-CondaEnv {
    param ([string]$EnvName)

    $condaPath = "$HOME\AppData\Local\miniconda3\shell\condabin\conda-hook.ps1"

    if (-not (Test-Path $condaPath)) {
        Write-Host "Conda not found at $condaPath" -ForegroundColor Red
        exit 1
    }

    Write-Host "Activating Conda hook from: $condaPath" -ForegroundColor Yellow
    & $condaPath

    Write-Host "Creating Conda environment: $EnvName" -ForegroundColor Yellow
    & conda create -n $EnvName python=3.13 -y
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create the Conda environment." -ForegroundColor Red
        Read-Host -Prompt "Press enter to exit..."
        exit 1
    } else {
        Write-Host "Conda '$EnvName' environment created successfully!" -ForegroundColor Green
    }

    Write-Host "Activating Conda environment: $EnvName" -ForegroundColor Yellow
    & conda activate $EnvName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to activate the Conda environment $EnvName." -ForegroundColor Red
        Read-Host -Prompt "Press enter to exit..."
        exit 1
    }
}

function Build-AndInstall-Pyrpl {
    param ([string]$RepoPath)
    Set-Location $RepoPath
    Write-Host "Running python setup.py bdist_wheel" -ForegroundColor Yellow
    & python setup.py bdist_wheel
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to build the Pyrpl package." -ForegroundColor Red
        Read-Host -Prompt "Press enter to exit..."
        exit 1
    }

    $whlFile = Get-ChildItem -Path "$RepoPath\dist" -Filter "pyrpl-*.whl" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($whlFile) {
        $whlPath = $whlFile.FullName
        Write-Host "Installing Pyrpl package from: $whlPath" -ForegroundColor Yellow
        & pip install $whlPath        
    } else {
        Write-Host "Pyrpl wheel file not found in the dist folder." -ForegroundColor Red
    }

    # This Read-Host is now outside the if block
    if ($LASTEXITCODE -ne 0) { 
        Write-Host "Failed to install Pyrpl." -ForegroundColor Red
        Read-Host -Prompt "Press enter to exit..."
        exit 1
    }
}

# Function to perform complete installation
function Complete-Installation {
    # Install conda and git using winget
    Write-Host "`r`n=======================================================`r`nStep 1: Installing conda and git..." -ForegroundColor Cyan
    Install-Software -Name "conda" -WingetId "Anaconda.Miniconda3"
    Install-Software -Name "git" -WingetId "Git.Git"

    Write-Host "`r`n=======================================================`r`nStep 2: Generating or displaying SSH key..." -ForegroundColor Cyan
    Setup-SSHKey

    Write-Host "`r`n=======================================================`r`nStep 3: Adding SSH key to GitHub..." -ForegroundColor Cyan
    Write-Host "To allow access to the repository, you need to add your public SSH key to your GitHub account." -ForegroundColor Yellow
    Write-Host "1. Go to your GitHub settings: https://github.com/settings/keys"
    Write-Host "2. Click 'New SSH key'."
    Write-Host "3. Give your key a title (e.g., 'My Laptop')."
    Write-Host "4. Paste the public key (displayed above) into the 'Key' field."
    Write-Host "5. Click 'Add SSH key'."

    # Ensure the user is a member of the organization with access to the repository
    Write-Host "`nPlease also ensure that your GitHub account is a member of the 'qpit' organization and has access to the 'pyrpl' repository." -ForegroundColor Yellow

    Read-Host -Prompt "Press Enter to continue after adding the SSH key and confirming organization membership..."

    Write-Host "`r`n=======================================================`r`nStep 4: Setting up project..." -ForegroundColor Cyan
    Write-Host "If you are being asked if you want to continue connecting, answer 'yes'." -ForegroundColor Yellow
    $defaultPath = [System.IO.Path]::Combine($HOME, "software")
    $softwareFolder = Create-Folder -DefaultPath $defaultPath

    $repoUrl = "git@github.com:qpit/pyrpl.git"
    $repoPath = Join-Path -Path $softwareFolder -ChildPath "pyrpl"
    Clone-Repo -RepoUrl $repoUrl -TargetPath $repoPath

    Write-Host "`r`n=======================================================`r`nStep 5: Setting up Conda environment..." -ForegroundColor Cyan
    $envName = Read-Host "Enter the name for the Conda environment (default: rp): "
    if ($envName -eq "") { $envName = "rp" }
    Create-CondaEnv -EnvName $envName

    Write-Host "`r`n=======================================================`r`nStep 6: Building and installing Pyrpl..." -ForegroundColor Cyan
    Build-AndInstall-Pyrpl -RepoPath $repoPath
}

# Function to install pyrpl in current environment
function Install-InCurrentEnv {
    Write-Host "`r`n=======================================================`r`nStep 1: Generating or displaying SSH key..." -ForegroundColor Cyan
    Setup-SSHKey

    Write-Host "`r`n=======================================================`r`nStep 3: Adding SSH key to GitHub..." -ForegroundColor Cyan
    Write-Host "To allow access to the repository, you need to add your public SSH key to your GitHub account." -ForegroundColor Yellow
    Write-Host "1. Go to your GitHub settings: https://github.com/settings/keys"
    Write-Host "2. Click 'New SSH key'."
    Write-Host "3. Give your key a title (e.g., 'My Laptop')."
    Write-Host "4. Paste the public key (displayed above) into the 'Key' field."
    Write-Host "5. Click 'Add SSH key'."

    # Ensure the user is a member of the organization with access to the repository
    Write-Host "`nPlease also ensure that your GitHub account is a member of the 'qpit' organization and has access to the 'pyrpl' repository." -ForegroundColor Yellow

    Read-Host -Prompt "Press Enter to continue after adding the SSH key and confirming organization membership..."

    Write-Host "`r`n=======================================================`r`nStep 3: Setting up project..." -ForegroundColor Cyan
    Write-Host "If you are being asked if you want to continue connecting, answer 'yes'." -ForegroundColor Yellow
    $defaultPath = [System.IO.Path]::Combine($HOME, "software")
    $softwareFolder = Create-Folder -DefaultPath $defaultPath

    $repoUrl = "git@github.com:qpit/pyrpl.git"
    $repoPath = Join-Path -Path $softwareFolder -ChildPath "pyrpl"
    Clone-Repo -RepoUrl $repoUrl -TargetPath $repoPath

    Write-Host "`r`n=======================================================`r`nStep 4: Checking for pip..." -ForegroundColor Cyan
    if (!(Get-Command pip -ErrorAction SilentlyContinue)) {
        Write-Host "pip is not available in the current environment." -ForegroundColor Red
        Read-Host -Prompt "Press enter to exit..."
        exit 1
    }

    Write-Host "`r`n=======================================================`r`nStep 5: Building and installing Pyrpl..." -ForegroundColor Cyan
    Build-AndInstall-Pyrpl -RepoPath $repoPath
}

# Main script workflow

# Ask the user for installation type
Write-Host "Choose installation type:"
Write-Host "1. Complete Installation (includes miniconda, git, and new environment) [Default]" -ForegroundColor Green
Write-Host "2. Install in current environment (not recommended)" -ForegroundColor Yellow
$installationType = Read-Host "Enter your choice (1 or 2)"

switch ($installationType) {
    "2" { # Only if the user explicitly enters '2'
        Install-InCurrentEnv
    }
    default { # This will include an empty input or any other input besides '2'
        Complete-Installation
    }
}

Write-Host "`r`n=======================================================`r`nSetup complete! Repository is ready, and environment is activated and configured. Remember that this environment needs to be active for pyrpl to work." -ForegroundColor Green