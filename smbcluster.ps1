<#
    .SYNOPSIS
        Creates a Windows Server 2012R2 SMB3 failover cluster

    .DESCRIPTION
        This script automates the creation of a Windows Server 2012R2
        failover cluster and configures it to use SMB3 storage

    .PARAMETER XenServerHost
        The XenServer host to connect to

    .PARAMETER Nodes
        The VM nodes used to form the cluster

    .NOTES
        Copyright (c) Citrix Systems, Inc. All rights reserved.
        Version 1.0
#>

Param(
    [Parameter(mandatory=$true)] [string]$XenServerHost,
    [Parameter(mandatory=$true)] [string]$UserName,
    [Parameter(mandatory=$true)] [string]$Password,
    [Parameter(mandatory=$true)] [int]$NumNodes

)

#loads the XenServer Powershell SnapIn
function loadPSSnapin(){
     Write-Host "$($MyInvocation.MyCommand): Verifying XenServer PowerShell SnapIn..."
     #check if snapin is installed and registered
     if (Get-PSSnapin -registered | ?{$_.Name -eq "XenServerPSSnapIn"}){
        #load the snapin if it is not loaded
        if ((Get-PSSnapin -Name XenServerPSSnapIn -ErrorAction SilentlyContinue) -eq $null){
            Write-Host "$($MyInvocation.MyCommand): Loading XenServer PowerShell SnapIn..."
            Add-PSSnapin XenServerPSSnapIn
        }
     }else {
        Write-Host "$($MyInvocation.MyCommand): XenServerPSSnapIn not found, please install and register the snapin" `
                                                "Script exiting..."
        exit
     }
}

#
#BEGIN SCRIPT
#
loadPSSnapin

try{
    #Connect to the server
    Write-Host "$($MyInvocation.MyCommand): Connecting to XenServer Host: $XenServerHost"
    $session = Connect-XenServer -Server $XenServerHost -UserName $UserName -Password $Password `
                -NoWarnCertificates -SetDefaultSession -PassThru

    Write-Host "$($MyInvocation.MyCommand): Building $NumNodes cluster nodes"
    #create desired number of VMs(cluster nodes) based on WS2012r2 template
    $template = Get-XenVM | where{$_.name_label -eq "Windows Server 2012 R2"}
    Write-host "pass 1"
    for($i=1 ; $i -le $NumNodes ;$i++){
        $VMname = "WS12R2_node_"+ $i
        $SRname = $VMname+"_SR"
        write-host "pass 2"
        Invoke-XenVM -VM $template -XenAction Clone -NewName $VMname -Async `
                     -PassThru | Wait-XenTask -ShowProgress
        write-host "pass 3"
        $VM = Get-XenVM -Name $VMname
        $SR = Get-XenSR -Name $SRname
        write-host "pass 4"
        $other_config = $VM.other_config
        write-host "pass 5"
        $other_config["disks"] = $other_config["disks"].Replace('sr=""', 'sr="{0}"' -f $SR.uuid)
        write-host "pass 6"
        Set-XenVM -VM $VM -OtherConfig $other_config
        write-host "pass 7"
  
      #provision vm 
      Invoke-XenVM -VM $VM -XenAction Provision -Async -PassThru | Wait-XenTask -ShowProgress 
      write-host "pass 8"

    }
        

        

}catch{
        "Caught the bugger!!!"


}finally{

    #Disconnect from server if there is an active connection
    if($session){
        Write-Host "$($MyInvocation.MyCommand): Disconnecting from XenServer Host: $XenServerHost"
        Disconnect-XenServer -Session $session
    }

    #Remove XenServerPSSnapin
    Write-Host "$($MyInvocation.MyCommand): Removing XenServer PowerShell SnapIn and exiting script"
    Remove-PSSnapin XenServerPSSnapIn
    exit
}





