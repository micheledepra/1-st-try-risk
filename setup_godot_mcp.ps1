# setup_godot_mcp.ps1 - Configures Claude Desktop to use godot-mcp
# Run this script once, then restart Claude Desktop

$configDir = "$env:APPDATA\Claude"
$configFile = "$configDir\claude_desktop_config.json"

# Ensure the Claude config directory exists
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    Write-Host "Created directory: $configDir"
}

# Build the new godot server entry
$godotEntry = @{
    command = "node"
    args    = @("C:/Users/mchld/.claude/godot-mcp/build/index.js")
    env     = @{
        GODOT_PATH = "C:/GODOT/Godot_v4.5.1-stable_win64.exe"
    }
}

# Load existing config or start fresh
if (Test-Path $configFile) {
    $config = Get-Content $configFile -Raw | ConvertFrom-Json
    Write-Host "Found existing config, merging..."
} else {
    $config = [PSCustomObject]@{ mcpServers = [PSCustomObject]@{} }
    Write-Host "No existing config found, creating new one..."
}

# Ensure mcpServers key exists
if (-not $config.PSObject.Properties['mcpServers']) {
    $config | Add-Member -MemberType NoteProperty -Name 'mcpServers' -Value ([PSCustomObject]@{})
}

# Add or overwrite the godot entry
$config.mcpServers | Add-Member -MemberType NoteProperty -Name 'godot' -Value $godotEntry -Force

# Write back
$config | ConvertTo-Json -Depth 10 | Set-Content $configFile -Encoding UTF8
Write-Host "Done! Config written to: $configFile"
Write-Host ""
Write-Host "NEXT STEP: Fully quit and restart Claude Desktop, then come back."
