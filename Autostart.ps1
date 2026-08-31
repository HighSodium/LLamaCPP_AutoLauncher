$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ModelsDir = Join-Path $ScriptDir "models"
$ConfigFile = Join-Path $ScriptDir "config.json"

if (-not (Test-Path $ModelsDir)) 
{
    Write-Host "Error: 'models' folder not found at $ModelsDir" -ForegroundColor Red
    Exit
}

# get only .gguf files (excluding mmproj and mtp files from the main selection menu)
$Models = @(Get-ChildItem -Path $ModelsDir -Filter "*.gguf" | 
          Where-Object { $_.Name -notlike "*.mmproj.gguf" -and $_.Name -notlike "*.mtp.gguf" } | 
          Select-Object -ExpandProperty Name)

if ($Models.Count -eq 0) 
{
    Write-Host "No base .gguf models found in $ModelsDir" -ForegroundColor Yellow
    Exit
}

# # ========== VARIABLES ==========

$Selection = 0
$ParsedContext = 0
$ParsedThinking = 0
$ParsedMtp = 0
$SelectedModel = $null
$ContextSize = 50000
$Thinking = "off"
$IsMtpModel = "off"
$HasHistory = $false

# ========== CONFIG HANDLING ==========
if (Test-Path $ConfigFile) {
    $Config = Get-Content $ConfigFile | ConvertFrom-Json
    # Ensure the saved model file still exists in the folder
    if ($Models -contains $Config.LastModel) 
    {
        $HasHistory = $true
    }
}

# ========== MENU CREATION ==========
Write-Host "--- Available GGUF Models ---" -ForegroundColor Cyan
if ($HasHistory) 
{
    Write-Host " LOAD LAST USED: $($Config.LastModel) (Context: $($Config.ContextSize)) (Thinking: $($Config.Thinking)) (MTP: $($Config.IsMtpModel))" -ForegroundColor Yellow
}

for ($i = 0; $i -lt $Models.Count; $i++) 
{
    Write-Host "[$($i + 1)] $($Models[$i])"
}

# ========== INPUT HANDLING ==========
Write-Host ""
$SelectionInput = Read-Host "Select an option number"

# running into invalid [ref] usage...
if (-not [int]::TryParse($SelectionInput, [ref]$Selection)) 
{
    Write-Host "`$SelectionInput` is not a number. Please enter a number..." -ForegroundColor Red
    Exit
}

# auto-selection
if ($Selection -eq 0 -and $HasHistory) 
{
    $SelectedModel = $Config.LastModel
    $ContextSize = $Config.ContextSize
    $Thinking = $Config.Thinking
    if ($Config.IsMtpModel) 
    { 
        $IsMtpModel = $Config.IsMtpModel 
    }
} 
elseif ($Selection -ge 1 -and $Selection -le $Models.Count) 
{
    
    $SelectedModel = $Models[$Selection - 1]
    Write-Host ""
    $ContextInput = Read-Host "Enter context size (Press Enter for default $ContextSize)"
    
    # MAKE SURE THEY ARE USING A NUMBER else use default
    if (-not [string]::IsNullOrWhiteSpace($ContextInput)) 
    {
        if ([int]::TryParse($ContextInput, [ref]$ParsedContext)) 
        {
            $ContextSize = $ParsedContext
        } else {
            Write-Host "Invalid context number. Using default 4096." -ForegroundColor Yellow
        }
    }

    # ========== ASK for thinking ==========
    $ThinkingInput = Read-Host "Enable thinking (1 for true | Any for False)"
    if (-not [string]::IsNullOrWhiteSpace($ThinkingInput)) 
    {
        if ([int]::TryParse($ThinkingInput, [ref]$ParsedThinking)) 
        {
            if($ParsedThinking -eq 1)
            {
                $Thinking = "on"
            }
        }
    }

    # ========== CHECK FOR MTP FILE FIRST BEFORE ASKING ==========
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($SelectedModel)
    $MtpFile = Join-Path $ModelsDir "$BaseName.mtp.gguf"

    if (Test-Path $MtpFile) 
    {
        # File found! Auto-enable MTP and skip the question
        $IsMtpModel = "on"
        Write-Host "-> Auto-detected sidecar draft file. Skipping MTP compatibility question." -ForegroundColor Cyan
    } 
    else 
    {
        # We need handle what happens if there is no MTP file but there is a built in MTP head
        $MtpInput = Read-Host "Is this an MTP (Multi Token Predict) compatible model? (1 for true | Any for False)"
        if (-not [string]::IsNullOrWhiteSpace($MtpInput)) 
        {
            if ([int]::TryParse($MtpInput, [ref]$ParsedMtp)) 
            {
                if($ParsedMtp -eq 1){
                    $IsMtpModel = "on"
                }
            }
        }
    }

    # ========== CONFIG SAVE ==========
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

# if there are additional MMPROJ and MTP files, we need to find them
$BaseName = [System.IO.Path]::GetFileNameWithoutExtension($SelectedModel)
$Alias = $SelectedModel -split '\.'
$ModelPath = Join-Path $ModelsDir $SelectedModel

# ========== MMPROJ and MTP HANDLING ==========
$ExtraArgs = ""

$MmprojFile = Join-Path $ModelsDir "$BaseName.mmproj.gguf"
if (Test-Path $MmprojFile) 
{
    Write-Host "-> Found matching Vision Model: $BaseName.mmproj.gguf" -ForegroundColor Cyan
    $ExtraArgs += " --mmproj \`"$MmprojFile\`""
}

$MtpFile = Join-Path $ModelsDir "$BaseName.mtp.gguf"
if (Test-Path $MtpFile) 
{
    Write-Host "-> Found matching Speculative Draft Model: $BaseName.mtp.gguf" -ForegroundColor Cyan
    $ExtraArgs += " --spec-draft-model \`"$MtpFile\`""
}

if ($IsMtpModel -eq "on") 
{
    $ExtraArgs += " --spec-type draft-mtp"
}

Write-Host "`nSpawning llama-server in a fresh window..." -ForegroundColor Green
Write-Host "Model: $SelectedModel | Context: $ContextSize | Thinking: $Thinking | MTP: $IsMtpModel`n" -ForegroundColor Green

# ========== PARAM APPENDING ==========
$Executable = Join-Path $ScriptDir "src\llama-server.exe"
$Arguments = "-m \`"$ModelPath\`" --alias \`"$Alias\`" -c $ContextSize --reasoning $Thinking -ngl -1 --flash-attn on $ExtraArgs"

# ran into issue of llama.cpp not being there
if (-not (Test-Path $Executable)) 
{
    Write-Host "Error: Could not find llama-server.exe at $Executable" -ForegroundColor Red
    Write-Host "Please make sure your llama.cpp server binaries are inside the 'src' folder." -ForegroundColor Yellow
    Exit
}

# ========== EXIT ==========

Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "& `"$Executable`" $Arguments"

# left exit out to see full terminal results
#Exit
