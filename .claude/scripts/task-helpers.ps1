# Task Management Helpers

function Get-NextTaskNumber {
    $tasksDir = "C:\Users\dusti\dev\tasks"
    $allTasks = @()

    Get-ChildItem -Path "$tasksDir\*" -Directory | ForEach-Object {
        Get-ChildItem -Path $_.FullName -Filter "????_*" | ForEach-Object {
            $name = $_.BaseName
            if ($name -match '^(\d{4})_') {
                $allTasks += [int]$matches[1]
            }
        }
    }

    if ($allTasks.Count -eq 0) {
        return "0001"
    }

    $nextNum = ($allTasks | Measure-Object -Maximum).Maximum + 1
    return $nextNum.ToString("D4")
}

function Get-TasksInState {
    param([string]$State)
    $stateDir = "C:\Users\dusti\dev\tasks\$State"
    if (-not (Test-Path $stateDir)) {
        return @()
    }

    Get-ChildItem -Path $stateDir -Filter "????_*" -File | Sort-Object Name
}

function Read-TaskMetadata {
    param([string]$TaskPath)

    $content = Get-Content -Path $TaskPath -Raw

    $metadata = @{
        title       = ""
        description = ""
        repos       = @()
        prs         = @()
    }

    # Parse frontmatter if it exists
    if ($content -match '---\n([\s\S]*?)\n---') {
        $frontmatter = $matches[1]
        # Parse key: value pairs
        $frontmatter -split '\n' | ForEach-Object {
            if ($_ -match '^\s*(\w+):\s*(.*)$') {
                $key = $matches[1]
                $value = $matches[2].Trim()
                if ($key -eq "repos") {
                    $metadata.repos = @($value -split ',\s*')
                } elseif ($key -eq "prs") {
                    $metadata.prs = @($value -split ',\s*')
                } else {
                    $metadata.$key = $value
                }
            }
        }
    }

    return $metadata
}

function Move-TaskToState {
    param([string]$TaskFile, [string]$FromState, [string]$ToState)

    $fromPath = "C:\Users\dusti\dev\tasks\$FromState\$TaskFile"
    $toPath = "C:\Users\dusti\dev\tasks\$ToState\$TaskFile"

    if (Test-Path $fromPath) {
        Move-Item -Path $fromPath -Destination $toPath
        return $true
    }
    return $false
}

Export-ModuleMember -Function Get-NextTaskNumber, Get-TasksInState, Read-TaskMetadata, Move-TaskToState
