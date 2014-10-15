<#
  .SYNOPSIS
    Get certificates from remote hosts.
  .PARAMETER SingleTarget
    A specific target to retrieve certificates from
  .PARAMETER NoDomain
    Do not gather targets using ADSI
  .NOTES
    Author: Joff Thyer and Luke Baggett
    Date: October 15, 2014
#>
function Get-RegistryInfo
{
  param(
    [string]$SingleTarget="",
    [switch]$NoDomain=$False
  )

  # set up for terminating condition
  $ErrorActionPreference = "Stop"

  # constant values for registry hives
  $HKROOT = 2147483648
  $HKCU = 2147483649
  $HKLM = 2147483650
  $HKU = 2147483651
  $HKCC = 2147483653
  $HKDD = 2147483654
  $reg_run = "Software\Microsoft\Windows\CurrentVersion\Run"
  $reg_runonce = "Software\Microsoft\Windows\CurrentVersion\RunOnce"

  ## GATHER TARGETS ##
  $Targets = @()
  if(!$NoDomain)
  {
    # Create adsi searching object
    $adsisearcher = [adsisearcher]'objectclass=computer'
    # Add each hostname to the list of targets
    # seems like a fully qualified target name presents a problem
    # when using PSDrive.  So we are using just the "name" property.
    $adsisearcher.FindAll() | % {$Targets += $($_.properties.name)}
  }

  # Add the single target to the list, if one was specified
  if($SingleTarget -ne "")
  {
    $Targets += $SingleTarget
  }

  # If there are no targets at this point something went wrong
  if($Targets.Count -lt 1)
  {
    Write-Error "No targets found"
  }

  # get a credential
  $msg = 'Please enter a domain administrator credential ' `
          + ' which will be used to retrieve remote registry information'
  $cred = Get-Credential -Message $msg
  
  foreach($Target in $Targets)
  {
    try {
      $wmic = Get-WmiObject Win32_OperatingSystem -Credential $cred -ComputerName $Target
    }
    catch {
      Write-Output "[-] Skipping host [$Target]"
      continue
    }

    Write-Output "[+] Getting list of software from [$Target]"
    $software = Get-WmiObject Win32_Product -Credential $cred -ComputerName $Target
    $software | format-list -property Name, Version

    Write-Output "[+] Registry key [$reg_run] from [$Target]"
    $registry = Get-WmiObject StdRegProv -Namespace Root/Default -Credential $cred -ComputerName $Target -List
    $enum = $registry.EnumValues($HKLM, $reg_run)
    ForEach ($key in $enum.sNames) {
      $value = ($registry.GetStringValue($HKLM, $reg_run, $key)).sValue
      Write-Output "  [+] $reg_run : $key = $value"
    }

    Write-Output "[+] Registry key [$reg_runonce] from [$Target]"
    $enum = $registry.EnumValues($HKLM, $reg_runonce)
    ForEach ($key in $enum.sNames) {
      $value = ($registry.GetStringValue($HKLM, $reg_runonce, $key)).sValue
      Write-Output "  [+] $reg_run : $key = $value"
    }
  }
}
