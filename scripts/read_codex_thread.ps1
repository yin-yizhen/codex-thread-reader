param(
    [Parameter(Mandatory = $true)]
    [string]$ThreadId,

    [string]$CodexHome = "D:\codex_home",

    [string]$CurrentCwd = "",

    [switch]$IncludeToolEvents,

    [switch]$IncludeSystemMessages
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Get-ThreadId {
    param([string]$Value)

    $match = [regex]::Match($Value, "(?i)(?:codex://threads/)?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})")
    if (-not $match.Success) {
        throw "Could not find a Codex thread id in input: $Value"
    }
    return $match.Groups[1].Value.ToLowerInvariant()
}

function ConvertTo-PlainMessageText {
    param($Content)

    if ($null -eq $Content) {
        return ""
    }

    if ($Content -is [string]) {
        return $Content
    }

    $parts = @()
    foreach ($item in @($Content)) {
        if ($null -ne $item.text) {
            $parts += [string]$item.text
        } elseif ($null -ne $item.content) {
            $parts += [string]$item.content
        }
    }
    return ($parts -join "`n")
}

function Read-SessionIndex {
    param([string]$Root)

    $map = @{}
    $indexPath = Join-Path $Root "session_index.jsonl"
    if (-not (Test-Path -LiteralPath $indexPath)) {
        return $map
    }

    Get-Content -LiteralPath $indexPath -Encoding UTF8 | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) {
            return
        }
        try {
            $row = $_ | ConvertFrom-Json
            if ($row.id) {
                $map[[string]$row.id] = $row
            }
        } catch {
        }
    }
    return $map
}

function Find-SessionFile {
    param(
        [string]$Root,
        [string]$Id
    )

    $sessionsRoot = Join-Path $Root "sessions"
    $archiveRoot = Join-Path $Root "archived_sessions"
    $matches = @()

    foreach ($base in @($sessionsRoot, $archiveRoot)) {
        if (-not (Test-Path -LiteralPath $base)) {
            continue
        }

        $matches += Get-ChildItem -LiteralPath $base -Recurse -Filter "*.jsonl" -File |
            Where-Object { $_.Name -like "*$Id*" }
    }

    if ($matches.Count -gt 0) {
        return ($matches | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    }

    foreach ($base in @($sessionsRoot, $archiveRoot)) {
        if (-not (Test-Path -LiteralPath $base)) {
            continue
        }

        $found = Get-ChildItem -LiteralPath $base -Recurse -Filter "*.jsonl" -File |
            Select-String -SimpleMatch $Id -List |
            Select-Object -First 1
        if ($found) {
            return $found.Path
        }
    }

    return $null
}

$id = Get-ThreadId -Value $ThreadId
$warnings = New-Object System.Collections.Generic.List[string]
$index = Read-SessionIndex -Root $CodexHome
$path = Find-SessionFile -Root $CodexHome -Id $id

if (-not $path) {
    $result = [ordered]@{
        id = $id
        found = $false
        codex_home = $CodexHome
        warnings = @("No local JSONL session file found for thread id.")
    }
    $result | ConvertTo-Json -Depth 8
    exit 0
}

$sessionMeta = $null
$messages = New-Object System.Collections.Generic.List[object]
$eventUserMessages = New-Object System.Collections.Generic.List[object]
$tool_events = New-Object System.Collections.Generic.List[object]
$seenUserEvents = @{}
$encryptedReasoningCount = 0

Get-Content -LiteralPath $path -Encoding UTF8 | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) {
        return
    }

    try {
        $row = $_ | ConvertFrom-Json
    } catch {
        $warnings.Add("Skipped a malformed JSONL row.")
        return
    }

    if ($row.type -eq "session_meta") {
        $sessionMeta = $row.payload
        return
    }

    if ($row.type -eq "response_item") {
        $payload = $row.payload

        if ($payload.type -eq "reasoning" -and $payload.encrypted_content) {
            $encryptedReasoningCount += 1
            return
        }

        if ($payload.type -eq "message") {
            $role = [string]$payload.role
            if (($role -eq "user" -or $role -eq "assistant") -or $IncludeSystemMessages) {
                $text = ConvertTo-PlainMessageText -Content $payload.content
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $messages.Add([ordered]@{
                        timestamp = $row.timestamp
                        role = $role
                        text = $text
                    })
                }
            }
            return
        }

        if ($IncludeToolEvents -and ($payload.type -eq "function_call" -or $payload.type -eq "function_call_output")) {
            $tool_events.Add([ordered]@{
                timestamp = $row.timestamp
                type = $payload.type
                name = $payload.name
                call_id = $payload.call_id
                summary = if ($payload.arguments) { [string]$payload.arguments } elseif ($payload.output) { [string]$payload.output } else { "" }
            })
            return
        }
    }

    if ($row.type -eq "event_msg" -and $row.payload.type -eq "user_message") {
        $text = [string]$row.payload.message
        $key = "$($row.timestamp)|$text"
        if (-not $seenUserEvents.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace($text)) {
            $seenUserEvents[$key] = $true
            $eventUserMessages.Add([ordered]@{
                timestamp = $row.timestamp
                role = "user"
                text = $text
            })
        }
    }
}

if ($messages.Count -eq 0 -and $eventUserMessages.Count -gt 0) {
    foreach ($message in $eventUserMessages) {
        $messages.Add($message)
    }
    $warnings.Add("No response_item messages were found; returned event_msg user messages only.")
}

$title = $null
$updatedAt = $null
if ($index.ContainsKey($id)) {
    $title = $index[$id].thread_name
    $updatedAt = $index[$id].updated_at
}

$cwd = $null
$createdAt = $null
if ($sessionMeta) {
    $cwd = $sessionMeta.cwd
    $createdAt = $sessionMeta.timestamp
}

$cwdMatch = $null
if (-not [string]::IsNullOrWhiteSpace($CurrentCwd) -and -not [string]::IsNullOrWhiteSpace($cwd)) {
    $cwdMatch = ([System.IO.Path]::GetFullPath($CurrentCwd).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($cwd).TrimEnd('\'))
}

if ($encryptedReasoningCount -gt 0) {
    $warnings.Add("Skipped $encryptedReasoningCount encrypted reasoning record(s); encrypted_content cannot be decrypted.")
}

$result = [ordered]@{
    id = $id
    found = $true
    thread_name = $title
    updated_at = $updatedAt
    created_at = $createdAt
    cwd = $cwd
    current_cwd = $CurrentCwd
    cwd_match = $cwdMatch
    path = $path
    message_count = $messages.Count
    messages = @($messages.ToArray())
    tool_event_count = $tool_events.Count
    tool_events = @($tool_events.ToArray())
    warnings = @($warnings.ToArray())
}

$result | ConvertTo-Json -Depth 12
