#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._ArgumentSpecs
#AnsibleRequires -PowerShell ..module_utils._WslUtils
#AnsibleRequires -PowerShell ..module_utils._Distributions

$commonOptions = Get-WslCommandCommonOptionsDict
$moduleOptions = @{
    name = @{ type = "str"; }
}
$spec = @{
    options = $commonOptions + $moduleOptions
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$name = $module.Params.name

$wslExe = Test-WslInstall -module $module


$distributions = Get-DistributionRuntimeInfo -wslExe $wslExe -module $module -name $name
foreach ($distro in (Get-DistributionInstallInfo -name $name).GetEnumerator()) {
    # make sure the local distribution info has the distro the registry mentions.
    # probably not a common scenario but the registry could be stale
    if (-not $distributions.Contains($distro.Key)) { continue }

    $distributions[$distro.Key] += $distro.Value
}

$module.Result.distributions = $distributions
$module.ExitJson()
