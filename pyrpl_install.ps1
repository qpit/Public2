function Install-Software {
    param (
        [string]$Name,
        [string]$WingetId,
        [string]$Version
    )

    if (!(Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Host "Installing $Name..." -ForegroundColor Yellow
        winget install --id $WingetId --silent --accept-package-agreements --version $Version
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

function Run-GitBashCommand {
    param ([string]$Command)

    # Helper to test and return a candidate path if it exists
    function Get-ValidPath([string]$path) {
        if (Test-Path $path) {
            return $path
        } else {
            return $null
        }
    }

    $candidates = @()

    # 1. Registry key GitForWindows under HKLM
    try {
        $lm = Get-ItemProperty -Path 'HKLM:\Software\GitForWindows' -ErrorAction Stop
        if ($lm.InstallPath) {
            $p = Join-Path $lm.InstallPath 'bin\bash.exe'
            Write-Host "[HKLM GitForWindows] candidate: $p"
            $candidates += $p
        }
    } catch {}

    # 2. Registry key GitForWindows under HKCU
    try {
        $cu = Get-ItemProperty -Path 'HKCU:\Software\GitForWindows' -ErrorAction Stop
        if ($cu.InstallPath) {
            $p = Join-Path $cu.InstallPath 'bin\bash.exe'
            $candidates += $p
        }
    } catch {}

    # 3. Uninstall entry fallback (Git_is1)
    $uninstKeys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Git_is1',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Git_is1',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Git_is1'
    )
    foreach ($key in $uninstKeys) {
        try {
            $u = Get-ItemProperty -Path $key -ErrorAction Stop
            if ($u.InstallLocation) {
                $p = Join-Path $u.InstallLocation 'bin\bash.exe'
                $candidates += $p
            }
            elseif ($u.DisplayIcon) {
                $exe = ($u.DisplayIcon -split '"')[1]
                $root = Split-Path $exe -Parent
                $p = Join-Path $root 'bin\bash.exe'
                $candidates += $p
            }
        } catch {}
    }

    # 4. Well‑known fallback paths
    $fallbacks = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "$env:ProgramFiles(x86)\Git\bin\bash.exe",
        "$env:LocalAppData\Programs\Git\bin\bash.exe"
    )
    foreach ($p in $fallbacks) {
        $candidates += $p
    }

    # 5. Pick and report the first existing path
    $gitBashExe = $candidates |
        ForEach-Object { Get-ValidPath $_ } |
        Where-Object { $_ } |
        Select-Object -First 1

    if (-not $gitBashExe) {
        Write-Host "Git Bash executable not found via any method." -ForegroundColor Red
        Read-Host -Prompt "Press enter to exit..."
        exit 1
    }

    Write-Host "Using Git Bash executable: $gitBashExe" -ForegroundColor Green
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
        Write-Host "Error: Git clone failed. This may happen if git is not found or a folder with the same name already exists." -ForegroundColor Red
        Write-Host "Please clone the repository manually using the following command from withing Git Bash:" -ForegroundColor Yellow
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

    # 1. Gather all condabin hook paths from registry Uninstall entries
    $hookPaths = @()
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstallRoots) {
        Get-ChildItem $root -ErrorAction SilentlyContinue |
          Get-ItemProperty -ErrorAction SilentlyContinue |
          Where-Object { $_.DisplayName -match 'Anaconda|Miniconda' } |
          ForEach-Object {
              $p = $null # Initialize $p for each loop iteration
              if ($_.InstallLocation) {
                  $p = Join-Path $_.InstallLocation 'shell\condabin\conda-hook.ps1'
                  Write-Host "[Registry InstallLocation] candidate: $p"
              }
              elseif ($_.UninstallString) {
                  # Correctly handle quoted uninstall strings
                  $exePath = $_.UninstallString
                  if ($exePath -match '"([^"]+)"') {
                    $exePath = $matches[1]
                  }
                  $installRoot = Split-Path $exePath -Parent
                  $p = Join-Path $installRoot 'shell\condabin\conda-hook.ps1'
                  Write-Host "[Registry UninstallString] candidate: $p"
              }

              if ($p -and (Test-Path $p)) {
                  Write-Host "Added valid hook path: $p" -ForegroundColor Green
                  $hookPaths += $p
              } else {
                  if ($p) { # Only write this message if a candidate path was actually formed
                    Write-Host "Path not found, skipping: $p" -ForegroundColor Yellow
                  }
              }
          }
    }

    # 2. Pick the best hook path: per-user > localappdata > system
    $condaPath = $hookPaths |
      Sort-Object {
          if ($_ -like "$($env:USERPROFILE)*") {
              0 # Highest priority for user profile paths
          }
          elseif ($_ -like "$($env:LOCALAPPDATA)*") {
              1 # Second priority for local app data paths
          }
          else {
              2 # Lowest priority for all other (e.g., system) paths
          }
      } |
      Select-Object -First 1

    if ($condaPath) {
        Write-Host "Using conda hook at: $condaPath" -ForegroundColor Yellow
    }
    else {
        Write-Host 'No valid conda-hook.ps1 found.' -ForegroundColor Red
        Read-Host -Prompt "Press Enter to exit…"
        exit 1
    }

    # 3. Activate and create the environment
    Write-Host "Activating Conda hook..." -ForegroundColor Cyan
    & $condaPath

    Write-Host "Creating Conda environment: $EnvName" -ForegroundColor Yellow
    & conda create -n $EnvName python=3.13 -y
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create the Conda environment." -ForegroundColor Red
        Read-Host -Prompt "Press Enter to exit..."
        exit 1
    } else {
        Write-Host "Conda '$EnvName' environment created successfully!" -ForegroundColor Green
    }

    Write-Host "Activating Conda environment: $EnvName" -ForegroundColor Yellow
    & conda activate $EnvName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to activate the Conda environment $EnvName." -ForegroundColor Red
        Read-Host -Prompt "Press Enter to exit..."
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
        Read-Host -Prompt "Press enter to exit..."
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
    Install-Software -Name "conda" -WingetId "Anaconda.Miniconda3" -Version py313_25.3.1-1
    Install-Software -Name "git" -WingetId "Git.Git" -Version 2.42.0.2

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