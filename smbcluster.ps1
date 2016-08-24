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
    #[Parameter(mandatory=$true)] [int]$NumNodes,
    [Parameter(mandatory=$true)] [string[]]$Nodes
)

if (Get-PSSnapin -registered | ?{$_.Name -eq "XenServerPSSnapIn"}){
    
    #Load the XenServer PSSnapIn
    if ((Get-PSSnapin -Name XenServerPSSnapIn -ErrorAction SilentlyContinue) -eq $null){
        Write-Host "$($MyInvocation.MyCommand): Adding XenServerPSSnapIn PowerShell Snap-in"
        Add-PSSnapin XenServerPSSnapIn
    }
    
    try{
        #Connect to the server
        Write-Host "$($MyInvocation.MyCommand): Connecting to XenServer Host: $XenServerHost"
        $session = Connect-XenServer -Server $XenServerHost -UserName $UserName -Password $Password `
                   -NoWarnCertificates -SetDefaultSession -PassThru
        
        #TESTING :: Rename VMs
        $NodeNum = 1
        foreach ($Node in $Nodes){
            $VM = Get-XenVM -Name $Node
            $NewName = "WS2012r2_Node_"+$NodeNum
            Set-XenVm -VM $VM -NameLabel $NewName
            $NodeNum++
            Write-Host "$($MyInvocation.MyCommand): Name change completed"
            Start-Sleep 5
        }



    }finally{
        #Disconnect from server
        Write-Host "$($MyInvocation.MyCommand): Disconnecting from XenServer Host: $XenServerHost"
        Disconnect-XenServer -Session $session

        #Remove XenServerPSSnapin
        Write-Host "$($MyInvocation.MyCommand): Removing XenServerPSSnapIn PowerShell Snap-in"
        Remove-PSSnapin XenServerPSSnapIn
    }

}else {
    throw "XenServerPSSnapIn not found."
}



