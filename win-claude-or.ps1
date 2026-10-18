$ErrorActionPreference = 'Stop'
$Arguments = @($args)
$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $ScriptPath
$Repo = 'dariusz-przada/claude-or'
$UserHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
$ConfigDir = if ($env:WIN_CLAUDE_OR_CONFIG) { $env:WIN_CLAUDE_OR_CONFIG } else { Join-Path $UserHome '.config\claude-or' }
$AliasFile = Join-Path $ConfigDir 'aliases.json'
$KeysFile = Join-Path $ConfigDir 'keys.json'
$AliasBin = Join-Path $UserHome '.local\bin'

function Fail([string] $Message) { throw "win-claude-or: $Message" }

function Ensure-Config {
    if (-not (Test-Path -LiteralPath $ConfigDir)) { New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $AliasFile)) {
        Copy-Item -LiteralPath (Join-Path $ScriptDir 'aliases.json') -Destination $AliasFile -Force
    }
}

function Read-Aliases {
    Ensure-Config
    try { Get-Content -LiteralPath $AliasFile -Raw | ConvertFrom-Json } catch { Fail "invalid aliases file: $AliasFile" }
}

function Save-Json($Object, [string] $Path) {
    $tmp = "$Path.tmp.$PID"
    $Object | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-AliasNames($Config) {
    if ($null -eq $Config.aliases) { return @() }
    @($Config.aliases.PSObject.Properties.Name)
}

function Get-AliasEntry($Config, [string] $Name) {
    $p = $Config.aliases.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    $p.Value
}

function Require-Alias($Config, [string] $Name) {
    $entry = Get-AliasEntry $Config $Name
    if ($null -eq $entry) { Fail "alias '$Name' not found in $AliasFile (see --list)" }
    $entry
}

function Test-AliasName([string] $Name) {
    if ($Name -notmatch '^[A-Za-z0-9_.-]+$' -or $Name -eq 'win-claude-or') { Fail "invalid alias name '$Name' (use letters, digits, ., _ or -)" }
    if (Get-Command $Name -ErrorAction SilentlyContinue) { Fail "'$Name' is already a command in PATH" }
}

function Get-ModelInfo([string] $Model) {
    try {
        $catalog = Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/models' -TimeoutSec 20
        $info = @($catalog.data | Where-Object { $_.id -eq $Model }) | Select-Object -First 1
        if ($null -eq $info) { Fail "model '$Model' not found on OpenRouter" }
        if (@($info.supported_parameters) -notcontains 'tools') { Write-Warning "'$Model' does not list tool support; Claude Code needs tool calls" }
        return $info
    } catch [System.Management.Automation.RuntimeException] { throw }
    catch { Write-Warning "could not reach OpenRouter; model '$Model' was not verified"; return $null }
}

function Show-Table($Rows) {
    if (@($Rows).Count -eq 0) { return }
    $Rows | Format-Table -AutoSize | Out-Host
}

function Show-Aliases {
    $c = Read-Aliases
    $rows = foreach ($name in (Get-AliasNames $c)) {
        $e = Get-AliasEntry $c $name
        [pscustomobject]@{ ALIAS=$name; MODEL=$e.model; CONTEXT=$(if ($e.context) { $e.context } else { '-' }); 'BACKGROUND MODEL'=$(if ($e.small) { $e.small } elseif ($c.defaults.small) { $c.defaults.small } else { '-' }); LINK=$(if ($e.link -eq $false) { 'off' } else { 'on' }) }
    }
    Show-Table $rows
}

function Ensure-AliasBin {
    if (-not (Test-Path -LiteralPath $AliasBin)) { New-Item -ItemType Directory -Path $AliasBin -Force | Out-Null }
}

function Write-AliasShim([string] $Name) {
    Ensure-AliasBin
    $shim = Join-Path $AliasBin "$Name.cmd"
    $content = "@echo off`r`npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" $Name %*`r`n"
    Set-Content -LiteralPath $shim -Value $content -Encoding ASCII
}

function Remove-AliasShim([string] $Name) {
    $shim = Join-Path $AliasBin "$Name.cmd"
    if (Test-Path -LiteralPath $shim) { Remove-Item -LiteralPath $shim -Force }
}

function Sync-Aliases {
    $c = Read-Aliases
    Ensure-AliasBin
    $wanted = @(Get-AliasNames $c)
    foreach ($name in $wanted) {
        $e = Get-AliasEntry $c $name
        if ($e.link -eq $false) { Remove-AliasShim $name; Write-Host "off      $name" }
        else { Write-AliasShim $name; Write-Host "linked   $name -> $AliasBin\$name.cmd" }
    }
    Get-ChildItem -LiteralPath $AliasBin -Filter '*.cmd' -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -notin $wanted -and $_.BaseName -ne 'win-claude-or' } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
    $pathParts = @($env:Path -split ';')
    if ($pathParts -notcontains $AliasBin) { Write-Warning "$AliasBin is not in PATH; add it before using ccds/ccqwen directly" }
}

function Set-AliasLinks([string[]] $Items, [bool] $Enable) {
    $c = Read-Aliases
    $names = @($Items | Where-Object { $_ -notin @('-y','--yes') })
    if ($names.Count -eq 0) { $names = @(Get-AliasNames $c) }
    foreach ($name in $names) { $e = Require-Alias $c $name; if ($Enable) { $e.PSObject.Properties.Remove('link'); Write-AliasShim $name; Write-Host "linked   $name" } else { $e | Add-Member -NotePropertyName link -NotePropertyValue $false -Force; Remove-AliasShim $name; Write-Host "unlinked $name" } }
    Save-Json $c $AliasFile
}

function Add-Alias([string[]] $Items) {
    if ($Items.Count -lt 2 -or $Items.Count -gt 3) { Fail 'usage: --add <alias> <model-id> [context]' }
    $name, $model, $context = $Items
    Test-AliasName $name
    $c = Read-Aliases
    if ($null -ne (Get-AliasEntry $c $name)) { Fail "alias '$name' already exists" }
    $info = Get-ModelInfo $model
    if ($context -and $context -notmatch '^\d+$') { Fail 'context must be a whole number of tokens' }
    $entry = [ordered]@{ model=$model }
    if ($context) { $entry.context = [int64]$context } elseif ($info.context_length) { $entry.context = [int64]$info.context_length }
    $c.aliases | Add-Member -NotePropertyName $name -NotePropertyValue ([pscustomobject]$entry)
    Save-Json $c $AliasFile
    Write-Host "added $name -> $model"
    Sync-Aliases
}

function Update-Alias([string[]] $Items) {
    if ($Items.Count -ne 3) { Fail 'usage: --update <alias> <model|context|small> <value>' }
    $name, $property, $value = $Items
    $c = Read-Aliases; $e = Require-Alias $c $name
    if ($property -notin @('model','small','context')) { Fail 'property must be model, small or context' }
    if ($property -eq 'context' -and $value -notmatch '^\d+$') { Fail 'context must be a whole number of tokens' }
    if ($property -in @('model','small')) { [void](Get-ModelInfo $value) }
    $old = $e.$property
    if ($property -eq 'context') { $value = [int64]$value }
    $e.$property = $value
    Save-Json $c $AliasFile
    Write-Host "updated $name`: $property $old -> $value"
}

function Remove-Alias([string[]] $Items) {
    if ($Items.Count -lt 1) { Fail 'usage: --remove <alias>...' }
    $c = Read-Aliases
    foreach ($name in $Items) { [void](Require-Alias $c $name) }
    foreach ($name in $Items) { $c.aliases.PSObject.Properties.Remove($name); Remove-AliasShim $name }
    Save-Json $c $AliasFile
}

function Read-Keys {
    if (-not (Test-Path -LiteralPath $KeysFile)) { return [pscustomobject]@{ active=$null; keys=@() } }
    Get-Content -LiteralPath $KeysFile -Raw | ConvertFrom-Json
}

function Save-KeyConfig($Keys) { Save-Json $Keys $KeysFile }

function Convert-SecureValueToPlain([string] $Value) {
    $secure = ConvertTo-SecureString $Value
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Get-KeyValue([string] $Name) {
    $k = Read-Keys
    $entry = @($k.keys | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
    if ($null -eq $entry) { return $null }
    if ($entry.key -like 'DPAPI:*') { return Convert-SecureValueToPlain $entry.key.Substring(6) }
    $entry.key
}

function Resolve-Key([string] $Ref) {
    $k = Read-Keys
    if ($Ref -match '^\d+$') { $entry = @($k.keys)[([int]$Ref)-1] } else { $entry = @($k.keys | Where-Object { $_.name -eq $Ref }) | Select-Object -First 1 }
    if ($null -eq $entry) { Fail "no key '$Ref' (see --key-list)" }
    $entry
}

function Add-Key([string[]] $Items) {
    if ($Items.Count -lt 1 -or $Items.Count -gt 2) { Fail 'usage: --key-add <name> [key]' }
    $name = $Items[0]; $key = if ($Items.Count -eq 2) { $Items[1] } else { $secret = Read-Host 'OpenRouter API key' -AsSecureString; $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret); try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) } }
    if ($name -notmatch '^[A-Za-z0-9_.-]+$') { Fail 'invalid key name' }
    $test = Invoke-WebRequest -Uri 'https://openrouter.ai/api/v1/key' -Headers @{ Authorization="Bearer $key" } -TimeoutSec 20 -UseBasicParsing
    if ($test.StatusCode -ne 200) { Fail 'OpenRouter rejected this key' }
    $k = Read-Keys
    if (@($k.keys | Where-Object { $_.name -eq $name })) { Fail "key '$name' already exists" }
    $protected = ConvertTo-SecureString $key -AsPlainText -Force | ConvertFrom-SecureString
    $new = [pscustomobject]@{ name=$name; key="DPAPI:$protected" }
    $list = [System.Collections.Generic.List[object]]::new(); @($k.keys) | ForEach-Object { [void]$list.Add($_) }; [void]$list.Add($new); $k.keys=$list
    if (-not $k.active) { $k.active=$name }
    Save-KeyConfig $k; Write-Host "saved key '$name' (active: $($k.active))"
}

function Show-Keys {
    $k=Read-Keys; $i=0; $rows=foreach($e in @($k.keys)){ $i++; $plain=Get-KeyValue $e.name; [pscustomobject]@{ACTIVE=$(if($e.name -eq $k.active){'*'}else{''}); '#'=$i; NAME=$e.name; KEY=$(if($plain.Length -gt 12){$plain.Substring(0,5)+'...'+$plain.Substring($plain.Length-4)}else{'***'})} }; Show-Table $rows
}

function Switch-Key([string[]] $Items) { if($Items.Count -ne 1){Fail 'usage: --key-switch <index|name>'}; $e=Resolve-Key $Items[0]; $k=Read-Keys; $k.active=$e.name; Save-KeyConfig $k; Write-Host "active key: $($e.name)" }

function Remove-Key([string[]] $Items) { if($Items.Count -lt 1){Fail 'usage: --key-remove <index|name>...'}; $k=Read-Keys; $names=@($Items|ForEach-Object{(Resolve-Key $_).name}); $k.keys=@($k.keys|Where-Object{$_.name -notin $names}); if($k.active -in $names){$k.active=$null}; Save-KeyConfig $k }

function Get-RunKey([string] $Override) {
    if ($Override) { return (Resolve-Key $Override | ForEach-Object { Get-KeyValue $_.name }) }
    if ($env:OPENROUTER_API_KEY) { return $env:OPENROUTER_API_KEY }
    $k=Read-Keys; if($k.active){ return Get-KeyValue $k.active }
    $null
}

function Invoke-Claude([string] $Model, [int64] $Context, [string] $Small, [string[]] $ClaudeArgs, [string] $KeyOverride) {
    $key=Get-RunKey $KeyOverride; if(-not $key){Fail 'no OpenRouter key: use --key-add, OPENROUTER_API_KEY or --key-run'}
    $env:ANTHROPIC_BASE_URL='https://openrouter.ai/api'; $env:ANTHROPIC_AUTH_TOKEN=$key; $env:ANTHROPIC_API_KEY=''
    $env:ANTHROPIC_MODEL=$Model; $env:ANTHROPIC_DEFAULT_FABLE_MODEL=$Model; $env:ANTHROPIC_DEFAULT_OPUS_MODEL=$Model; $env:ANTHROPIC_DEFAULT_SONNET_MODEL=$Model; $env:ANTHROPIC_DEFAULT_HAIKU_MODEL=$Small; $env:ANTHROPIC_SMALL_FAST_MODEL=$Small; $env:CLAUDE_CODE_SUBAGENT_MODEL=$Model; $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'; $env:CLAUDECODE=$null
    if($Context){$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS=[string]$Context}else{$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS=$null}
    & claude @ClaudeArgs
    exit $LASTEXITCODE
}

function Show-Help { Get-Content -LiteralPath (Join-Path $ScriptDir 'README.md') -TotalCount 80; Write-Host "`nUsage: win-claude-or <alias|vendor/model> [claude args...]" }

if ($Arguments.Count -eq 0 -or $Arguments[0] -in @('-h','--help')) { Show-Help; exit 0 }
$command=$Arguments[0]; $rest=@($Arguments | Select-Object -Skip 1)
switch ($command) {
    '--list' { Show-Aliases; exit 0 }
    '--sync' { Sync-Aliases; exit 0 }
    '--link' { Set-AliasLinks $rest $true; exit 0 }
    '--unlink' { Set-AliasLinks $rest $false; exit 0 }
    '--add' { Add-Alias $rest; exit 0 }
    '--update' { Update-Alias $rest; exit 0 }
    '--remove' { Remove-Alias $rest; exit 0 }
    '--key-add' { Add-Key $rest; exit 0 }
    '--key-list' { Show-Keys; exit 0 }
    '--key-switch' { Switch-Key $rest; exit 0 }
    '--key-remove' { Remove-Key $rest; exit 0 }
    '--key-run' { if($rest.Count -lt 2){Fail 'usage: --key-run <index|name> <alias|model-id> [claude args...]'}; $keyRef=$rest[0]; $target=$rest[1]; $rest=@($rest|Select-Object -Skip 2); $command=$target; $keyOverride=$keyRef }
}

Ensure-Config
$config=Read-Aliases
if($command -match '/') { $model=$command; $entry=$null } else { $entry=Require-Alias $config $command; $model=$entry.model }
$ctx=if($entry.context){[int64]$entry.context}else{0}; $small=if($entry.small){$entry.small}elseif($config.defaults.small){$config.defaults.small}else{$model}
Invoke-Claude $model $ctx $small $rest $keyOverride
