#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._ArgumentSpecs
#AnsibleRequires -PowerShell ..module_utils._WslUtils
#AnsibleRequires -PowerShell ..module_utils._Distributions

$commonOptions = Get-WslCommandCommonOptionsDict
$moduleOptions = @{
    name = @{ type = "str"; required = $true }
    distribution_id = @{ type = "str" }
    state = @{ type = "str"; default = "present"; choices = @("present", "absent") }
    version = @{ type = "int"; choices = @(1, 2); }
    size = @{ type = "int"; }
    location = @{ type = "str"; }
    sparse = @{ type = "bool"; }
    use_ms_store = @{ type = "bool"; default=$true }
    use_fixed_vhd = @{ type = "bool"; default=$false }
    allow_shutdown = @{ type = "bool"; default=$true }
}
$spec = @{
    options = $commonOptions + $moduleOptions
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$name = $module.Params.name
$distributionId = $module.Params.distribution_id
$state = $module.Params.state
$allowShutdown = $module.Params.allow_shutdown

# updatable options
$desiredVersion = $module.Params.version
$desiredSize = $module.params.size
$desiredLocation = $module.params.location
$desiredSparse = $module.params.sparse

$wslExe = Test-WslInstall -module $module


function Install-Distribution {
    $module.Result.changed = $true
    $module.Diff.after = @{ "name" = $name }
    $distroId = if ($distributionId) { $distributionId } else { $name }
    $installParams = [System.Collections.Generic.List[string]]::new()
    $installParams.AddRange(
        [string[]]@("--install", "--no-launch", "-d", "$distroId", "--name", "$name")
    )
    if ($module.params.use_fixed_vhd) { $installParams.Add("--fixed-vhd") }
    if (-not $module.params.use_ms_store) { $installParams.Add("--web-download") }
    if ($desiredVersion) { $installParams.AddRange([string[]]@("--version", "$desiredVersion")) }
    if ($desiredLocation) { $installParams.AddRange([string[]]@("--location", $desiredLocation)) }
    if ($desiredSize) { $installParams.AddRange([string[]]@("--vhd-size", "$($desiredSize)GB")) }

    if ($module.CheckMode) {
        return
    }

    Invoke-WslCommand `
        -wslExe $wslExe `
        -module $module `
        -arguments $installParams

    if ($desiredSparse) {
        if ($allowShutdown) {
            Invoke-WslCommand `
                -wslExe $wslExe `
                -module $module `
                -arguments @("--shutdown")
        }
        Invoke-WslCommand `
            -wslExe $wslExe `
            -module $module `
            -arguments @("--manage", $name, "--set-sparse", "$desiredSparse".ToLower(), "--allow-unsafe")
    }
}


function Remove-Distribution {
    param (
        [object]$currentDistro
    )
    $module.Diff.before = $currentDistro
    $module.Result.changed = $true
    if (-not $module.CheckMode) {
        Invoke-WslCommand `
            -wslExe $wslExe `
            -module $module `
            -arguments @("--unregister", $name)
    }
    return
}



function Invoke-RequiredUpdateCommand {
    if ($allowShutdown) {
        Invoke-WslCommand `
            -wslExe $wslExe `
            -module $module `
            -arguments @("--shutdown")
    }

    if ($module.diff.after.Contains("location")) {
        Invoke-WslCommand `
            -wslExe $wslExe `
            -module $module `
            -arguments @("--manage", $name, "--move", $desiredLocation)
    }
    if ($module.diff.after.Contains("sparse")) {
        Invoke-WslCommand `
            -wslExe $wslExe `
            -module $module `
            -arguments @("--manage", $name, "--set-sparse", "$desiredSparse".ToLower(), "--allow-unsafe")
    }
    if ($module.diff.after.Contains("size")) {
        Invoke-WslCommand `
            -wslExe $wslExe `
            -module $module `
            -arguments @("--manage", $name, "--resize", "$($desiredSize)GB")
    }
    if ($module.diff.after.Contains("version")) {
        Invoke-WslCommand `
            -wslExe $wslExe `
            -module $module `
            -arguments @("--manage", $name, "--set-version", "$desiredVersion")
    }

}


function Update-Distribution {
    param (
        [object]$currentDistro
    )
    $detailedInfo = Get-DistributionInstallInfo -name $name -flat
    $currentDistro = $currentDistro + $detailedInfo
    $module.Diff.before = @{}
    $module.Diff.after = @{}

    $comparableSize = if ($desiredSize) { "$($desiredSize)GB" } else { $null }
    $updatableParams = @(
        ,("version", $desiredVersion, $currentDistro.version)
        ,("size", $comparableSize, $currentDistro.size)
        ,("location", $desiredLocation, $currentDistro.location)
        ,("sparse", $desiredSparse, $currentDistro.is_sparse)
    )
    foreach($updatableParam in $updatableParams) {
        Compare-DesiredVsActual `
            -attributeName $updatableParam[0] `
            -desired $updatableParam[1] `
            -actual $updatableParam[2] `
            -diff $module.diff
    }

    $module.result.changed = ($module.diff.after.Count -gt 0)
    if ($module.CheckMode -or (-not $module.result.changed)) {
        return
    }

    Invoke-RequiredUpdateCommand
}


$currentDistro = Get-DistributionRuntimeInfo -wslExe $wslExe -module $module -name $name -flat

if ($currentDistro -eq $null) {
    if ($module.params.state -eq "present") {
        Install-Distribution | Out-Null
    }
    # otherwise, the state is absent and its already absent
}
else {
    if ($module.params.state -eq "absent") {
        Remove-Distribution -currentDistro $currentDistro | Out-Null
    }
    else {
        Update-Distribution -currentDistro $currentDistro | Out-Null
    }
}

$module.ExitJson()
