function Get-DistributionRuntimeInfo {
    <#
    .SYNOPSIS
        Gets runtime information for WSL distributions.
    .DESCRIPTION
        Runs 'wsl --list --verbose' and parses the output to extract
        the name, state, version, and default status of each distribution.
        Can return all distributions or filter by name.
    .PARAMETER wslExe
        The wsl.exe command object returned by Test-WslInstall.
    .PARAMETER module
        The Ansible.Basic.AnsibleModule instance.
    .PARAMETER name
        Optional distribution name to filter results.
    .PARAMETER flat
        If set, returns a single hashtable for the matched distribution
        instead of a dictionary keyed by name. Returns $null if not found.
    .OUTPUTS
        System.Collections.Hashtable. A dictionary of distributions keyed
        by name, or a single hashtable when -flat is used.
    #>
    param (
        [object]$wslExe,
        [object]$module,
        [string]$name,
        [switch]$flat
    )
    $stdout, $stderr = Invoke-WslCommand `
        -wslExe $wslExe `
        -module $module `
        -arguments @("--list", "--verbose")

    $lines = Split-StdText $stdout
    $distributions = @{}
    foreach ($line in ($lines | Select-Object -Skip 1)) {
        if ($line -match '^\s*(\*)?\s*(.+?)\s+(Stopped|Running|Installing|Uninstalling|Converting|Exporting)\s+(\d+)\s*$') {
            $distroName = $Matches[2].Trim()
            if ((-not [string]::IsNullOrEmpty($name)) -and ($name -ne $distroName)) {
                continue
            }
            $distributions[$distroName] = @{
                name = $distroName
                state = $Matches[3]
                version = [int]$Matches[4]
                is_default = ($null -ne $Matches[1])
            }
        }
    }

    if ($flat) {
        if ($distributions.Count -eq 0) {
            return $null
        }
        return $distributions.Values | Select-Object -First 1
    }
    return $distributions
}


function Wait-DistributionState {
    <#
    .SYNOPSIS
        Waits for a WSL distribution to reach a desired state.
    .DESCRIPTION
        Polls Get-DistributionRuntimeInfo at 10-second intervals until the
        distribution reaches the desired state or the timeout is exceeded.
        Throws an error if the timeout is reached.
    .PARAMETER wslExe
        The wsl.exe command object returned by Test-WslInstall.
    .PARAMETER module
        The Ansible.Basic.AnsibleModule instance.
    .PARAMETER name
        The name of the distribution to monitor.
    .PARAMETER desiredState
        The state to wait for (e.g. Stopped, Running).
    .PARAMETER timeout
        Maximum time in seconds to wait. Defaults to 60.
    #>
    param (
        [Parameter(Mandatory)]
        [object]$wslExe,

        [Parameter(Mandatory)]
        [object]$module,

        [Parameter(Mandatory)]
        [string]$name,

        [Parameter(Mandatory)]
        [string]$desiredState,

        [int]$timeout = 60
    )

    $elapsed = 0
    $interval = 10
    while ($elapsed -lt $timeout) {
        $info = Get-DistributionRuntimeInfo -wslExe $wslExe -module $module -name $name -flat
        if ($null -ne $info -and $info.state -eq $desiredState) {
            return
        }
        Start-Sleep -Seconds $interval
        $elapsed += $interval
    }

    $currentState = if ($null -ne $info) { $info.state } else { "not found" }
    throw "Timed out waiting for distribution '$name' to reach state '$desiredState' after $timeout seconds. Current state: $currentState"
}


function Get-VhdFileInfo {
    <#
    .SYNOPSIS
        Gets file information for a VHD file.
    .DESCRIPTION
        Checks if the VHD file exists at the given path and returns its
        sparse attribute and size rounded to the nearest half gigabyte.
    .PARAMETER vhdPath
        The full path to the VHD file.
    .OUTPUTS
        System.Collections.Hashtable. A hashtable with is_sparse and size
        keys, or $null if the file does not exist.
    #>
    param (
        [string]$vhdPath
    )

    if (-not (Test-Path $vhdPath)) { return $null }
    $fileInfo = Get-Item $vhdPath
    return @{
        "is_sparse" = (($fileInfo.Attributes -band [System.IO.FileAttributes]::SparseFile) -ne 0)
        # calculate size to the nearest half or whole number
        "size" = "$([math]::Round($fileInfo.Length / 1GB * 2) / 2)GB"
    }
}


function Get-DistributionInstallInfo {
    param (
        [string]$name,
        [switch]$flat
    )
    $baseRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    $output = @{}
    foreach ($key in (Get-ChildItem -Path $baseRegPath | Where-Object { $_.Property -contains "BasePath" })) {
        $props = Get-ItemProperty $key.PSPath
        $distroName = $props.DistributionName
        if ((-not [string]::IsNullOrEmpty($name)) -and ($name -ne $distroName)) {
            continue
        }
        $data = @{
            location      = $props.BasePath
            default_uid   = $props.DefaultUid
            flavor        = $props.Flavor
            os_version    = $props.OsVersion
            vhd_file_name = $props.VhdFileName
        }

        $vhdInfo = Get-VhdFileInfo -vhdPath (Join-Path $data.location $data.vhd_file_name)
        if ($null -ne $vhdInfo) {
            $data.is_sparse = $vhdInfo.is_sparse
            $data.size = $vhdInfo.size
        }
        $output[$distroName] = $data
    }

    if ($flat) {
        if ($output.Count -eq 0) {
            return $null
        }
        return $output.Values | Select-Object -First 1
    }
    return $output
}
