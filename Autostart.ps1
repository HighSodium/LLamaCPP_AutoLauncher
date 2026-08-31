# 1. Define paths (looks for 'models' and 'src\llama-server.exe' right next to the script)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ModelsDir = Join-Path $ScriptDir "models"
$ConfigFile = Join-Path $ScriptDir "config.json"

# 2. Check if models folder exists
if (-not (Test-Path $ModelsDir)) {
    Write-Host "Error: 'models' folder not found at $ModelsDir" -ForegroundColor Red
    Exit
}

# 3. Get only .gguf files (excluding mmproj and mtp sidecar files from the main selection menu)
$Models = @(Get-ChildItem -Path $ModelsDir -Filter "*.gguf" | 
          Where-Object { $_.Name -notlike "*.mmproj.gguf" -and $_.Name -notlike "*.mtp.gguf" } | 
          Select-Object -ExpandProperty Name)

if ($Models.Count -eq 0) {
    Write-Host "No base .gguf models found in $ModelsDir" -ForegroundColor Yellow
    Exit
}

# Initialize variables to prevent the [ref] error
$Selection = 0
$ParsedContext = 0
$ParsedThinking = 0
$ParsedMtp = 0
$SelectedModel = $null
$ContextSize = 50000
$Thinking = "off"
$IsMtpModel = "off"
$HasHistory = $false

# 4. Check for a saved configuration from last time
if (Test-Path $ConfigFile) {
    $Config = Get-Content $ConfigFile | ConvertFrom-Json
    # Ensure the saved model file still exists in the folder
    if ($Models -contains $Config.LastModel) {
        $HasHistory = $true
    }
}

# 5. Display the menu
Write-Host "--- Available GGUF Models ---" -ForegroundColor Cyan
if ($HasHistory) {
    Write-Host " LOAD LAST USED: $($Config.LastModel) (Context: $($Config.ContextSize)) (Thinking: $($Config.Thinking)) (MTP: $($Config.IsMtpModel))" -ForegroundColor Yellow
}
for ($i = 0; $i -lt $Models.Count; $i++) {
    Write-Host "[$($i + 1)] $($Models[$i])"
}

# 6. Get and validate user selection
Write-Host ""
$SelectionInput = Read-Host "Select an option number"

# Parsed variable now safely exists before using [ref]
if (-not [int]::TryParse($SelectionInput, [ref]$Selection)) {
    Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
    Exit
}

# 7. Process selection and determine context size
if ($Selection -eq 0 -and $HasHistory) {
    # Load last used parameters
    $SelectedModel = $Config.LastModel
    $ContextSize = $Config.ContextSize
    $Thinking = $Config.Thinking
    if ($Config.IsMtpModel) { $IsMtpModel = $Config.IsMtpModel }
} elseif ($Selection -ge 1 -and $Selection -le $Models.Count) {
    # Select a new model and prompt for custom context size
    $SelectedModel = $Models[$Selection - 1]
    Write-Host ""
    $ContextInput = Read-Host "Enter context size (Press Enter for default $ContextSize)"
    
    # Safe check for optional context size entry
    if (-not [string]::IsNullOrWhiteSpace($ContextInput)) {
        if ([int]::TryParse($ContextInput, [ref]$ParsedContext)) {
            $ContextSize = $ParsedContext
        } else {
            Write-Host "Invalid context number. Using default 4096." -ForegroundColor Yellow
        }
    }

    # ====== ASK for thinking
    $ThinkingInput = Read-Host "Enable thinking (1 for true | Any for False)"
    if (-not [string]::IsNullOrWhiteSpace($ThinkingInput)) {
        if ([int]::TryParse($ThinkingInput, [ref]$ParsedThinking)) {
            if($ParsedThinking -eq 1){
                $Thinking = "on"
            }
        }
    }

    # ====== CHECK FOR MTP FILE FIRST BEFORE ASKING
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($SelectedModel)
    $MtpFile = Join-Path $ModelsDir "$BaseName.mtp.gguf"

    if (Test-Path $MtpFile) {
        # File found! Auto-enable MTP and skip the question
        $IsMtpModel = "on"
        Write-Host "-> Auto-detected sidecar draft file. Skipping MTP compatibility question." -ForegroundColor Cyan
    } else {
        # No file found, ask the manual configuration question
        $MtpInput = Read-Host "Is this an MTP (Multi Token Predict) compatible model? (1 for true | Any for False)"
        if (-not [string]::IsNullOrWhiteSpace($MtpInput)) {
            if ([int]::TryParse($MtpInput, [ref]$ParsedMtp)) {
                if($ParsedMtp -eq 1){
                    $IsMtpModel = "on"
                }
            }
        }
    }

    # Save these fresh settings to the config file
    $NewConfig = @{
        LastModel   = $SelectedModel
        ContextSize = $ContextSize
        Thinking    = $Thinking
        IsMtpModel  = $IsMtpModel
    }
    $NewConfig | ConvertTo-Json | Out-File $ConfigFile -Force
} else {
    Write-Host "Invalid selection." -ForegroundColor Red
    Exit
}

# 8. Extract the alias and compile final arguments
$BaseName = [System.IO.Path]::GetFileNameWithoutExtension($SelectedModel)
$Alias = $SelectedModel -split '\.'
$ModelPath = Join-Path $ModelsDir $SelectedModel

# Dynamic addition for MMPROJ and MTP sidecars
$ExtraArgs = ""

$MmprojFile = Join-Path $ModelsDir "$BaseName.mmproj.gguf"
if (Test-Path $MmprojFile) {
    Write-Host "-> Found matching Vision Model: $BaseName.mmproj.gguf" -ForegroundColor Cyan
    $ExtraArgs += " --mmproj \`"$MmprojFile\`""
}

# Re-verify and append the actual draft file flag if the file exists
$MtpFile = Join-Path $ModelsDir "$BaseName.mtp.gguf"
if (Test-Path $MtpFile) {
    Write-Host "-> Found matching Speculative Draft Model: $BaseName.mtp.gguf" -ForegroundColor Cyan
    $ExtraArgs += " --spec-draft-model \`"$MtpFile\`""
}

# Dynamic building of speculative execution string based on MTP capability or file presence
if ($IsMtpModel -eq "on") {
    $ExtraArgs += " --spec-type draft-mtp"
}

Write-Host "`nSpawning llama-server in a fresh window..." -ForegroundColor Green
Write-Host "Model: $SelectedModel | Context: $ContextSize | Thinking: $Thinking | MTP: $IsMtpModel`n" -ForegroundColor Green

# 9. Define parameters and launch (Points to the src folder and llama-server.exe)
$Executable = Join-Path $ScriptDir "src\llama-server.exe"
$Arguments = "-m \`"$ModelPath\`" --alias \`"$Alias\`" -c $ContextSize --reasoning $Thinking -ngl -1 --flash-attn on $ExtraArgs"

# Double check that the executable actually exists where we expect it
if (-not (Test-Path $Executable)) {
    Write-Host "Error: Could not find llama-server.exe at $Executable" -ForegroundColor Red
    Write-Host "Please make sure your llama.cpp server binaries are inside the 'src' folder." -ForegroundColor Yellow
    Exit
}

# Safe Security Launch: Call a native PowerShell window to anchor the executable window process safely
Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "& `"$Executable`" $Arguments"

# 10. Instantly close this setup menu session
#Exit
