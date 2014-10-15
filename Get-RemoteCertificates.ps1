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
function Get-RemoteCertificates
{
  param(
    [string]$SingleTarget="",
    [switch]$NoDomain=$False
  )

  # set up for terminating condition
  $ErrorActionPreference = "Stop"

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
          + ' which will be used to retrieve remote certificate information'
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

    # Create and execute the command to execute on each machine
    $command = ("
      `$ErrorActionPreference = 'continue'
      try { mkdir '\\localhost\admin$\Temp\certstorage' } catch {}
      Get-ChildItem -Path cert: -Recurse |
        Where-Object { `$_.GetType().Name -eq 'X509Certificate2' } |
        % { [System.IO.file]::WriteAllBytes('\\localhost\admin$\temp\certstorage\' + `$_.Thumbprint + '.cer', (`$_.Export('CERT', 'secret'))) }
    ")

    $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
    $encoded = [Convert]::ToBase64String($bytes)

    Write-Output "[+] Enumerating certificate store on [$Target]"
    $wmic = Invoke-WmiMethod -Credential $cred `
      -ComputerName $Target `
      -Class Win32_Process `
      -Impersonation 4 `
      -Name Create `
      -ArgumentList "powershell -Exec bypass -EncodedCommand $encoded"

    # Delay
    Start-Sleep -s 1

    # Copy back the files
    if (!(Test-Path $Target)) {
      mkdir $Target
    }
    $drive = New-PSDrive -Credential $cred -Name "ZZZ" -PSProvider FileSystem -Root "\\$Target\admin$\temp\certstorage"
    
    # should probably test the return value here
    Copy-Item -Force ZZZ:* $Target
    Remove-PSDrive -Name "ZZZ"

    # Create and execute the command to delete the files
    $command = ("Remove-Item -Force -Recurse '\\localhost\admin$\Temp\certstorage\'")
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
    $encoded = [Convert]::ToBase64String($bytes)
    $wmic = Invoke-WmiMethod -Credential $cred `
      -ComputerName $Target `
      -Class Win32_Process `
      -Impersonation 4 `
      -Name Create `
      -ArgumentList "powershell -Exec bypass -EncodedCommand $encoded"
  }
}
